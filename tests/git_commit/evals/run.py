#!/usr/bin/env python3
"""Sonnet worker-runner for the git_commit behavioral evals.

Phase 2 (the skill actually running) used to be operator-driven in the
host session, i.e. on whatever model the session inherited. This runner
instead spawns one pinned-sonnet `claude -p` worker per eval, so the
skill *under test* always runs on the same cheap, stable model. The
meta level on top — the deterministic `grade.sh`, and any prose-verdict
confirmation the operator does by reading `response.txt` — stays on the
inherited model (and `grade.sh` itself uses no model at all).

Per eval the runner:

1. Stages a fresh sandbox via `stage.sh <id> <target>` and reads back
   `sandbox_repo`, `skill_path`, `prompt`.
2. Runs `claude -p --model <sonnet> --permission-mode bypassPermissions`
   with the sandbox repo as the working directory and a prompt that
   tells the worker to load the SKILL.md at `skill_path` and apply it.
3. Captures `response.txt` / `stderr.txt` / `timing.json` under
   `workspace/run-<ts>/<id>/`.
4. Grades the post-run sandbox with `grade.sh <id> <sandbox_repo>`.

Exit code is 0 only when every eval's worker completed cleanly (CLI rc 0
with a real response) AND its deterministic grade passed. A timed-out or
crashed worker fails the eval regardless of grade.sh, which would
otherwise pass on the partially-correct sandbox state an aborted run left.
The prose-verdict expectations in evals.json remain operator-confirmed
from the captured `response.txt`.

Usage:
    python3 tests/git_commit/evals/run.py [eval_id ...]   # default 1..7
      [--model claude-sonnet-4-6]   # '' inherits the CLI default
      [--timeout 300] [--claude-bin claude]
"""

from __future__ import annotations

import argparse
import datetime
import json
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


def source_roots_for(skill_path: str):
    """git_commit is self-contained: the SKILL.md the worker loads, its
    scripts/, and references/ all live in the one skill dir, so that dir is the
    whole artifact-under-test for the cache key."""
    return [pathlib.Path(skill_path).parent]


DEFAULT_IDS = ["1", "2", "3", "4", "5", "6", "7"]

WORKER_PROMPT = """\
You are running an automated skill regression eval. Do exactly this:

1. Read the skill definition file in full: {skill_path}
2. Follow that skill's instructions exactly as written. Resolve any
   bundled scripts it references relative to that SKILL.md's directory.
3. Carry out the user request below, operating only inside the current
   working directory ({workdir}):

{prompt}
"""


def stage(eval_id: str, target: pathlib.Path) -> dict:
    """Run stage.sh and read back the staged values. stage.sh prints
    printf-%q-quoted `name=value` lines meant to be `eval`'d in bash, so
    we let bash eval them and re-emit the raw values NUL-separated."""
    emit = (
        f'eval "$({shlex.quote(str(STAGE))} {shlex.quote(eval_id)} '
        f'{shlex.quote(str(target))})"; '
        'printf "%s\\0%s\\0%s\\0" "$sandbox_repo" "$skill_path" "$prompt"'
    )
    out = subprocess.run(
        ["bash", "-c", emit], capture_output=True, text=True, check=True
    ).stdout
    sandbox_repo, skill_path, prompt, _ = out.split("\0")
    return {"sandbox_repo": sandbox_repo, "skill_path": skill_path, "prompt": prompt}


def worker_completed(rc: int, stdout: str) -> bool:
    """Whether a worker run is trustworthy for grading. The CLI must have
    exited 0 and produced a final response. A non-zero rc (timeout → -1,
    crash, API error) or an empty response means the skill did not finish,
    so grade.sh's checks on the resulting sandbox reflect only partial state
    and must not count as a pass."""
    return rc == 0 and bool(stdout.strip())


def run_one(eval_id: str, run_dir: pathlib.Path, claude_bin: str,
            model: str, timeout: int, cache, force: bool):
    eval_dir = run_dir / eval_id
    target = eval_dir / "sandbox"
    target.mkdir(parents=True, exist_ok=True)

    staged = stage(eval_id, target)
    workdir = staged["sandbox_repo"]

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
                print(f"  [eval-{eval_id}] CACHED {verdict} "
                      f"(graded {hit.get('graded_at', '?')}, "
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

    print(f"  [eval-{eval_id}] running claude -p (model={model or '<cli-default>'}) ...",
          flush=True)
    start = time.time()
    try:
        result = subprocess.run(
            cmd, cwd=workdir, env=worker_env(), capture_output=True, text=True, timeout=timeout
        )
        rc, stdout, stderr = result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired as e:
        rc = -1
        stdout = e.stdout or ""
        stderr = (e.stderr or "") + f"\n[TIMEOUT after {timeout}s]"
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
        print(f"  [eval-{eval_id}] FAIL — worker did not complete ({why}); "
              f"grade.sh ran on partial sandbox state and cannot be trusted "
              f"(grade alone would have said {'PASS' if grade_passed else 'FAIL'})\n",
              flush=True)
    else:
        print(f"  [eval-{eval_id}] {'PASS' if passed else 'FAIL'} (worker rc={rc})\n",
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
                        help="Eval ids to run (default: 1 2 3 4 5 6 7)")
    parser.add_argument("--model", default="claude-sonnet-4-6",
                        help="Worker model for the skill under test "
                             "(default: claude-sonnet-4-6). '' inherits the "
                             "CLI default. Grading stays model-free.")
    parser.add_argument("--timeout", type=int, default=300,
                        help="Per-eval worker timeout in seconds (default 300).")
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

    # Sequential on purpose: grade.sh's TMPDIR straggler check would
    # cross-talk if two git_commit workers ran concurrently.
    results = {i: run_one(i, run_dir, args.claude_bin, args.model, args.timeout,
                          cache, args.force)
               for i in ids}

    ok = sum(1 for passed, _ in results.values() if passed)
    cached_n = sum(1 for _, was_cached in results.values() if was_cached)
    print("=" * 56)
    print(f"graded: {ok}/{len(results)} evals passed ({cached_n} from cache)")
    for i, (passed, was_cached) in results.items():
        print(f"  eval-{i}: {'PASS' if passed else 'FAIL'}{' (cached)' if was_cached else ''}")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
