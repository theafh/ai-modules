#!/usr/bin/env python3
"""Sonnet worker-runner for guardrail_audit behavioral evals.

Stages a sandbox, runs a pinned-sonnet `claude -p` worker that loads
guardrail_audit (which reads the guardrail hub via <authority>), then
grades byte-identity and response markers with grade.sh.

Usage:
    python3 tests/guardrail_audit/evals/run.py [eval_id ...]
      [--model claude-sonnet-4-6] [--timeout 300] [--claude-bin claude]
      [--force] [--no-cache]
"""

from __future__ import annotations

import argparse
import datetime
import json
import pathlib
import subprocess
import sys
import time

THIS = pathlib.Path(__file__).resolve().parent
STAGE = THIS / "stage.sh"
GRADE = THIS / "grade.sh"
WORKSPACE = THIS / "workspace"

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import eval_cache  # noqa: E402
from worker_auth import preflight_auth, worker_env  # noqa: E402
from worker_io import as_text  # noqa: E402  (shared; tests/ is gitignored)

DEFAULT_IDS = [
    "presence_gate",
    "doc_vs_doc",
    "doc_vs_code",
    "direction_target",
    "missing_testing",
    "nature_mismatch",
]

WORKER_PROMPT = """\
You are running an automated skill regression eval. Do exactly this:

1. Read the skill definition file in full: {skill_path}
2. Follow that skill's <authority> block: also read the hub skill at
   {hub_path} (and its references/ as needed) rather than inventing the
   doc set, hierarchy, format, orient, suggest, or consumption rules.
3. Carry out the user request below, operating only inside the current
   working directory ({workdir}):

{prompt}

4. Edit no file in the working directory. Report findings only.
"""


def source_roots_for(skill_path: str):
    skill_dir = pathlib.Path(skill_path).parent
    skills = skill_dir.parent
    return sorted({skill_dir, skills / "guardrail"})


def stage(eval_id: str, target: pathlib.Path) -> dict:
    out = subprocess.check_output(
        ["bash", str(STAGE), eval_id, str(target)],
        text=True,
    )
    env: dict[str, str] = {}
    for line in out.splitlines():
        if "=" not in line:
            continue
        key, raw = line.split("=", 1)
        env[key] = subprocess.check_output(
            ["bash", "-c", f"printf %s {raw}"], text=True
        ).rstrip("\n")
    return env


def worker_completed(rc: int, stdout: str) -> bool:
    return rc == 0 and bool(stdout.strip())


def run_one(eval_id: str, run_dir: pathlib.Path, claude_bin: str,
            model: str, timeout: int, cache, force: bool):
    eval_dir = run_dir / eval_id
    target = eval_dir / "sandbox"
    target.mkdir(parents=True, exist_ok=True)

    staged = stage(eval_id, target)
    workdir = staged["sandbox_proj"]

    key = None
    if cache is not None:
        key = eval_cache.content_key(
            source_roots=source_roots_for(staged["skill_path"]),
            harness_dir=THIS, model=model, eval_id=eval_id, prompt=staged["prompt"],
        )
        if not force:
            hit = cache.lookup(eval_id, key)
            if hit is not None:
                eval_cache.write_replay_artifacts(eval_dir, hit)
                verdict = "PASS" if hit["passed"] else "FAIL"
                print(f"  [{eval_id}] CACHED {verdict} "
                      f"(graded {hit.get('graded_at', '?')}, "
                      f"model={hit.get('model', '?')}) — skipped claude -p; "
                      "--force to re-run\n", flush=True)
                return hit["passed"], True

    prompt = WORKER_PROMPT.format(
        skill_path=staged["skill_path"],
        hub_path=staged["hub_path"],
        workdir=workdir,
        prompt=staged["prompt"],
    )

    cmd = [claude_bin, "-p", "--permission-mode", "bypassPermissions"]
    if model:
        cmd += ["--model", model]
    cmd.append(prompt)

    print(f"  [{eval_id}] running claude -p "
          f"(model={model or '<cli-default>'}) ...", flush=True)
    start = time.time()
    try:
        result = subprocess.run(
            cmd, cwd=workdir, env=worker_env(), capture_output=True,
            text=True, timeout=timeout
        )
        rc, stdout, stderr = result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired as e:
        rc = -1
        stdout = as_text(e.stdout)
        stderr = as_text(e.stderr) + f"\n[TIMEOUT after {timeout}s]"
    duration_s = time.time() - start

    (eval_dir / "response.txt").write_text(stdout)
    (eval_dir / "stderr.txt").write_text(stderr)
    (eval_dir / "timing.json").write_text(json.dumps({
        "eval_id": eval_id,
        "duration_s": duration_s,
        "claude_rc": rc,
        "model": model or "<cli-default>",
    }, indent=2))

    grade = subprocess.run(
        ["bash", str(GRADE), eval_id, workdir, str(eval_dir / "response.txt")],
        capture_output=True, text=True
    )
    (eval_dir / "grading.txt").write_text(grade.stdout + grade.stderr)
    print(grade.stdout, end="", flush=True)
    grade_passed = grade.returncode == 0
    completed = worker_completed(rc, stdout)
    passed = grade_passed and completed

    if not completed:
        why = ("timeout" if "[TIMEOUT" in stderr
               else "empty response" if not stdout.strip()
               else f"worker rc={rc}")
        print(f"  [{eval_id}] FAIL — worker did not complete ({why})\n",
              flush=True)
    else:
        print(f"  [{eval_id}] {'PASS' if passed else 'FAIL'} (worker rc={rc})\n",
              flush=True)

    if cache is not None and completed and key is not None:
        cache.record(eval_id, key, passed=passed, model=model or "<cli-default>",
                     duration_s=duration_s, worker_rc=rc,
                     grading_output=grade.stdout + grade.stderr,
                     response_excerpt=stdout[:eval_cache.RESPONSE_EXCERPT_CHARS])
    return passed, False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ids", nargs="*", default=None)
    parser.add_argument("--model", default="claude-sonnet-4-6")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--claude-bin", default="claude")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--no-cache", action="store_true")
    args = parser.parse_args()

    ids = args.ids if args.ids else DEFAULT_IDS
    cache = None if args.no_cache else eval_cache.EvalCache(THIS / ".eval_cache")

    preflight_auth(args.claude_bin)

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{ts}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")

    failures = []
    for eval_id in ids:
        ok, _cached = run_one(
            eval_id, run_dir, args.claude_bin, args.model, args.timeout,
            cache, args.force,
        )
        if not ok:
            failures.append(eval_id)

    if failures:
        print("FAILED:", ", ".join(failures))
        return 1
    print("All evals passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
