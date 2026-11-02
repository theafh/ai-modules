#!/usr/bin/env python3
"""Vendor-aware worker runner for the task-family behavioral evals.

Phase 2 (the skill actually running) used to be operator-driven in the
host session, i.e. on whatever model the session inherited. This runner
instead spawns one vendor-resolved print-mode worker per eval. By default
that means the Cursor worker (`agent -p`, model `auto`); `--vendor claude`
(model `sonnet`) runs where Claude is needed or asked for, and
`--model ''` inherits the vendor CLI default. The meta level on top — the
deterministic `grade.sh`, which reads the captured response through
`RESPONSE_FILE`, and the operator's confirmation of the remaining
`agent-attest` judgements — stays model-free.

Isolated evals run through `tests/lib/eval_runner.py` at `--workers`
(default 4). The Approach serial nested-loop set
(`auto_check_boundary`, `fix_coherence_reconcile_escalated`,
`fix_coherence_reconcile_inline_staleness`) runs afterward at one worker,
so those jobs do not overlap one another or the isolated pool.

Per eval the runner:

1. Stages a fresh sandbox via `stage.sh <id> <target>` and reads back
   `sandbox_proj`, `skill_name`, `skill_path`, `prompt`.
2. Micro-deploys the loaded skill, the base `task` skill, and whatever
   further task-family skills and `auto_*_task` agents the sibling reaches
   (see `artefacts_for`) through the deploy script into a scratch home, then
   runs a vendor-resolved print-mode worker with the sandbox project as the
   working directory (so the skill's discover_tasks.sh resolves the
   sandbox, never the real repo) and a prompt that tells the worker to load
   the deployed SKILL.md.
3. Captures `response.txt` / `stderr.txt` / `timing.json` (with the
   `artefacts_read_from_micro_deployment` integrity record and wall-clock
   `started_at` / `ended_at`) under `tests/task/workspace/run-<ts>/<id>/`.
4. Grades the post-run sandbox with `grade.sh <id> <sandbox_proj>`, passing
   the captured response through `RESPONSE_FILE`.

Exit code is 0 only when every eval's worker completed cleanly (CLI rc 0
with a real response) AND its deterministic grade passed. A timed-out or
crashed worker fails the eval regardless of grade.sh: grade.sh then sees
only partial sandbox state (e.g. an early status stamp an aborted loop
left behind), which could otherwise masquerade as a clean pass.
The grader reads the captured response through `RESPONSE_FILE` for the
subject and verdict checks each eval carries, and those checks decide the
exit code. The remaining output-verdict expectations in evals.json (the
literal `# General assessment`, `No issues found.`, `Success: full task
compliance confirmed.`, and `audit complete — …` strings) are the
judgements no check can decide and stay operator-confirmed.

Usage:
    python3 tests/task/evals/run.py [eval_id ...]
      # default: every `id` in evals.json, derived at startup, so a newly
      #          authored eval joins the suite without editing this file
      [--vendor claude|cursor] [--model sonnet|auto|'']
      [--workers 4] [--timeout 600] [--worker-bin <bin>]
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

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import eval_cache  # noqa: E402  (shared local test helper; tests/ is gitignored)
import eval_runner  # noqa: E402  (shared Pattern A runner)
import micro_deploy  # noqa: E402  (shared micro-deployment helper)
import vendor  # noqa: E402  (shared vendor helper; tests/ is gitignored)
import worker_isolation  # noqa: E402  (shared sandbox-root helper)

WORKSPACE = eval_runner.resolve_workspace(THIS)

ISOLATION_PREFIX = "task_"

AUTO_AGENTS = [
    "auto_drift_task",
    "auto_dryrun_task",
    "auto_gate_task",
    "auto_reviewer_task",
    "auto_shaper_task",
    "auto_verifier_task",
]

# The siblings that spawn the auto_*_task agents: task_auto_check drives them,
# and task_fix escalates to auto_shaper_task.
AGENT_SPAWNING_SKILLS = {"task_auto_check", "task_fix"}

# The Approach serial nested-loop set. These jobs share the model in a way the
# pool cannot isolate, so they run one id at a time after the isolated pool.
SERIAL_NESTED_LOOP_IDS = (
    "auto_check_boundary",
    "fix_coherence_reconcile_escalated",
    "fix_coherence_reconcile_inline_staleness",
)

DEFAULT_IDS = eval_runner.load_eval_ids(THIS / "evals.json")


def artefacts_for(skill_name: str) -> list[str]:
    """Names micro-deployed for one eval, following what its sibling reaches.

    Every sibling reads the base `task` hub through its <authority> step. The
    two agent-spawning siblings also get the six auto_*_task agents and the
    `task_check` skill, which the auto_gate_task agent wraps, and task_fix gets
    `task_auto_check`, which its escalated auto_shaper_task may invoke. Every
    other sibling spawns no agent, so its evals declare none. That keeps their
    sandbox repository as staged: on Cursor the deploy script writes agents
    into the sandbox project's `.cursor/agents/`, and the read-only evals
    grade that repository's `git status` as unchanged."""
    names = [skill_name, "task"]
    if skill_name in AGENT_SPAWNING_SKILLS:
        names.append("task_check")
        if skill_name == "task_fix":
            names.append("task_auto_check")
        names.extend(AUTO_AGENTS)
    return list(dict.fromkeys(names))


def source_roots_for(skill_name: str):
    """A task-family eval loads one sibling skill, which reads the base `task`
    skill via its <authority> step and (for the agent-spawning siblings)
    spawns agents. Hash every artefact `artefacts_for` declares, so an edit to
    the base skill or a reached agent invalidates the cache too, not just an
    edit to the loaded sibling. Over-inclusion only forces an occasional extra
    run; it can never serve a stale pass."""
    return micro_deploy.source_roots_for(artefacts_for(skill_name))


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


