#!/usr/bin/env python3
"""Sonnet worker-runner for the task-family behavioral evals.

Phase 2 (the skill actually running) used to be operator-driven in the
host session, i.e. on whatever model the session inherited. This runner
instead spawns one pinned-sonnet `claude -p` worker per eval, so the
skill *under test* always runs on the same cheap, stable model. The
meta level on top — the deterministic `grade.sh`, and any prose-verdict
confirmation the operator does by reading `response.txt` — stays on the
inherited model (and `grade.sh` itself uses no model at all).

Per eval the runner:

1. Stages a fresh sandbox via `stage.sh <id> <target>` and reads back
   `sandbox_proj`, `skill_name`, `skill_path`, `prompt`.
2. Runs `claude -p --model <sonnet> --permission-mode bypassPermissions`
   with the sandbox project as the working directory (so the skill's
   discover_tasks.sh resolves the sandbox, never the real repo) and a
   prompt that tells the worker to load the SKILL.md at `skill_path`.
3. Captures `response.txt` / `stderr.txt` / `timing.json` under
   `workspace/run-<ts>/<id>/`.
4. Grades the post-run sandbox with `grade.sh <id> <sandbox_proj>`.

Exit code is 0 only when every eval's worker completed cleanly (CLI rc 0
with a real response) AND its deterministic grade passed. A timed-out or
crashed worker fails the eval regardless of grade.sh: grade.sh then sees
only partial sandbox state (e.g. an early status stamp an aborted loop
left behind), which could otherwise masquerade as a clean pass.
The output-verdict expectations in evals.json (the literal
`# General assessment`, `Gaps:`, `Success: full task compliance
confirmed.`, `audit complete — …` strings) remain operator-confirmed
from the captured `response.txt`.

Usage:
    python3 tests/task/evals/run.py [eval_id ...]
      # default: every `id` in evals.json, derived at startup, so a newly
      #          authored eval joins the suite without editing this file
      [--model claude-sonnet-4-6]   # '' inherits the CLI default
      [--timeout 600] [--claude-bin claude]
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import pathlib
import shlex
import subprocess
import sys
import time

THIS = pathlib.Path(__file__).resolve().parent
STAGE = THIS / "stage.sh"
GRADE = THIS / "grade.sh"
WORKSPACE = THIS / "workspace"

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import eval_cache  # noqa: E402  (shared local test helper; tests/ is gitignored)
from worker_auth import preflight_auth, worker_env  # noqa: E402  (shared; tests/ is gitignored)
from worker_io import as_text  # noqa: E402  (shared; tests/ is gitignored)


def source_roots_for(skill_path: str):
    """A task-family eval loads one sibling skill, which reads the base `task`
    skill via its <authority> step and (for the auto_* siblings) spawns agents.
    Hash the loaded sibling, the base hub, and the agents dir together so an edit
    to the base skill or an agent invalidates the cache too — not just an edit to
    the loaded sibling. Over-inclusion only forces an occasional extra run; it can
    never serve a stale pass."""
    skill_dir = pathlib.Path(skill_path).parent        # .../skills/<skill>
    skills = skill_dir.parent                          # .../skills
    roots = {skill_dir, skills / "task"}               # loaded sibling + base hub
    agents = skills.parent / "agents"                  # .../ai_dev/agents
    if agents.is_dir():
        roots.add(agents)
    return sorted(roots)


def eval_timeout(eval_id: str, default: int) -> int:
    """Per-eval worker timeout from evals.json, falling back to the CLI default.

    One global ceiling has to serve both a 2-minute `task_create` run and the
    `task_auto_check` repair loop, so a ceiling low enough to keep the fast
    evals honest guarantees a timeout on the slow ones — and a timed-out worker
    is scored FAIL regardless of its grade. An eval that is structurally slower
    than its peers declares its own budget here instead of forcing the whole
    suite up to its worst case.
    """
    with open(THIS / "evals.json", encoding="utf-8") as fh:
        for e in json.load(fh)["evals"]:
            if e["id"] == eval_id:
                return int(e.get("timeout", default))
    return default


def _all_eval_ids():
    """Every `id` in evals.json, in authoring order.

    Derived rather than hand-listed: a hand-maintained default set silently
    drops any eval added to evals.json without a matching edit here, and a
    regression suite that skips evals reports a clean tree it never checked.
    Deriving makes "the suite" mean "every eval defined", so a new entry is
    covered the moment it is authored. Narrow a run by naming ids on the
    command line.
    """
    with open(THIS / "evals.json", encoding="utf-8") as fh:
        return [e["id"] for e in json.load(fh)["evals"]]


DEFAULT_IDS = _all_eval_ids()

WORKER_PROMPT = """\
You are running an automated skill regression eval. Do exactly this:

1. Read the skill definition file in full: {skill_path}
2. Follow that skill's instructions exactly as written. Resolve any
   bundled scripts it references relative to that SKILL.md's directory.
3. Carry out the user request below, operating only inside the current
   working directory ({workdir}) and its tasks/ tree:

