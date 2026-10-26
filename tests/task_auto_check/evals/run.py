#!/usr/bin/env python3
"""Vendor-aware worker runner for task_auto_check behavioral evals.

A pass requires both a clean worker completion (CLI rc 0 with a real
response) and a passing grade.sh. A timed-out or crashed worker fails the
eval regardless of grade.sh, which would otherwise pass on the partial
sandbox state an aborted loop left behind. These evals run the slow
nested-agent loop and are the most timeout-prone in the repo, so the gate
matters most here.

Isolated evals run through tests/lib/eval_runner.py at --workers
(default 4). The serial nested-loop set runs afterward at one worker, so
those jobs do not overlap one another or the isolated pool. Each fresh
pass micro-deploys inside its own job.

The worker policy comes from `tests/lib/vendor.py`: the worker runs on
Cursor by default (model `auto`), `--vendor claude` (model `sonnet`) runs
where Claude is needed or asked for, and `--model ''` inherits the
vendor CLI default. The harness micro-deploys the skill, the base `task`
and `task_check` skills, and the six `auto_*_task` agents through the
deploy script so named-agent runs stay hermetic, and records
`artefacts_read_from_micro_deployment` in each `timing.json`.
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
from collections.abc import Mapping

THIS = pathlib.Path(__file__).resolve().parent
STAGE = THIS / "stage.sh"
GRADE = THIS / "grade.sh"
WORKSPACE = THIS.parent / "workspace"

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import eval_cache  # noqa: E402  (shared local test helper)
import eval_runner  # noqa: E402  (shared Pattern A runner)
import micro_deploy  # noqa: E402  (shared micro-deployment helper)
import vendor  # noqa: E402  (shared vendor helper)
import worker_isolation  # noqa: E402  (shared sandbox-root helper)

ARTEFACTS = [
    "task_auto_check",
    "task",
    "task_check",
    "auto_drift_task",
    "auto_dryrun_task",
    "auto_gate_task",
    "auto_reviewer_task",
    "auto_shaper_task",
    "auto_verifier_task",
]

ISOLATION_PREFIX = "task_auto_check_"

# Repair-class six plus the timeout-table full-repair peers, ending with the
# dry-run gap serial. File order matches evals.json. These jobs share the
# model in a way the pool cannot isolate, so they run one at a time after
# the isolated pool finishes.
SERIAL_NESTED_LOOP_IDS = (
    "repair_to_ready",
    "relay_by_path",
    "stray_hunk_reverted",
    "guard_rebaseline_after_gate",
    "interaction_scan_surfaces",
    "immediate_ready_citations_overturn",
    "regroup_via_reviewer",
    "regroup_immediate_ready",
    "regroup_same_paragraph_ready",
    "committed_rule_deletion_routed",
    "last_call_ready_refuted",
    "regate_isolated",
    "dryrun_gap_confirmed",
)

DEFAULT_IDS = eval_runner.load_eval_ids(THIS / "evals.json")

WORKER_PROMPT = """\
You are running an automated skill regression eval. Do exactly this:

1. Read the skill definition file in full: {skill_path}
2. Follow that skill's instructions exactly as written. Resolve any
   bundled scripts or helper agents it references relative to that
   SKILL.md directory when the harness exposes only file paths.
3. Carry out the user request below, operating only inside the current
   working directory ({workdir}) and its tasks/ tree:

