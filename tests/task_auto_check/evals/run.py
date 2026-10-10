#!/usr/bin/env python3
"""Vendor-aware worker runner for task_auto_check behavioral evals.

A pass requires both a clean worker completion (CLI rc 0 with a real
response) and a passing grade.sh. A timed-out or crashed worker fails the
eval regardless of grade.sh, which would otherwise pass on the partial
sandbox state an aborted loop left behind. These evals run the slow
nested-agent loop and are the most timeout-prone in the repo, so the gate
matters most here.

The worker policy comes from `tests/lib/vendor.py`: the worker runs on
Cursor by default (model `auto`), `--vendor claude` (model `sonnet`) runs where Claude is needed or asked for, and `--model ''` inherits the
vendor CLI default. The
harness micro-deploys the skill, the base `task` and `task_check` skills,
and the five `auto_*_task` agents through the deploy script so named-agent
runs stay hermetic, and records `artefacts_read_from_micro_deployment` in
each `timing.json`."""

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
WORKSPACE = THIS.parent / "workspace"

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import eval_cache  # noqa: E402  (shared local test helper; tests/ is gitignored)
import micro_deploy  # noqa: E402  (shared micro-deployment helper)
import vendor  # noqa: E402  (shared vendor helper; tests/ is gitignored)

ARTEFACTS = [
    "task_auto_check",
    "task",
    "task_check",
    "auto_drift_task",
    "auto_gate_task",
    "auto_reviewer_task",
    "auto_shaper_task",
    "auto_verifier_task",
]


def source_roots_for():
    """task_auto_check loads the task_auto_check skill, which reads the base
    `task` skill via <authority>, wraps `task_check` through the gate agent, and
    spawns the auto_*_task helper agents. Hash all of them so an edit to the
    base skill or any helper agent invalidates the cache, not just an edit to
    task_auto_check itself. Over-inclusion only forces an occasional extra run;
    it can never serve a stale pass."""
    return micro_deploy.source_roots_for(ARTEFACTS)


def eval_timeout(eval_id: str, default: int) -> int:
    """Per-eval worker timeout from evals.json, falling back to the CLI
    default, so a structurally slower eval declares its own budget instead of
    forcing the whole suite up to its worst case."""
    with open(THIS / "evals.json", encoding="utf-8") as fh:
        for e in json.load(fh)["evals"]:
            if e["id"] == eval_id:
                return int(e.get("timeout", default))
    return default


DEFAULT_IDS = [
    "mechanical_lint_ready",
    "mechanical_lint_link",
    "mechanical_lint_frontmatter",
    "mechanical_lint_markdown",
    "mechanical_lint_oversized_surface",
    "already_ready",
    "intent_drift_human_route",
    "drift_gate_narrowing_clean",
    "drift_gate_refinement_clean",
    "drift_gate_broadening_drift",
    "drift_gate_committed_broadening_clean",
    "repair_to_ready",
    "scope_split_stuck",
    "fidelity_rejects_drift",
    "no_verified_fix",
    "cap_override",
    "gate_failure_user_stop",
    "drift_failure_user_stop",
    "verifier_failure_user_stop",
    "guard_rebaseline_after_gate",
    "interaction_scan_surfaces",
    "interaction_scan_no_false_alarm",
    "immediate_ready_citations_survive",
    "immediate_ready_citations_overturn",
    "regroup_via_reviewer",
    "regroup_immediate_ready",
]

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


def stage(eval_id: str, target: pathlib.Path) -> dict[str, str]:
    emit = (
        f'eval "$(bash {shlex.quote(str(STAGE))} {shlex.quote(eval_id)} '
        f'{shlex.quote(str(target))})"; '
        'printf "%s\\0%s\\0%s\\0%s\\0" '
        '"$sandbox_proj" "$skill_name" "$skill_path" "$prompt"'
    )
    out = subprocess.run(["bash", "-c", emit], capture_output=True, text=True, check=True).stdout
    sandbox_proj, skill_name, skill_path, prompt, _ = out.split("\0")
    return {
        "sandbox_proj": sandbox_proj,
        "skill_name": skill_name,
        "skill_path": skill_path,
        "prompt": prompt,
    }


def worker_completed(rc: int, stdout: str) -> bool:
    """Whether a worker run is trustworthy for grading. The CLI must have
    exited 0 and produced a final response. A non-zero rc (timeout → -1,
    crash, API error) or an empty response means the loop did not finish,
    so grade.sh's checks on the resulting sandbox reflect only partial state
    and must not count as a pass — a timed-out loop that stamped an early
    status could otherwise masquerade as a clean 'surfaced-stuck' verdict."""
    return rc == 0 and bool(stdout.strip())