def partition_ids(ids: list[str]) -> tuple[list[str], list[str]]:
    """Split ids into the isolated pool and the serial nested-loop set.

    Both lists keep evals.json file order. An id outside the serial set is
    isolated, including one the caller named on the command line.
    """
    serial_members = set(SERIAL_NESTED_LOOP_IDS)
    isolated = [eval_id for eval_id in ids if eval_id not in serial_members]
    serial = [eval_id for eval_id in ids if eval_id in serial_members]
    return isolated, serial


WORKER_PROMPT = """\
You are running an automated skill regression eval. Do exactly this:

1. Read the skill definition file in full: {skill_path}
2. Follow that skill's instructions exactly as written. Resolve any
   bundled scripts it references relative to that SKILL.md's directory.
3. Carry out the user request below, operating only inside the current
   working directory ({workdir}) and its tasks/ tree:

{prompt}
"""


def stage(
    eval_id: str, target: pathlib.Path, env: Mapping[str, str]
) -> dict[str, str]:
    """Run stage.sh and read back the staged values. stage.sh prints
    printf-%q-quoted `name=value` lines meant to be `eval`'d in bash, so
    we let bash eval them and re-emit the raw values NUL-separated. The
    script captures stage.sh's output before evaluating it and exits with
    stage.sh's status when it fails, so a failed stage raises here. An empty
    or missing sandbox_proj raises too, because pathlib.Path("") is the
    current directory and the worker would otherwise start in the checkout."""
    emit = (
        f'out="$(bash {shlex.quote(str(STAGE))} {shlex.quote(eval_id)} '
        f'{shlex.quote(str(target))})" || exit $?; eval "$out"; '
        'printf "%s\\0%s\\0%s\\0%s\\0" '
        '"$sandbox_proj" "$skill_name" "$skill_path" "$prompt"'
    )
    result = subprocess.run(
        ["bash", "-c", emit], capture_output=True, text=True, env=dict(env)
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"stage.sh failed for eval {eval_id} (rc={result.returncode}): "
            f"{result.stderr.strip()}"
        )
    sandbox_proj, skill_name, skill_path, prompt, _rest = (
        result.stdout.split("\0")
    )
    if not sandbox_proj or not pathlib.Path(sandbox_proj).is_dir():
        raise RuntimeError(
            f"stage.sh staged no sandbox project for eval {eval_id}: "
            f"{sandbox_proj!r}"
        )
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


def _apply_job_temp(deploy_env: dict[str, str], job_env: Mapping[str, str]) -> None:
    """Point the worker at this job's TMPDIR, TEMP, and TMP."""
    for key in ("TMPDIR", "TEMP", "TMP"):
        value = job_env.get(key)
        if value:
            deploy_env[key] = value


def run_one(eval_id: str, run_dir: pathlib.Path, resolved: vendor.Resolved,
            timeout: int, cache, force: bool,
            env: Mapping[str, str]) -> tuple[bool, bool]:
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
                source_roots=source_roots_for(staged["skill_name"]),
                harness_dir=THIS,
                model=resolved.worker_model,
                eval_id=eval_id,
                prompt=staged["prompt"],
                dependencies=eval_cache.dependencies_for(THIS / "evals.json", eval_id),
            )
        hit = eval_runner.cache_lookup(
            cache, eval_id, key, eval_dir, force=force
        )
        if hit is not None:
            verdict = "PASS" if hit["passed"] else "FAIL"
            print(f"  [{eval_id}] CACHED {verdict} "
                  f"(skill={staged['skill_name']}, "
                  f"graded {hit.get('graded_at', '?')}, "
                  f"model={hit.get('model', '?')}) — skipped {resolved.config.label}; "
                  "--force to re-run\n", flush=True)
            return bool(hit["passed"]), True

        print(f"  [{eval_id}] running {resolved.config.label} "
              f"(skill={staged['skill_name']}, model={model_label}) ...", flush=True)
        started_at = time.time()
        with micro_deploy.micro_deploy(
            resolved.vendor, artefacts_for(staged["skill_name"]),
            pathlib.Path(workdir), preflight=False,
        ) as md:
            _apply_job_temp(md.env, env)
            prompt = WORKER_PROMPT.format(
                skill_path=md.path_map[staged["skill_name"]], workdir=workdir,
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
        passed = (
            grade_passed and completed
            and micro_deploy.read_checks_passed(integrity, checkout_unread)
        )

        if not completed:
            why = ("timeout" if "[TIMEOUT" in stderr
                   else "empty response" if not stdout.strip()
                   else f"worker rc={rc}")
            print(f"  [{eval_id}] FAIL — worker did not complete ({why}); "
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
    parser.add_argument("ids", nargs="*", default=None,
                        help="Eval ids to run (default: every id in DEFAULT_IDS)")
    vendor.add_vendor_arguments(parser)
    eval_runner.add_workers_argument(parser)
    parser.add_argument("--timeout", type=int, default=1800,
                        help="Default per-eval worker timeout in seconds. "
                             "evals/README.md documents the fix_coherence "
                             "reconcile evals as wanting 1800s, so the "
                             "default performs the documented run rather "
                             "than needing the flag. An eval carrying its "
                             "own \"timeout\" in evals.json overrides this.")
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
    isolated, serial = partition_ids(ids)

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{stamp}"
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

    # Isolated evals run through the shared pool at --workers (default 4);
    # the Approach serial nested-loop set runs afterward at one worker, so
    # those jobs do not overlap one another or the isolated pool.
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
