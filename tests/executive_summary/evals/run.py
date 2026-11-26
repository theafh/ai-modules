#!/usr/bin/env python3
"""Vendor-aware runner for the executive_summary behavioral evals.

Each eval is one job in the shared pool from `tests/lib/eval_runner.py`
(`--workers`, default `vendor.DEFAULT_PARALLEL_WORKERS`, each job with its own
TMPDIR). The default ids are every id in `evals.json`, in file order.

Per eval the job:

1. Stages a fresh sandbox via `stage.sh <id> <target>` and reads back
   `sandbox_proj`, `skill_path`, and `prompt`.
2. Micro-deploys `executive_summary` into a scratch home outside the sandbox
   project and runs a vendor-resolved print-mode worker with the sandbox as its
   working directory, telling it to load the deployed SKILL.md, follow it, and
   write the summary to `summary.md`.
3. Captures `response.txt` / `stderr.txt` / `timing.json` under
   `tests/executive_summary/workspace/run-<ts>/<id>/`.
4. Grades the sandbox deterministically with `grade.sh`, then runs the
   refute-biased `judge.py` for fidelity and ordering.

Exit code is 0 only when every eval's worker completed cleanly, its
deterministic grade passed, and the judge passed both assertions.

Usage:
    python3 tests/executive_summary/evals/run.py [eval_id ...]
      [--vendor claude|cursor] [--model ...] [--effort ...]
      [--worker-bin <bin>] [--workers 4] [--timeout 600]
      [--judge-timeout 300] [--skip-judge] [--force] [--no-cache]
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
JUDGE = THIS / "judge.py"
EVALS = THIS / "evals.json"

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import eval_cache  # noqa: E402
import eval_runner  # noqa: E402
import micro_deploy  # noqa: E402
import vendor  # noqa: E402
import worker_isolation  # noqa: E402

WORKSPACE = eval_runner.resolve_workspace(THIS)
ARTEFACTS = ["executive_summary"]
ISOLATION_PREFIX = "executive_summary_"
DEFAULT_IDS = eval_runner.load_eval_ids(EVALS)

WORKER_PROMPT = """\
You are running an automated skill regression eval. Do exactly this:

1. Read the skill definition file in full: {skill_path}
2. Follow that skill's instructions exactly as written.
3. Carry out the user request below, operating only inside the current
   working directory ({workdir}):

{prompt}