def run_one(
    eval_id: str,
    run_dir: pathlib.Path,
    resolved: vendor.Resolved,
    timeout: int,
    cache,
    force: bool,
):
    timeout = eval_timeout(eval_id, timeout)
    eval_dir = run_dir / eval_id
    target = eval_dir / "sandbox"
    target.mkdir(parents=True, exist_ok=True)

    staged = stage(eval_id, target)
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
        )
        if not force:
            hit = cache.lookup(eval_id, key)
            if hit is not None:
                eval_cache.write_replay_artifacts(eval_dir, hit)
                verdict = "PASS" if hit["passed"] else "FAIL"
                print(f"  [{eval_id}] CACHED {verdict} "
                      f"(skill={staged['skill_name']}, "
                      f"graded {hit.get('graded_at', '?')}, "
                      f"model={hit.get('model', '?')}) — skipped {resolved.config.label}; "
                      "--force to re-run\n", flush=True)
                return hit["passed"], True

    print(
        f"  [{eval_id}] running {resolved.config.label} "
        f"(skill={staged['skill_name']}, model={model_label}) ...",
        flush=True,
    )
    start = time.time()
    with micro_deploy.micro_deploy(
        resolved.vendor, ARTEFACTS, pathlib.Path(workdir), preflight=False
    ) as md:
        prompt = WORKER_PROMPT.format(
            skill_path=md.path_map["task_auto_check"],
            workdir=workdir,
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

    (eval_dir / "response.txt").write_text(stdout)
    (eval_dir / "stderr.txt").write_text(stderr)
    (eval_dir / "timing.json").write_text(
        json.dumps(
            {
                "eval_id": eval_id,
                "skill_name": staged["skill_name"],
                "duration_s": duration_s,
                "worker_rc": rc,
                "claude_rc": rc,
                "model": model_label,
                "artefacts_read_from_micro_deployment": integrity,
            },
            indent=2,
        )
    )

    grade = subprocess.run(
        ["bash", str(GRADE), eval_id, workdir],
        capture_output=True,
        text=True,
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
              f"grade.sh ran on partial sandbox state and cannot be trusted "
              f"(grade alone would have said {'PASS' if grade_passed else 'FAIL'})\n",
              flush=True)
    elif not integrity["passed"]:
        print(f"  [{eval_id}] FAIL — worker read artefacts outside the "
              f"micro-deployment: {integrity['out_of_set']}\n", flush=True)
    else:
        print(f"  [{eval_id}] {'PASS' if passed else 'FAIL'} (worker rc={rc})\n", flush=True)

    # Cache only a conclusive verdict from a completed worker: a timeout or
    # crash is transient/environmental, not a property of the inputs, so
    # caching it would replay a spurious verdict on a later clean run.
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
    parser = argparse.ArgumentParser()
    parser.add_argument("ids", nargs="*", default=None)
    vendor.add_vendor_arguments(parser)
    parser.add_argument("--timeout", type=int, default=1800,
                        help="Default per-eval worker timeout in seconds. The repair "
                             "loop runs ~900-1500s solo, so the default leaves "
                             "headroom above that band rather than sitting on its "
                             "floor. An eval carrying its own \"timeout\" in "
                             "evals.json overrides this.")
    parser.add_argument("--force", action="store_true",
                        help="Ignore cached verdicts and re-run every eval, "
                             "refreshing the cache with the new result.")
    parser.add_argument("--no-cache", action="store_true",
                        help="Neither read nor write the verdict cache.")
    args = parser.parse_args()

    ids = args.ids if args.ids else DEFAULT_IDS
    cache = None if args.no_cache else eval_cache.EvalCache(THIS / ".eval_cache")
    resolved = vendor.resolve(args)
    model_label = resolved.worker_model or "<inherit>"

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{ts}-{os.getpid()}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")
    print(
        f"Worker vendor: {resolved.vendor}; command: {resolved.config.label}; "
        f"model: {model_label}; evals: {ids}"
    )
    cache_mode = "off" if cache is None else ("force-refresh" if args.force else "on")
    print(f"Verdict cache: {cache_mode}\n")

    micro_deploy.preflight_auth(resolved.vendor, resolved.bin, resolved.worker_model)

    results = {
        eval_id: run_one(eval_id, run_dir, resolved, args.timeout, cache, args.force)
        for eval_id in ids
    }

    ok = sum(1 for passed, _ in results.values() if passed)
    cached_n = sum(1 for _, was_cached in results.values() if was_cached)
    print("=" * 56)
    print(f"graded: {ok}/{len(results)} evals passed ({cached_n} from cache)")
    for eval_id, (passed, was_cached) in results.items():
        print(f"  {eval_id}: {'PASS' if passed else 'FAIL'}{' (cached)' if was_cached else ''}")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
