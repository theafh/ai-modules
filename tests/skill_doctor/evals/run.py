#!/usr/bin/env python3
"""Vendor-aware worker runner for the skill_doctor behavioral evals.

Modeled on tests/git_commit/evals/run.py: one vendor-resolved print-mode
worker runs per eval, so the skill under test uses one explicit worker policy
each run. By default that means the Cursor worker (`agent -p`, model
`auto`); `--vendor claude` (model `sonnet`) runs where Claude is needed or asked for, and `--model ''` inherits the vendor CLI default. The deterministic `grade.sh` on top uses
no model at all.

Per eval the runner:

1. Stages a fresh sandbox via `stage.sh <id> <target>` and reads back
   `sandbox_repo`, `skill_path`, `prompt`.
2. Micro-deploys the skill under test and its declared companion skills
   through the deploy script into a scratch home, then runs a
   vendor-resolved print-mode worker with the sandbox repo as the working
   directory.
3. Captures `response.txt` / `stderr.txt` / `timing.json` (with the
   `artefacts_read_from_micro_deployment` integrity record) under
   `workspace/run-<ts>/<id>/`.
4. Grades with `grade.sh <id> <sandbox_repo> <response.txt>` — the sandbox
   checksum manifest proves the check-only contract, and the response text
   carries the resolved-target-set and ordering expectations.

Exit code is 0 only when every eval's worker completed cleanly (CLI rc 0 with
a real response) AND its deterministic grade passed.

Usage:
    python3 tests/skill_doctor/evals/run.py [eval_id ...]
      [--vendor claude|cursor] [--model sonnet|auto|'']
      [--timeout 420] [--worker-bin <bin>] [--force] [--no-cache]
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
WORKSPACE = THIS.parent / "workspace"

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import eval_cache  # noqa: E402  (shared local test helper; tests/ is gitignored)
import micro_deploy  # noqa: E402  (shared micro-deployment helper)
import vendor  # noqa: E402  (shared vendor helper)

EVALS_JSON = THIS / "evals.json"

ARTEFACTS = ["skill_doctor", "ai_instruction_formatting", "ai_instruction_writing"]


def all_eval_ids() -> list[str]:
    """Every id in evals.json, in file order — the default run set.

    Derived rather than frozen: a hand-maintained subset here silently ran
    half the suite while still printing a clean `graded: N/N` line, so a
    newly added eval looked covered when nothing had run it.
    """
    data = json.loads(EVALS_JSON.read_text())
    return [e["id"] for e in data["evals"]]

WORKER_PROMPT = """\
You are running an automated skill regression eval. Do exactly this:

1. Read the skill definition file in full: {skill_path}
2. Follow that skill's instructions exactly as written. Resolve any
   bundled scripts it references relative to that SKILL.md's directory.
3. Carry out the user request below, treating the current working
   directory ({workdir}) as the repository under check and operating
   only inside it:

