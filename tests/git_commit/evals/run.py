#!/usr/bin/env python3
"""Vendor-aware worker runner for the git_commit behavioral evals.

Phase 2 (the skill actually running) used to be operator-driven in the
host session, i.e. on whatever model the session inherited. This runner
instead spawns one vendor-resolved print-mode worker per eval. By default
that means the Cursor worker (`agent -p`, model `auto`); `--vendor claude`
(model `sonnet`) runs where Claude is needed or asked for, and
`--model ''` inherits the vendor CLI default. The meta level on top — the deterministic `grade.sh`,
and any prose-verdict confirmation the operator does by reading
`response.txt` — stays model-free.

Each eval is one job in the shared pool from `tests/lib/eval_runner.py`
(`--workers`, default `vendor.DEFAULT_PARALLEL_WORKERS`, each job with its own
TMPDIR). The default ids are every id in `evals.json`, in file order. Per eval
the job:

1. Stages a fresh sandbox via `stage.sh <id> <target>` and reads back
   `sandbox_repo`, `skill_path`, `prompt`.
2. Micro-deploys the skill through the deploy script into a scratch home
   outside the sandbox repo and copies the edits of a fixture's own skill
   copy (evals 5 to 7) onto that deployed skill. It then points the worker's
   TMPDIR, TEMP, and TMP at the job's own directory and runs a
   vendor-resolved print-mode worker with the sandbox repo as the working
   directory and a prompt that tells the worker to load the deployed SKILL.md
   and apply it.
3. Captures `response.txt` / `stderr.txt` / `timing.json` (with
   `started_at`, `ended_at`, the `fixture_overlay` file list, and the
   `artefacts_read_from_micro_deployment` integrity record) under
   `tests/git_commit/workspace/run-<ts>/<id>/`.
4. Grades the post-run sandbox with `grade.sh <id> <sandbox_repo>` under the
   same job environment, so its straggler scan reads the job's TMPDIR.

Exit code is 0 only when every eval's worker completed cleanly (CLI rc 0
with a real response) AND its deterministic grade passed. A timed-out or
crashed worker fails the eval regardless of grade.sh, which would
otherwise pass on the partially-correct sandbox state an aborted run left.
The prose-verdict expectations in evals.json remain operator-confirmed
from the captured `response.txt`.

Usage:
    python3 tests/git_commit/evals/run.py [eval_id ...]   # default: every id
      [--vendor claude|cursor] [--model sonnet|auto|''] [--worker-bin <bin>]
      [--workers 4] [--timeout 300] [--force] [--no-cache]
"""

from __future__ import annotations

import argparse
import datetime
import pathlib
import shlex
import subprocess
import sys
import time
from collections.abc import Mapping

THIS = pathlib.Path(__file__).resolve().parent
STAGE = THIS / "stage.sh"
GRADE = THIS / "grade.sh"
EVALS = THIS / "evals.json"

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import eval_cache  # noqa: E402  (shared local test helper; tests/ is gitignored)
import eval_runner  # noqa: E402  (shared Pattern A job pool)
import micro_deploy  # noqa: E402  (shared micro-deployment helper)
import vendor  # noqa: E402  (shared vendor helper; tests/ is gitignored)
import worker_isolation  # noqa: E402  (shared sandbox-root helper)

# The sole run root: tests/git_commit/workspace, beside evals/.
WORKSPACE = eval_runner.resolve_workspace(THIS)

ARTEFACTS = ["git_commit"]

ISOLATION_PREFIX = "git_commit_"


def source_roots_for():
    """git_commit is self-contained: the SKILL.md the worker loads, its
    scripts/, and references/ all live in the one skill dir, so that dir is the
    whole artifact-under-test for the cache key."""
    return micro_deploy.source_roots_for(ARTEFACTS)


DEFAULT_IDS = eval_runner.load_eval_ids(EVALS)

WORKER_PROMPT = """\
You are running an automated skill regression eval. Do exactly this:

1. Read the skill definition file in full: {skill_path}
2. Follow that skill's instructions exactly as written. Resolve any
   bundled scripts it references relative to that SKILL.md's directory.
3. Carry out the user request below, operating only inside the current
   working directory ({workdir}):

{prompt}
"""


def stage(eval_id: str, target: pathlib.Path, env: Mapping[str, str]) -> dict:
    """Run stage.sh and read back the staged values. stage.sh prints
    printf-%q-quoted `name=value` lines meant to be `eval`'d in bash, so
    we let bash eval them and re-emit the raw values NUL-separated. The
    script captures stage.sh's output before evaluating it and exits with
    stage.sh's status when it fails, so a failed stage raises here. An empty
    or missing sandbox_repo raises too, because pathlib.Path("") is the
    current directory and the worker would otherwise start in the checkout."""
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
    """Whether a worker run is trustworthy for grading. The CLI must have
    exited 0 and produced a final response. A non-zero rc (timeout → -1,
    crash, API error) or an empty response means the skill did not finish,
    so grade.sh's checks on the resulting sandbox reflect only partial state
    and must not count as a pass."""
    return rc == 0 and bool(stdout.strip())


def _apply_job_temp(deploy_env: dict[str, str], job_env: Mapping[str, str]) -> None:
    """Point the worker at this job's TMPDIR, TEMP, and TMP."""

    for key in ("TMPDIR", "TEMP", "TMP"):
        value = job_env.get(key)
        if value:
            deploy_env[key] = value


