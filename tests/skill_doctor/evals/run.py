#!/usr/bin/env python3
"""Vendor-aware worker runner for the skill_doctor behavioral evals.

Modeled on tests/git_commit/evals/run.py: one vendor-resolved print-mode
worker runs per eval, so the skill under test uses one explicit worker policy
each run. By default that means the Cursor worker (`agent -p`, model
`auto`); `--vendor claude` (model `opus` at `high` effort) runs where Claude is needed or asked for, and `--model ''` inherits the vendor CLI default. The deterministic `grade.sh` on top uses
no model at all.

Each eval is one job in the shared pool from `tests/lib/eval_runner.py`
(`--workers`, default `vendor.DEFAULT_PARALLEL_WORKERS`, each job with its own
TMPDIR). The default ids are every id in `evals.json`, in file order. Per eval
the job:

1. Stages a fresh sandbox via `stage.sh <id> <target>` and reads back
   `sandbox_repo`, `skill_path`, `prompt`.
2. Micro-deploys the skill under test and its declared companion skills
   through the deploy script into a scratch home, points the worker's
   `TMPDIR`, `TEMP`, and `TMP` at the job's own directory, then runs a
   vendor-resolved print-mode worker with the sandbox repo as the working
   directory.
3. Captures `response.txt` / `stderr.txt` / `timing.json` (with `started_at`,
   `ended_at`, and the `artefacts_read_from_micro_deployment` integrity
   record) under `workspace/run-<ts>/<id>/`.
4. Grades with `grade.sh <id> <sandbox_repo> <response.txt>` under the same
   job environment — the sandbox checksum manifest proves the check-only
   contract, and the response text carries the resolved-target-set and
   ordering expectations.

Exit code is 0 only when every eval's worker completed cleanly (CLI rc 0 with
a real response) AND its deterministic grade passed.

Usage:
    python3 tests/skill_doctor/evals/run.py [eval_id ...]
      # default: every `id` in evals.json, derived at startup
      [--vendor claude|cursor] [--model opus|auto|''] [--effort high|<level>|'']
      [--workers 4] [--timeout 420] [--worker-bin <bin>]
      [--force] [--no-cache]
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
from collections.abc import Mapping

THIS = pathlib.Path(__file__).resolve().parent
STAGE = THIS / "stage.sh"
GRADE = THIS / "grade.sh"
EVALS_JSON = THIS / "evals.json"

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import eval_cache  # noqa: E402  (shared local test helper; tests/ is gitignored)
import eval_runner  # noqa: E402  (shared Pattern A job pool)
import micro_deploy  # noqa: E402  (shared micro-deployment helper)
import vendor  # noqa: E402  (shared vendor helper)
import worker_isolation  # noqa: E402  (shared sandbox-root helper)

# The sole run root: tests/skill_doctor/workspace, beside evals/.
WORKSPACE = eval_runner.resolve_workspace(THIS)

ARTEFACTS = ["skill_doctor", "ai_instruction_formatting", "ai_instruction_writing"]

# Every id in evals.json, in file order — the default run set. Derived rather
# than frozen: a hand-maintained subset here silently ran half the suite while
# still printing a clean `graded: N/N` line, so a newly added eval looked
# covered when nothing had run it.
DEFAULT_IDS = eval_runner.load_eval_ids(EVALS_JSON)

ISOLATION_PREFIX = "skill_doctor_"

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


def stage(
    eval_id: str, target: pathlib.Path, env: Mapping[str, str]
) -> dict:
    """Run stage.sh and read back the staged values. stage.sh prints
    printf-%q-quoted `name=value` lines meant to be `eval`'d in bash, so we
    let bash eval them and re-emit the raw values NUL-separated. The script
    captures stage.sh's output before evaluating it and exits with stage.sh's
    status when it fails, so a failed stage raises here. An empty or missing
    sandbox_repo raises too, because pathlib.Path("") is the current directory
    and the worker would otherwise start in the checkout."""
    emit = (
        f'out="$({shlex.quote(str(STAGE))} {shlex.quote(eval_id)} '
        f'{shlex.quote(str(target))})" || exit $?; eval "$out"; '
        'printf "%s\\0%s\\0%s\\0" "$sandbox_repo" "$skill_path" "$prompt"'
    )
    result = subprocess.run(
        ["bash", "-c", emit], capture_output=True, text=True, env=dict(env)
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"stage.sh failed for eval {eval_id} (rc={result.returncode}): "
            f"{result.stderr.strip()}"
        )
    sandbox_repo, skill_path, prompt, _ = result.stdout.split("\0")
    if not sandbox_repo or not pathlib.Path(sandbox_repo).is_dir():
        raise RuntimeError(
            f"stage.sh staged no sandbox repository for eval {eval_id}: "
            f"{sandbox_repo!r}"
        )
    return {"sandbox_repo": sandbox_repo, "skill_path": skill_path, "prompt": prompt}


def worker_completed(rc: int, stdout: str) -> bool:
    """Whether a worker run is trustworthy for grading. A non-zero rc
    (timeout, crash, API error) or an empty response means the skill did not
    finish, so the graded state reflects only partial work."""
    return rc == 0 and bool(stdout.strip())


def _apply_job_temp(deploy_env: dict[str, str], job_env: Mapping[str, str]) -> None:
    """Point the worker at this job's TMPDIR, TEMP, and TMP."""
    for key in ("TMPDIR", "TEMP", "TMP"):
        value = job_env.get(key)
        if value:
            deploy_env[key] = value