Write your final summary to summary.md in the current working directory.
"""


def source_roots_for():
    return micro_deploy.source_roots_for(ARTEFACTS)


def stage(eval_id: str, target: pathlib.Path, env: Mapping[str, str]) -> dict:
    emit = (
        f'out="$({shlex.quote(str(STAGE))} {shlex.quote(eval_id)} '
        f'{shlex.quote(str(target))})" || exit $?; eval "$out"; '
        'printf "%s\\0%s\\0%s\\0" "$sandbox_proj" "$skill_path" "$prompt"'
    )
    result = subprocess.run(
        ["bash", "-c", emit], capture_output=True, text=True, env=dict(env)
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"stage.sh failed for eval {eval_id} (rc={result.returncode}): "
            f"{result.stderr.strip()}"
        )
    sandbox_proj, skill_path, prompt, _ = result.stdout.split("\0")
    if not sandbox_proj or not pathlib.Path(sandbox_proj).is_dir():
        raise RuntimeError(f"stage.sh staged no sandbox project for eval {eval_id}: {sandbox_proj!r}")
    return {"sandbox_proj": sandbox_proj, "skill_path": skill_path, "prompt": prompt}


def worker_completed(rc: int, stdout: str) -> bool:
    return rc == 0 and bool(stdout.strip())


def _apply_job_temp(deploy_env: dict[str, str], job_env: Mapping[str, str]) -> None:
    for key in ("TMPDIR", "TEMP", "TMP"):
        value = job_env.get(key)
        if value:
            deploy_env[key] = value


def run_one(eval_id: str, run_dir: pathlib.Path, resolved: vendor.Resolved,
            args, cache, env: Mapping[str, str]) -> bool:
    eval_dir = run_dir / eval_id
    eval_dir.mkdir(parents=True, exist_ok=True)

    root = worker_isolation.create_sandbox_root(ISOLATION_PREFIX)
    try:
        staged = stage(eval_id, root, env)
        workdir = staged["sandbox_proj"]

        key = None
        if cache is not None:
            key = eval_cache.content_key(
                source_roots=source_roots_for(),
                harness_dir=THIS,
                model=resolved.worker_model,
                effort=resolved.worker_effort,
                eval_id=eval_id,
                prompt=staged["prompt"],
                dependencies=eval_cache.dependencies_for(EVALS, eval_id),
            )
        hit = eval_runner.cache_lookup(cache, eval_id, key, eval_dir, force=args.force)
        if hit is not None:
            print(f"  [eval-{eval_id}] CACHED {'PASS' if hit['passed'] else 'FAIL'}\n", flush=True)
            return bool(hit["passed"])

        print(f"  [eval-{eval_id}] running {resolved.config.label} ...", flush=True)
        started = time.time()
        with micro_deploy.micro_deploy(
            resolved.vendor, ARTEFACTS, pathlib.Path(workdir), preflight=False
        ) as md:
            _apply_job_temp(md.env, env)
            prompt = WORKER_PROMPT.format(
                skill_path=md.path_map["executive_summary"],
                workdir=workdir, prompt=staged["prompt"],
            )
            worker = micro_deploy.run_worker(
                vendor_name=resolved.vendor, bin_name=resolved.bin,
                model=resolved.worker_model, effort=resolved.worker_effort,
                prompt=prompt, deploy=md, timeout=args.timeout, cwd=workdir,
            )
            integrity, checkout_unread, harness_copy_unread = (
                micro_deploy.provenance_records(worker)
            )
        ended = time.time()
        rc = worker.returncode
        response = worker.stdout
        stderr = worker.stderr
        (eval_dir / "response.txt").write_text(response, encoding="utf-8")
        (eval_dir / "stderr.txt").write_text(stderr, encoding="utf-8")
        (eval_dir / "timing.json").write_text(json.dumps({
            "started_at": started, "ended_at": ended,
            "duration_s": ended - started, "worker_rc": rc,
            "model": resolved.worker_model, "effort": resolved.worker_effort,
            "artefacts_read_from_micro_deployment": integrity,
            "checkout_unread": checkout_unread,
            "harness_copy_unread": harness_copy_unread,
        }, indent=2) + "\n", encoding="utf-8")

        completed = worker_completed(rc, response)
        grading = subprocess.run(
            ["bash", str(GRADE), eval_id, workdir, str(eval_dir / "response.txt")],
            capture_output=True, text=True, env=dict(env),
        )
        (eval_dir / "grading.txt").write_text(grading.stdout + grading.stderr, encoding="utf-8")
        grade_ok = grading.returncode == 0

        judge_ok = bool(args.skip_judge)
        judge_ran = False
        if not args.skip_judge and completed and grade_ok:
            judge_ran = True
            summary = pathlib.Path(workdir) / "summary.md"
            verdict_path = eval_dir / "judge.json"
            judge = subprocess.run(
                [sys.executable, str(JUDGE), eval_id, str(pathlib.Path(workdir) / "source.md"),
                 str(summary), "--vendor", resolved.vendor,
                 "--judge-model", resolved.judge_model or "",
                 "--judge-effort", resolved.judge_effort or "",
                 "--timeout", str(args.judge_timeout), "--out", str(verdict_path)],
                capture_output=True, text=True, env=dict(env),
            )
            if judge.returncode != 0 or not verdict_path.is_file():
                judge_ok = False
                (eval_dir / "judge-stderr.txt").write_text(judge.stderr, encoding="utf-8")
            else:
                verdict = json.loads(verdict_path.read_text(encoding="utf-8"))
                judge_ok = verdict.get("fidelity") == "pass" and verdict.get("order") == "pass"

        read_ok = micro_deploy.read_checks_passed(
            integrity, checkout_unread, harness_copy_unread)
        passed = completed and grade_ok and judge_ok and read_ok
        verdict = {
            "eval_id": eval_id, "passed": passed, "worker_completed": completed,
            "artefacts_read_from_micro_deployment": integrity,
            "checkout_unread": checkout_unread,
            "harness_copy_unread": harness_copy_unread,
            "read_ok": read_ok,
            "grade_ok": grade_ok, "judge_ok": judge_ok, "judge_ran": judge_ran,
            "graded_at": datetime.datetime.now().isoformat(timespec="seconds"),
            "model": resolved.worker_model, "effort": resolved.worker_effort,
        }
        (eval_dir / "verdict.json").write_text(json.dumps(verdict, indent=2) + "\n", encoding="utf-8")
        if cache is not None and key is not None:
            eval_runner.cache_record(
                cache, eval_id, key,
                passed=passed,
                model=resolved.worker_model or "",
                effort=resolved.worker_effort or "",
                duration_s=ended - started,
                worker_rc=rc,
                grading_output=grading.stdout + grading.stderr,
                response_excerpt=response[:eval_cache.RESPONSE_EXCERPT_CHARS],
            )
        print(f"  [eval-{eval_id}] {'PASS' if passed else 'FAIL'}\n", flush=True)
        return passed
    finally:
        import shutil
        shutil.rmtree(root, ignore_errors=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*", default=None)
    vendor.add_vendor_arguments(ap, with_judge=True)
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--judge-timeout", type=int, default=300)
    ap.add_argument("--skip-judge", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--no-cache", action="store_true")
    eval_runner.add_workers_argument(ap)
    args = ap.parse_args()
    resolved = vendor.resolve(args, with_judge=True)
    ids = args.ids or DEFAULT_IDS
    cache = None if args.no_cache else eval_cache.EvalCache(THIS / ".eval_cache")

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{ts}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")
    print(f"Vendor: {resolved.vendor}; ids: {ids}\n")

    def job_for(eval_id: str):
        return lambda env: run_one(eval_id, run_dir, resolved, args, cache, env)

    def on_error(index: int, exc: Exception) -> bool:
        print(f"  [eval-{ids[index]}] ERROR, harness fault: {exc!r}\n", flush=True)
        return False

    results = eval_runner.run_jobs(
        [job_for(i) for i in ids], workers=args.workers, on_error=on_error,
    )
    passed = sum(1 for r in results if r)
    print(f"{passed}/{len(ids)} evals passed")
    return 0 if passed == len(ids) else 1


if __name__ == "__main__":
    sys.exit(main())