def run_one(eval_id: str, run_dir: pathlib.Path, resolved: vendor.Resolved,
            timeout: int, cache, force: bool, env: Mapping[str, str]):
    """Run one eval inside the caller's job. Returns (passed, was_cached)."""
    eval_dir = run_dir / eval_id
    eval_dir.mkdir(parents=True, exist_ok=True)

    root = worker_isolation.create_sandbox_root(ISOLATION_PREFIX)
    try:
        staged = stage(eval_id, root, env)
        workdir = staged["sandbox_repo"]
        model_label = resolved.worker_model or "<inherit>"

        key = None
        if cache is not None:
            key = eval_cache.content_key(
                source_roots=source_roots_for(),
                harness_dir=THIS,
                model=resolved.worker_model,
                eval_id=eval_id,
                prompt=staged["prompt"],
                dependencies=eval_cache.dependencies_for(EVALS, eval_id),
            )
        hit = eval_runner.cache_lookup(cache, eval_id, key, eval_dir, force=force)
        if hit is not None:
            verdict = "PASS" if hit["passed"] else "FAIL"
            print(f"  [eval-{eval_id}] CACHED {verdict} "
                  f"(graded {hit.get('graded_at', '?')}, "
                  f"model={hit.get('model', '?')}) — skipped {resolved.config.label}; "
                  "--force to re-run\n", flush=True)
            return bool(hit["passed"]), True

        print(f"  [eval-{eval_id}] running {resolved.config.label} (model={model_label}) ...",
              flush=True)
        started_at = time.time()
        # The skill deploys into a scratch home beside, never inside, the repo
        # under test: git_commit would otherwise pick up a copied skill tree.
        with micro_deploy.micro_deploy(
            resolved.vendor, ARTEFACTS, pathlib.Path(workdir), preflight=False
        ) as md:
            # The worker writes its git_commit_context.* file into the job's
            # own TMPDIR, the directory grade.sh's straggler scan reads below.
            _apply_job_temp(md.env, env)
            # Evals 5, 6, and 7 stage an edited copy of the skill as skill_path: a
            # prepare script stubbed to fail, or one wrapped to touch the drift
            # writer's marker. The worker loads the deployed copy, so those edits
            # go onto it. Every other eval names the checkout source, which
            # overlays nothing.
            fixture_overlay = micro_deploy.overlay_fixture_edits(
                md, "git_commit", pathlib.Path(staged["skill_path"]).parent
            )
            prompt = WORKER_PROMPT.format(
                skill_path=md.path_map["git_commit"], workdir=workdir,
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
            started_at=started_at,
            ended_at=ended_at,
            fixture_overlay=fixture_overlay,
            artefacts_read_from_micro_deployment=integrity,
            checkout_unread=checkout_unread,
        )

        # The grader runs under the job's environment, so its straggler scan
        # reads the TMPDIR this eval's worker wrote into.
        grade_env = dict(env)
        grade = subprocess.run(
            ["bash", str(GRADE), eval_id, workdir],
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
            print(f"  [eval-{eval_id}] FAIL — worker did not complete ({why}); "
                  f"grade.sh ran on partial sandbox state and cannot be trusted "
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
        # crash is transient/environmental, not a property of the inputs, so
        # caching it would replay a spurious verdict on a later clean run.
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


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run the git_commit behavioral evals on a vendor worker."
    )
    parser.add_argument("ids", nargs="*", default=None,
                        help=f"Eval ids to run (default: {' '.join(DEFAULT_IDS)}).")
    vendor.add_vendor_arguments(parser)
    eval_runner.add_workers_argument(parser)
    parser.add_argument("--timeout", type=int, default=300,
                        help="Per-eval worker timeout in seconds (default 300).")
    parser.add_argument("--force", action="store_true",
                        help="Ignore cached verdicts and re-run every eval, "
                             "refreshing the cache with the new result.")
    parser.add_argument("--no-cache", action="store_true",
                        help="Neither read nor write the verdict cache.")
    args = parser.parse_args()

    ids = list(args.ids) if args.ids else list(DEFAULT_IDS)
    unknown = [eval_id for eval_id in ids if eval_id not in DEFAULT_IDS]
    if unknown:
        parser.error(
            f"unknown eval id(s) {', '.join(unknown)}; "
            f"valid: {' '.join(DEFAULT_IDS)}"
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
        f"model: {model_label}; workers: {args.workers}; evals: {ids}"
    )
    cache_mode = "off" if cache is None else ("force-refresh" if args.force else "on")
    print(f"Verdict cache: {cache_mode}\n")

    micro_deploy.preflight_auth(resolved.vendor, resolved.bin, resolved.worker_model)

    def make_job(eval_id: str) -> eval_runner.JobFn:
        def job(env: Mapping[str, str]) -> tuple[bool, bool]:
            return run_one(eval_id, run_dir, resolved, args.timeout, cache,
                           args.force, env)

        return job

    def on_error(index: int, exc: Exception) -> tuple[bool, bool]:
        print(f"  [eval-{ids[index]}] FAIL — harness fault: {exc}\n", flush=True)
        return False, False

    # Parallel by default: eval_runner gives every job its own TMPDIR, the
    # worker writes its git_commit_context.* file there, and grade.sh's
    # straggler scan reads only that directory, so a concurrent eval's context
    # file never reaches another eval's scan. Every eval also stages its own
    # sandbox root. Pass --workers 1 to serialize.
    results = eval_runner.run_jobs(
        [make_job(eval_id) for eval_id in ids],
        workers=args.workers,
        on_error=on_error,
    )
    rows = [
        (f"eval-{eval_id}", passed, was_cached)
        for eval_id, (passed, was_cached) in zip(ids, results)
    ]
    eval_runner.print_summary(rows)
    return 0 if all(passed for _eval_id, passed, _cached in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