def run_one(
    eval_id: str,
    run_dir: pathlib.Path,
    resolved: vendor.Resolved,
    timeout: int,
    cache,
    force: bool,
    env: Mapping[str, str],
) -> tuple[bool, bool]:
    """Run one eval inside the caller's job. Returns (passed, was_cached)."""
    eval_dir = run_dir / eval_id
    eval_dir.mkdir(parents=True, exist_ok=True)

    root = worker_isolation.create_sandbox_root(ISOLATION_PREFIX)
    try:
        staged = stage(eval_id, root, env)
        workdir = staged["sandbox_repo"]
        model_label = resolved.worker_model or "<inherit>"
        worker_effort_label = resolved.worker_effort or "<inherit>"

        key = None
        if cache is not None:
            key = eval_cache.content_key(
                source_roots=source_roots_for(),
                harness_dir=THIS,
                model=resolved.worker_model,
                effort=resolved.worker_effort,
                eval_id=eval_id,
                prompt=staged["prompt"],
                dependencies=eval_cache.dependencies_for(EVALS_JSON, eval_id),
            )
        hit = eval_runner.cache_lookup(cache, eval_id, key, eval_dir, force=force)
        if hit is not None:
            verdict = "PASS" if hit["passed"] else "FAIL"
            print(f"  [{eval_id}] CACHED {verdict} "
                  f"(graded {hit.get('graded_at', '?')}, "
                  f"model={hit.get('model', '?')}, "
                  f"effort={hit.get('effort', '?')}) — skipped "
                  f"{resolved.config.label}; --force to re-run\n", flush=True)
            return bool(hit["passed"]), True

        print(f"  [{eval_id}] running {resolved.config.label} "
              f"(model={model_label}, effort={worker_effort_label}) ...", flush=True)
        started_at = time.time()
        with micro_deploy.micro_deploy(
            resolved.vendor, ARTEFACTS, pathlib.Path(workdir), preflight=False
        ) as md:
            _apply_job_temp(md.env, env)
            prompt = WORKER_PROMPT.format(
                skill_path=md.path_map["skill_doctor"], workdir=workdir,
                prompt=staged["prompt"],
            )
            worker = micro_deploy.run_worker(
                vendor_name=resolved.vendor, bin_name=resolved.bin,
                model=resolved.worker_model,
                effort=resolved.worker_effort,
                prompt=prompt, deploy=md,
                timeout=timeout, cwd=pathlib.Path(workdir),
            )
            rc, stdout, stderr = worker.returncode, worker.stdout, worker.stderr
            integrity, checkout_unread = micro_deploy.provenance_records(worker)
        ended_at = time.time()
        duration_s = ended_at - started_at

        eval_runner.write_run_artifacts(
            eval_dir,
            stdout=stdout,
            stderr=stderr,
            eval_id=eval_id,
            duration_s=duration_s,
            worker_rc=rc,
            model=model_label,
            effort=worker_effort_label,
            started_at=started_at,
            ended_at=ended_at,
            artefacts_read_from_micro_deployment=integrity,
            checkout_unread=checkout_unread,
        )

        grade = subprocess.run(
            ["bash", str(GRADE), eval_id, workdir,
             str(eval_dir / "response.txt")],
            capture_output=True, text=True, env=dict(env),
        )
        (eval_dir / "grading.txt").write_text(grade.stdout + grade.stderr)
        print(grade.stdout, end="", flush=True)
        grade_passed = grade.returncode == 0
        completed = worker_completed(rc, stdout)
        passed = (
            grade_passed and completed
            and micro_deploy.read_checks_passed(integrity, checkout_unread)
        )

        if not completed:
            why = ("timeout" if "[TIMEOUT" in stderr
                   else "empty response" if not stdout.strip()
                   else f"worker rc={rc}")
            print(f"  [{eval_id}] FAIL — worker did not complete ({why}); "
                  f"grade.sh ran on partial state and cannot be trusted "
                  f"(grade alone would have said {'PASS' if grade_passed else 'FAIL'})\n",
                  flush=True)
        else:
            fail = micro_deploy.read_checks_fail_message(
                integrity, checkout_unread, vendor=resolved.vendor
            )
            if fail:
                print(f"  [{eval_id}] FAIL — {fail}", flush=True)
            else:
                print(
                    f"  [{eval_id}] {'PASS' if passed else 'FAIL'} (worker rc={rc})",
                    flush=True,
                )

        # Cache only a conclusive verdict from a completed worker: a timeout or
        # crash is environmental, not a property of the inputs.
        if completed:
            eval_runner.cache_record(
                cache,
                eval_id,
                key,
                passed=passed,
                model=model_label,
                effort=worker_effort_label,
                duration_s=duration_s,
                worker_rc=rc,
                grading_output=grade.stdout + grade.stderr,
                response_excerpt=stdout[:eval_cache.RESPONSE_EXCERPT_CHARS],
            )
        return passed, False
    finally:
        worker_isolation.preserve_sandbox_copy(root, eval_dir / "sandbox")