{prompt}
"""


def source_roots_for():
    """The micro-deployed skill trees are the artefacts under test for the
    cache key."""
    return micro_deploy.source_roots_for(ARTEFACTS)


def stage(eval_id: str, target: pathlib.Path) -> dict:
    """Run stage.sh and read back the staged values. stage.sh prints
    printf-%q-quoted `name=value` lines meant to be `eval`'d in bash, so we
    let bash eval them and re-emit the raw values NUL-separated."""
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
    """Whether a worker run is trustworthy for grading. A non-zero rc
    (timeout, crash, API error) or an empty response means the skill did not
    finish, so the graded state reflects only partial work."""
    return rc == 0 and bool(stdout.strip())


def run_one(eval_id: str, run_dir: pathlib.Path, resolved: vendor.Resolved,
            timeout: int, cache, force: bool):
    eval_dir = run_dir / eval_id
    target = eval_dir / "sandbox"
    target.mkdir(parents=True, exist_ok=True)

    staged = stage(eval_id, target)
    workdir = staged["sandbox_repo"]
    model_label = resolved.worker_model or "<inherit>"

    key = None
    if cache is not None:
        key = eval_cache.content_key(
            source_roots=source_roots_for(),
            harness_dir=THIS, model=resolved.worker_model, eval_id=eval_id,
            prompt=staged["prompt"],
        )
        if not force:
            hit = cache.lookup(eval_id, key)
            if hit is not None:
                eval_cache.write_replay_artifacts(eval_dir, hit)
                verdict = "PASS" if hit["passed"] else "FAIL"
                print(f"  [{eval_id}] CACHED {verdict} "
                      f"(graded {hit.get('graded_at', '?')}, "
                      f"model={hit.get('model', '?')}) — skipped {resolved.config.label}; "
                      "--force to re-run\n", flush=True)
                return hit["passed"], True

    print(f"  [{eval_id}] running {resolved.config.label} (model={model_label}) ...",
          flush=True)
    start = time.time()
    with micro_deploy.micro_deploy(
        resolved.vendor, ARTEFACTS, pathlib.Path(workdir), preflight=False
    ) as md:
        prompt = WORKER_PROMPT.format(
            skill_path=md.path_map["skill_doctor"], workdir=workdir,
            prompt=staged["prompt"],
        )
        worker = micro_deploy.run_worker(
            vendor_name=resolved.vendor, bin_name=resolved.bin,
            model=resolved.worker_model, prompt=prompt, deploy=md,
            timeout=timeout, cwd=pathlib.Path(workdir),
        )
        rc, stdout, stderr = worker.returncode, worker.stdout, worker.stderr
        integrity = micro_deploy.integrity_record(
            worker.read_paths, worker.out_of_set_paths
        )
    duration_s = time.time() - start

    response_path = eval_dir / "response.txt"
    response_path.write_text(stdout)
    (eval_dir / "stderr.txt").write_text(stderr)
    (eval_dir / "timing.json").write_text(json.dumps({
        "eval_id": eval_id,
        "duration_s": duration_s,
        "worker_rc": rc,
        "claude_rc": rc,
        "model": model_label,
        "artefacts_read_from_micro_deployment": integrity,
    }, indent=2))

    grade = subprocess.run(
        ["bash", str(GRADE), eval_id, workdir, str(response_path)],
        capture_output=True, text=True,
    )
    (eval_dir / "grading.txt").write_text(grade.stdout + grade.stderr)
    print(grade.stdout, end="", flush=True)
    grade_passed = grade.returncode == 0
    completed = worker_completed(rc, stdout)
    passed = grade_passed and completed and integrity["passed"]

    if not completed:
        why = ("timeout" if "[TIMEOUT" in stderr
               else "empty response" if not stdout.strip()
               else f"worker rc={rc}")
        print(f"  [{eval_id}] FAIL — worker did not complete ({why}); "
              f"grade.sh ran on partial state and cannot be trusted "
              f"(grade alone would have said {'PASS' if grade_passed else 'FAIL'})\n",
              flush=True)
    elif not integrity["passed"]:
        print(f"  [{eval_id}] FAIL — worker read artefacts outside the "
              f"micro-deployment: {integrity['out_of_set']}\n", flush=True)
    else:
        print(f"  [{eval_id}] {'PASS' if passed else 'FAIL'} (worker rc={rc})\n",
              flush=True)

    # Cache only a conclusive verdict from a completed worker: a timeout or
    # crash is environmental, not a property of the inputs.
    if cache is not None and completed:
        cache.record(
            eval_id,
            key,
            passed=passed,
            model=model_label,
            duration_s=duration_s,
            worker_rc=rc,
            grading_output=grade.stdout + grade.stderr,
            response_excerpt=stdout[:eval_cache.RESPONSE_EXCERPT_CHARS],
        )
    return passed, False


def main() -> int:
    known_ids = all_eval_ids()

    parser = argparse.ArgumentParser()
    parser.add_argument("ids", nargs="*", default=None,
                        help="Eval ids to run (default: every id in "
                             f"evals.json — {' '.join(known_ids)})")
    vendor.add_vendor_arguments(parser)
    parser.add_argument("--timeout", type=int, default=420,
                        help="Per-eval worker timeout in seconds (default 420).")
    parser.add_argument("--force", action="store_true",
                        help="Ignore cached verdicts and re-run every eval.")
    parser.add_argument("--no-cache", action="store_true",
                        help="Neither read nor write the verdict cache.")
    args = parser.parse_args()

    ids = args.ids if args.ids else known_ids
    unknown = [i for i in ids if i not in known_ids]
    if unknown:
        parser.error(
            f"unknown eval id(s): {' '.join(unknown)}; "
            f"evals.json defines {' '.join(known_ids)}"
        )
    cache = None if args.no_cache else eval_cache.EvalCache(THIS / ".eval_cache")
    resolved = vendor.resolve(args)
    model_label = resolved.worker_model or "<inherit>"

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{ts}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")
    print(
        f"Worker vendor: {resolved.vendor}; command: {resolved.config.label}; "
        f"model: {model_label}; evals: {ids}"
    )
    cache_mode = "off" if cache is None else ("force-refresh" if args.force else "on")
    print(f"Verdict cache: {cache_mode}\n")

    micro_deploy.preflight_auth(resolved.vendor, resolved.bin, resolved.worker_model)

    results = {i: run_one(i, run_dir, resolved, args.timeout, cache, args.force)
               for i in ids}

    ok = sum(1 for passed, _ in results.values() if passed)
    cached_n = sum(1 for _, was_cached in results.values() if was_cached)
    print("=" * 56)
    print(f"graded: {ok}/{len(results)} evals passed ({cached_n} from cache)")
    for i, (passed, was_cached) in results.items():
        print(f"  {i}: {'PASS' if passed else 'FAIL'}"
              f"{' (cached)' if was_cached else ''}")
    summary = {
        "run_dir": str(run_dir),
        "model": model_label,
        "passed": ok,
        "total": len(results),
        "results": {i: {"passed": p, "cached": c} for i, (p, c) in results.items()},
    }
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