{prompt}
"""


def stage(eval_id: str, target: pathlib.Path) -> dict:
    """Run stage.sh and read back the staged values. stage.sh prints
    printf-%q-quoted `name=value` lines meant to be `eval`'d in bash, so
    we let bash eval them and re-emit the raw values NUL-separated."""
    emit = (
        f'eval "$({shlex.quote(str(STAGE))} {shlex.quote(eval_id)} '
        f'{shlex.quote(str(target))})"; '
        'printf "%s\\0%s\\0%s\\0%s\\0" '
        '"$sandbox_proj" "$skill_name" "$skill_path" "$prompt"'
    )
    out = subprocess.run(
        ["bash", "-c", emit], capture_output=True, text=True, check=True
    ).stdout
    sandbox_proj, skill_name, skill_path, prompt, _ = out.split("\0")
    return {
        "sandbox_proj": sandbox_proj, "skill_name": skill_name,
        "skill_path": skill_path, "prompt": prompt,
    }


def worker_completed(rc: int, stdout: str) -> bool:
    """Whether a worker run is trustworthy for grading. The CLI must have
    exited 0 and produced a final response. A non-zero rc (timeout → -1,
    crash, API error) or an empty response means the skill did not finish,
    so grade.sh's checks on the resulting sandbox reflect only partial state
    and must not count as a pass — a timed-out worker that stamped an early
    status could otherwise masquerade as a clean 'surfaced-stuck' verdict."""
    return rc == 0 and bool(stdout.strip())


def run_one(eval_id: str, run_dir: pathlib.Path, claude_bin: str,
            model: str, timeout: int, cache, force: bool):
    timeout = eval_timeout(eval_id, timeout)
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
                      f"(skill={staged['skill_name']}, "
                      f"graded {hit.get('graded_at', '?')}, "
                      f"model={hit.get('model', '?')}) — skipped claude -p; "
                      "--force to re-run\n", flush=True)
                return hit["passed"], True

    prompt = WORKER_PROMPT.format(
        skill_path=staged["skill_path"], workdir=workdir, prompt=staged["prompt"]
    )

    cmd = [claude_bin, "-p", "--permission-mode", "bypassPermissions"]
    if model:
        cmd += ["--model", model]
    cmd.append(prompt)

    print(f"  [{eval_id}] running claude -p (skill={staged['skill_name']}, "
          f"model={model or '<cli-default>'}) ...", flush=True)
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
        "skill_name": staged["skill_name"],
        "duration_s": duration_s,
        "claude_rc": rc,
        "model": model or "<cli-default>",
    }, indent=2))

    grade = subprocess.run(
        ["bash", str(GRADE), eval_id, workdir], capture_output=True, text=True
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
        print(f"  [{eval_id}] FAIL — worker did not complete ({why}); "
              f"grade.sh ran on partial sandbox state and cannot be trusted "
              f"(grade alone would have said {'PASS' if grade_passed else 'FAIL'})\n",
              flush=True)
    else:
        print(f"  [{eval_id}] {'PASS' if passed else 'FAIL'} (worker rc={rc})\n",
              flush=True)

    # Cache only a conclusive verdict from a completed worker: a timeout or
    # crash is transient/environmental, not a property of the inputs, so
    # caching it would replay a spurious verdict on a later clean run.
    if cache is not None and completed:
        cache.record(eval_id, key, passed=passed, model=model or "<cli-default>",
                     duration_s=duration_s, worker_rc=rc,
                     grading_output=grade.stdout + grade.stderr,
                     response_excerpt=stdout[:eval_cache.RESPONSE_EXCERPT_CHARS])
    return passed, False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ids", nargs="*", default=None,
                        help="Eval ids to run (default: every id in DEFAULT_IDS)")
    parser.add_argument("--model", default="claude-sonnet-4-6",
                        help="Worker model for the skill under test "
                             "(default: claude-sonnet-4-6). '' inherits the "
                             "CLI default. Grading stays model-free.")
    parser.add_argument("--timeout", type=int, default=1800,
                        help="Default per-eval worker timeout in seconds. "
                             "evals/README.md documents the fix_coherence "
                             "reconcile evals as wanting 1800s, so the "
                             "default performs the documented run rather "
                             "than needing the flag. An eval carrying its "
                             "own \"timeout\" in evals.json overrides this.")
    parser.add_argument("--claude-bin", default="claude")
    parser.add_argument("--force", action="store_true",
                        help="Ignore cached verdicts and re-run every eval, "
                             "refreshing the cache with the new result.")
    parser.add_argument("--no-cache", action="store_true",
                        help="Neither read nor write the verdict cache.")
    args = parser.parse_args()

    ids = args.ids if args.ids else DEFAULT_IDS
    cache = None if args.no_cache else eval_cache.EvalCache(THIS / ".eval_cache")

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{ts}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")
    print(f"Worker model: {args.model or '<cli-default>'}; evals: {ids}")
    cache_mode = "off" if cache is None else ("force-refresh" if args.force else "on")
    print(f"Verdict cache: {cache_mode}\n")

    preflight_auth(args.claude_bin, args.model)

    # Sequential on purpose: keeps each worker's sandbox isolation
    # checks unambiguous and the host filesystem quiet.
    results = {i: run_one(i, run_dir, args.claude_bin, args.model, args.timeout,
                          cache, args.force)
               for i in ids}

    ok = sum(1 for passed, _ in results.values() if passed)
    cached_n = sum(1 for _, was_cached in results.values() if was_cached)
    print("=" * 56)
    print(f"graded: {ok}/{len(results)} evals passed ({cached_n} from cache)")
    for i, (passed, was_cached) in results.items():
        print(f"  {i}: {'PASS' if passed else 'FAIL'}{' (cached)' if was_cached else ''}")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