def _execute(
    eval_ids: list[str],
    *,
    run_dir: pathlib.Path,
    resolved: vendor.Resolved,
    timeout: int,
    cache: eval_cache.EvalCache | None,
    force: bool,
    workers: int,
) -> list[tuple[str, bool, bool]]:
    """Run eval_ids through the shared pool. Results follow eval_ids."""

    if not eval_ids:
        return []

    def make_job(eval_id: str) -> eval_runner.JobFn:
        def job(env: Mapping[str, str]) -> tuple[bool, bool]:
            return run_one(
                eval_id, run_dir, resolved, timeout, cache, force, env
            )

        return job

    jobs = [make_job(eval_id) for eval_id in eval_ids]

    def on_error(index: int, exc: Exception) -> tuple[bool, bool]:
        eval_id = eval_ids[index]
        eval_dir = run_dir / eval_id
        eval_dir.mkdir(parents=True, exist_ok=True)
        (eval_dir / "stderr.txt").write_text(f"{exc}\n")
        print(f"  [{eval_id}] FAIL — {exc}\n", flush=True)
        return False, False

    raw = eval_runner.run_jobs(jobs, workers=workers, on_error=on_error)
    rows: list[tuple[str, bool, bool]] = []
    for index, eval_id in enumerate(eval_ids):
        passed, was_cached = raw[index]
        rows.append((eval_id, passed, was_cached))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ids", nargs="*", default=None,
                        help="Eval ids to run (default: every id in evals.json)")
    vendor.add_vendor_arguments(parser)
    eval_runner.add_workers_argument(parser)
    parser.add_argument("--timeout", type=int, default=420,
                        help="Per-eval worker timeout in seconds (default 420).")
    parser.add_argument("--force", action="store_true",
                        help="Ignore cached verdicts and re-run every eval.")
    parser.add_argument("--no-cache", action="store_true",
                        help="Neither read nor write the verdict cache.")
    args = parser.parse_args()

    ids = list(args.ids) if args.ids else list(DEFAULT_IDS)
    unknown = [i for i in ids if i not in DEFAULT_IDS]
    if unknown:
        parser.error(
            f"unknown eval id(s): {' '.join(unknown)}; "
            f"evals.json defines {' '.join(DEFAULT_IDS)}"
        )
    cache = None if args.no_cache else eval_cache.EvalCache(THIS / ".eval_cache")
    resolved = vendor.resolve(args)
    model_label = resolved.worker_model or "<inherit>"
    worker_effort_label = resolved.worker_effort or "<inherit>"

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{ts}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")
    print(
        f"Worker vendor: {resolved.vendor}; command: {resolved.config.label}; "
        f"model: {model_label}; "
        f"effort: {worker_effort_label}; workers: {args.workers}; evals: {ids}"
    )
    cache_mode = "off" if cache is None else ("force-refresh" if args.force else "on")
    print(f"Verdict cache: {cache_mode}\n")

    micro_deploy.preflight_auth(resolved.vendor, resolved.bin, resolved.worker_model)

    rows = _execute(
        ids,
        run_dir=run_dir,
        resolved=resolved,
        timeout=args.timeout,
        cache=cache,
        force=args.force,
        workers=args.workers,
    )
    eval_runner.print_summary(rows)
    ok = sum(1 for _eval_id, passed, _cached in rows if passed)

    # The helper prints the graded summary to stdout and writes no file, so
    # this runner keeps its own summary.json as the run's verdict of record.
    summary = {
        "run_dir": str(run_dir),
        "model": model_label,
        "effort": worker_effort_label,
        "passed": ok,
        "total": len(rows),
        "results": {
            eval_id: {"passed": passed, "cached": was_cached}
            for eval_id, passed, was_cached in rows
        },
    }
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    return 0 if ok == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