{prompt}
"""


def source_roots_for() -> list[pathlib.Path]:
    """Hash the skill, the base task skill, task_check, and the agents.

    task_auto_check reads the base `task` skill via <authority>, wraps
    `task_check` through the gate agent, and spawns the auto_*_task helper
    agents. An edit to any of them invalidates the cache. Over-inclusion
    only forces an occasional extra run; it can never serve a stale pass.
    """

    return micro_deploy.source_roots_for(ARTEFACTS)


def eval_timeout(eval_id: str, default: int) -> int:
    """Per-eval worker timeout from evals.json, else the CLI default."""

    with (THIS / "evals.json").open(encoding="utf-8") as handle:
        for entry in json.load(handle)["evals"]:
            if entry["id"] == eval_id:
                return int(entry.get("timeout", default))
    return default


def partition_ids(ids: list[str]) -> tuple[list[str], list[str]]:
    """Split ids into the isolated pool and the serial nested-loop set.

    Both lists keep evals.json file order. An id outside the serial set
    is isolated, including one the caller named on the command line.
    """

    serial_members = set(SERIAL_NESTED_LOOP_IDS)
    isolated = [eval_id for eval_id in ids if eval_id not in serial_members]
    serial = [eval_id for eval_id in ids if eval_id in serial_members]
    return isolated, serial


def stage(
    eval_id: str, target: pathlib.Path, env: Mapping[str, str]
) -> dict[str, str]:
    """Stage one eval and return sandbox_proj, skill_name, skill_path, prompt.

    The script captures stage.sh's output before evaluating it and exits with
    stage.sh's status when it fails, so a failed stage raises here. An empty
    or missing sandbox_proj raises too, because pathlib.Path("") is the
    current directory and the worker would otherwise start in the checkout.
    """

    emit = (
        f'out="$(bash {shlex.quote(str(STAGE))} {shlex.quote(eval_id)} '
        f'{shlex.quote(str(target))})" || exit $?; eval "$out"; '
        'printf "%s\\0%s\\0%s\\0%s\\0" '
        '"$sandbox_proj" "$skill_name" "$skill_path" "$prompt"'
    )
    result = subprocess.run(
        ["bash", "-c", emit],
        capture_output=True,
        text=True,
        env=dict(env),
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"stage.sh failed for eval {eval_id} (rc={result.returncode}): "
            f"{result.stderr.strip()}"
        )
    sandbox_proj, skill_name, skill_path, prompt, _rest = result.stdout.split("\0")
    if not sandbox_proj or not pathlib.Path(sandbox_proj).is_dir():
        raise RuntimeError(
            f"stage.sh staged no sandbox project for eval {eval_id}: "
            f"{sandbox_proj!r}"
        )
    return {
        "sandbox_proj": sandbox_proj,
        "skill_name": skill_name,
        "skill_path": skill_path,
        "prompt": prompt,
    }


def worker_completed(rc: int, stdout: str) -> bool:
    """Whether a worker run is trustworthy for grading.

    The CLI must have exited 0 and produced a final response. A non-zero
    rc (timeout is -1, crash, API error) or an empty response means the
    loop did not finish, so grade.sh's checks on the resulting sandbox
    reflect only partial state and must not count as a pass.
    """

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
    cache: eval_cache.EvalCache | None,
    force: bool,
    env: Mapping[str, str],
) -> tuple[bool, bool]:
    """Run one eval inside the caller's job. Returns (passed, was_cached)."""

    timeout = eval_timeout(eval_id, timeout)
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
                dependencies=eval_cache.dependencies_for(
                    THIS / "evals.json", eval_id
                ),
            )
        hit = eval_runner.cache_lookup(
            cache, eval_id, key, eval_dir, force=force
        )
        if hit is not None:
            verdict = "PASS" if hit["passed"] else "FAIL"
            print(
                f"  [{eval_id}] CACHED {verdict} "
                f"(skill={staged['skill_name']}, "
                f"graded {hit.get('graded_at', '?')}, "
                f"model={hit.get('model', '?')}) — skipped "
                f"{resolved.config.label}; --force to re-run\n",
                flush=True,
            )
            return bool(hit["passed"]), True

        print(
            f"  [{eval_id}] running {resolved.config.label} "
            f"(skill={staged['skill_name']}, model={model_label}) ...",
            flush=True,
        )
        started_at = time.time()
        with micro_deploy.micro_deploy(
            resolved.vendor,
            ARTEFACTS,
            pathlib.Path(workdir),
            preflight=False,
        ) as deploy:
            _apply_job_temp(deploy.env, env)
            prompt = WORKER_PROMPT.format(
                skill_path=deploy.path_map["task_auto_check"],
                workdir=workdir,
                prompt=staged["prompt"],
            )
            worker = micro_deploy.run_worker(
                vendor_name=resolved.vendor,
                bin_name=resolved.bin,
                model=resolved.worker_model,
                prompt=prompt,
                deploy=deploy,
                timeout=timeout,
                cwd=pathlib.Path(workdir),
            )
            rc = worker.returncode
            stdout = worker.stdout
            stderr = worker.stderr
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
            skill_name=staged["skill_name"],
            artefacts_read_from_micro_deployment=integrity,
            checkout_unread=checkout_unread,
            started_at=started_at,
            ended_at=ended_at,
        )

        grade_env = dict(env)
        grade_env["RESPONSE_FILE"] = str(eval_dir / "response.txt")
        grade = subprocess.run(
            ["bash", str(GRADE), eval_id, workdir],
            capture_output=True,
            text=True,
            env=grade_env,
        )
        (eval_dir / "grading.txt").write_text(grade.stdout + grade.stderr)
        print(grade.stdout, end="", flush=True)
        grade_passed = grade.returncode == 0
        completed = worker_completed(rc, stdout)
        passed = grade_passed and completed and micro_deploy.read_checks_passed(
            integrity, checkout_unread
        )

        if not completed:
            if "[TIMEOUT" in stderr:
                why = "timeout"
            elif not stdout.strip():
                why = "empty response"
            else:
                why = f"worker rc={rc}"
            grade_word = "PASS" if grade_passed else "FAIL"
            print(
                f"  [{eval_id}] FAIL — worker did not complete ({why}); "
                "grade.sh ran on partial sandbox state and cannot be trusted "
                f"(grade alone would have said {grade_word})\n",
                flush=True,
            )
        else:
            fail = micro_deploy.read_checks_fail_message(
                integrity, checkout_unread, vendor=resolved.vendor
            )
            if fail:
                print(f"  [{eval_id}] FAIL — {fail}", flush=True)
            else:
                word = "PASS" if passed else "FAIL"
                print(f"  [{eval_id}] {word} (worker rc={rc})", flush=True)

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
                response_excerpt=stdout[: eval_cache.RESPONSE_EXCERPT_CHARS],
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

    def on_error(_index: int, exc: Exception) -> tuple[bool, bool]:
        eval_id = eval_ids[_index]
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
    parser.add_argument("ids", nargs="*", default=None)
    vendor.add_vendor_arguments(parser)
    eval_runner.add_workers_argument(parser)
    parser.add_argument(
        "--timeout",
        type=int,
        default=2305,
        help=(
            "Default per-eval worker timeout in seconds. The repair "
            "loop runs ~576-2005s solo, so the default leaves headroom "
            "above that band rather than sitting on its floor. An eval "
            'carrying its own "timeout" in evals.json overrides this.'
        ),
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help=(
            "Ignore cached verdicts and re-run every eval, refreshing "
            "the cache with the new result."
        ),
    )
    parser.add_argument(
        "--no-cache",
        action="store_true",
        help="Neither read nor write the verdict cache.",
    )
    args = parser.parse_args()

    ids = list(args.ids) if args.ids else list(DEFAULT_IDS)
    cache = None if args.no_cache else eval_cache.EvalCache(THIS / ".eval_cache")
    resolved = vendor.resolve(args)
    model_label = resolved.worker_model or "<inherit>"
    isolated, serial = partition_ids(ids)

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{stamp}-{os.getpid()}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")
    print(
        f"Worker vendor: {resolved.vendor}; command: {resolved.config.label}; "
        f"model: {model_label}; workers: {args.workers}; evals: {ids}"
    )
    print(
        "Isolated pool: "
        f"{isolated or '(none)'}; serial nested-loop set at 1 worker after "
        f"that pool: {serial or '(none)'}"
    )
    if cache is None:
        cache_mode = "off"
    elif args.force:
        cache_mode = "force-refresh"
    else:
        cache_mode = "on"
    print(f"Verdict cache: {cache_mode}\n")

    micro_deploy.preflight_auth(resolved.vendor, resolved.bin, resolved.worker_model)

    by_id: dict[str, tuple[bool, bool]] = {}
    for eval_id, passed, was_cached in _execute(
        isolated,
        run_dir=run_dir,
        resolved=resolved,
        timeout=args.timeout,
        cache=cache,
        force=args.force,
        workers=args.workers,
    ):
        by_id[eval_id] = (passed, was_cached)
    for eval_id, passed, was_cached in _execute(
        serial,
        run_dir=run_dir,
        resolved=resolved,
        timeout=args.timeout,
        cache=cache,
        force=args.force,
        workers=1,
    ):
        by_id[eval_id] = (passed, was_cached)

    rows = [
        (eval_id, by_id[eval_id][0], by_id[eval_id][1]) for eval_id in ids
    ]
    eval_runner.print_summary(rows)
    ok = sum(1 for _eval_id, passed, _cached in rows if passed)
    return 0 if ok == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
