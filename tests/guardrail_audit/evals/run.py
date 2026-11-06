#!/usr/bin/env python3
"""Vendor-aware worker runner for guardrail_audit behavioral evals.

Stages a sandbox, micro-deploys guardrail_audit and the guardrail hub
through the deploy script into a scratch home, runs one vendor-resolved
print-mode worker that loads guardrail_audit (which reads the guardrail
hub via <authority>), records `artefacts_read_from_micro_deployment`, then
grades byte-identity and response markers with grade.sh. The worker runs
on Cursor by default (`agent -p`, model `auto`); `--vendor claude` (model
`sonnet`) runs where Claude is needed or asked for, and `--model ''`
inherits the vendor CLI default.

Isolated evals run through `tests/lib/eval_runner.py` at `--workers`
(default 4), each with its own `TMPDIR`. Every eval stages its own sandbox
root, and `grade.sh` compares only that sandbox's staged tree, so an
overlapping job's work stays outside another eval's comparison.

Usage:
    python3 tests/guardrail_audit/evals/run.py [eval_id ...]
      # default: every `id` in evals.json, derived at startup
      [--vendor claude|cursor] [--model sonnet|auto|'']
      [--workers 4] [--timeout 300] [--worker-bin <bin>]
      [--force] [--no-cache]
"""

from __future__ import annotations

import argparse
import datetime
import os
import pathlib
import shlex
import subprocess
import sys
import time
from collections.abc import Mapping

THIS = pathlib.Path(__file__).resolve().parent
STAGE = THIS / "stage.sh"
GRADE = THIS / "grade.sh"

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import eval_cache  # noqa: E402
import eval_runner  # noqa: E402  (shared Pattern A runner)
import micro_deploy  # noqa: E402
import vendor  # noqa: E402
import worker_isolation  # noqa: E402  (shared sandbox-root helper)

WORKSPACE = eval_runner.resolve_workspace(THIS)

ARTEFACTS = ["guardrail_audit", "guardrail"]

DEFAULT_IDS = eval_runner.load_eval_ids(THIS / "evals.json")

ISOLATION_PREFIX = "guardrail_audit_"

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


def source_roots_for():
    return micro_deploy.source_roots_for(ARTEFACTS)


def stage(
    eval_id: str, target: pathlib.Path, env: Mapping[str, str]
) -> dict:
    """Run stage.sh and read back the staged values.

    stage.sh prints printf-%q-quoted `name=value` lines meant to be `eval`'d in
    bash, so bash evaluates them and re-emits the raw values NUL-separated. The
    script captures stage.sh's output before evaluating it and exits with
    stage.sh's status when it fails, so a failed stage raises here. An empty or
    missing sandbox_proj raises too, because pathlib.Path("") is the current
    directory and the worker would otherwise start in the checkout.
    """
    emit = (
        f'out="$(bash {shlex.quote(str(STAGE))} {shlex.quote(eval_id)} '
        f'{shlex.quote(str(target))})" || exit $?; eval "$out"; '
        'printf "%s\\0%s\\0%s\\0%s\\0" '
        '"$sandbox_proj" "$skill_path" "$hub_path" "$prompt"'
    )
    result = subprocess.run(
        ["bash", "-c", emit], capture_output=True, text=True, env=dict(env)
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"stage.sh failed for eval {eval_id} (rc={result.returncode}): "
            f"{result.stderr.strip()}"
        )
    sandbox_proj, skill_path, hub_path, prompt, _rest = (
        result.stdout.split("\0")
    )
    if not sandbox_proj or not pathlib.Path(sandbox_proj).is_dir():
        raise RuntimeError(
            f"stage.sh staged no sandbox project for eval {eval_id}: "
            f"{sandbox_proj!r}"
        )
    return {
        "sandbox_proj": sandbox_proj,
        "skill_path": skill_path,
        "hub_path": hub_path,
        "prompt": prompt,
    }


def worker_completed(rc: int, stdout: str) -> bool:
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
    eval_dir = run_dir / eval_id
    eval_dir.mkdir(parents=True, exist_ok=True)

    root = worker_isolation.create_sandbox_root(ISOLATION_PREFIX)
    try:
        staged = stage(eval_id, root, env)
        workdir = staged["sandbox_proj"]
        model_label = resolved.worker_model or "<inherit>"

        key = None
        if cache is not None:
            key = eval_cache.content_key(
                source_roots=source_roots_for(),
                harness_dir=THIS,
                model=resolved.worker_model,
                eval_id=eval_id,
                prompt=staged["prompt"],
                dependencies=eval_cache.dependencies_for(THIS / "evals.json", eval_id),
            )
        hit = eval_runner.cache_lookup(cache, eval_id, key, eval_dir, force=force)
        if hit is not None:
            verdict = "PASS" if hit["passed"] else "FAIL"
            print(f"  [{eval_id}] CACHED {verdict} "
                  f"(graded {hit.get('graded_at', '?')}, "
                  f"model={hit.get('model', '?')}) — skipped "
                  f"{resolved.config.label}; --force to re-run\n", flush=True)
            return bool(hit["passed"]), True

        print(f"  [{eval_id}] running {resolved.config.label} "
              f"(model={model_label}) ...", flush=True)
        started_at = time.time()
        with micro_deploy.micro_deploy(
            resolved.vendor, ARTEFACTS, pathlib.Path(workdir), preflight=False
        ) as md:
            _apply_job_temp(md.env, env)
            prompt = WORKER_PROMPT.format(
                skill_path=md.path_map["guardrail_audit"],
                hub_path=md.path_map["guardrail"],
                workdir=workdir,
                prompt=staged["prompt"],
            )
            worker = micro_deploy.run_worker(
                vendor_name=resolved.vendor, bin_name=resolved.bin,
                model=resolved.worker_model, prompt=prompt, deploy=md,
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
            artefacts_read_from_micro_deployment=integrity,
            checkout_unread=checkout_unread,
            started_at=started_at,
            ended_at=ended_at,
        )

        grade_env = dict(env)
        grade_env["RESPONSE_FILE"] = str(eval_dir / "response.txt")
        grade = subprocess.run(
            ["bash", str(GRADE), eval_id, workdir,
             str(eval_dir / "response.txt")],
            capture_output=True, text=True, env=grade_env,
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
            print(f"  [{eval_id}] FAIL — worker did not complete ({why})\n",
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

        if completed:
            eval_runner.cache_record(
                cache,
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
    parser.add_argument("--timeout", type=int, default=300,
                        help="Per-eval worker timeout in seconds.")
    parser.add_argument("--force", action="store_true",
                        help="Ignore cached verdicts and re-run every eval, "
                             "refreshing the cache with the new result.")
    parser.add_argument("--no-cache", action="store_true",
                        help="Neither read nor write the verdict cache.")
    args = parser.parse_args()

    ids = list(args.ids) if args.ids else list(DEFAULT_IDS)
    cache = None if args.no_cache else eval_cache.EvalCache(THIS / ".eval_cache")
    resolved = vendor.resolve(args)
    model_label = resolved.worker_model or "<inherit>"

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{ts}-{os.getpid()}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")
    print(
        f"Worker vendor: {resolved.vendor}; command: {resolved.config.label}; "
        f"model: {model_label}; workers: {args.workers}; evals: {ids}"
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
    return 0 if ok == len(rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
