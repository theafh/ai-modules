#!/usr/bin/env python3
"""Vendor-aware worker runner for the task-family behavioral evals.

Phase 2 (the skill actually running) used to be operator-driven in the
host session, i.e. on whatever model the session inherited. This runner
instead spawns one vendor-resolved print-mode worker per eval. By default
that means the Cursor worker (`agent -p`, model `auto`); `--vendor claude`
(model `sonnet`) runs where Claude is needed or asked for, and
`--model ''` inherits the vendor CLI default. The meta level on top — the deterministic `grade.sh`, and any
prose-verdict confirmation the operator does by reading `response.txt` —
stays model-free.

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
   `artefacts_read_from_micro_deployment` integrity record) under
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
      [--vendor claude|cursor] [--model sonnet|auto|'']
      [--timeout 600] [--worker-bin <bin>]
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
import micro_deploy  # noqa: E402  (shared micro-deployment helper)
import vendor  # noqa: E402  (shared vendor helper; tests/ is gitignored)

AUTO_AGENTS = [
    "auto_drift_task",
    "auto_gate_task",
    "auto_reviewer_task",
    "auto_shaper_task",
    "auto_verifier_task",
]

# The siblings that spawn the auto_*_task agents: task_auto_check drives them,
# and task_fix escalates to auto_shaper_task.
AGENT_SPAWNING_SKILLS = {"task_auto_check", "task_fix"}


def artefacts_for(skill_name: str) -> list[str]:
    """Names micro-deployed for one eval, following what its sibling reaches.

    Every sibling reads the base `task` hub through its <authority> step. The
    two agent-spawning siblings also get the five auto_*_task agents and the
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


def run_one(eval_id: str, run_dir: pathlib.Path, resolved: vendor.Resolved,
            timeout: int, cache, force: bool):
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
            source_roots=source_roots_for(staged["skill_name"]),
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

    print(f"  [{eval_id}] running {resolved.config.label} "
          f"(skill={staged['skill_name']}, model={model_label}) ...", flush=True)
    start = time.time()
    with micro_deploy.micro_deploy(
        resolved.vendor, artefacts_for(staged["skill_name"]),
        pathlib.Path(workdir), preflight=False,
    ) as md:
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
        integrity = micro_deploy.integrity_record(
            worker.read_paths, worker.out_of_set_paths
        )
    duration_s = time.time() - start

    (eval_dir / "response.txt").write_text(stdout)
    (eval_dir / "stderr.txt").write_text(stderr)
    (eval_dir / "timing.json").write_text(json.dumps({
        "eval_id": eval_id,
        "skill_name": staged["skill_name"],
        "duration_s": duration_s,
        "worker_rc": rc,
        "claude_rc": rc,
        "model": model_label,
        "artefacts_read_from_micro_deployment": integrity,
    }, indent=2))

    grade = subprocess.run(
        ["bash", str(GRADE), eval_id, workdir], capture_output=True, text=True
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
        print(f"  [{eval_id}] {'PASS' if passed else 'FAIL'} (worker rc={rc})\n",
              flush=True)

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
    parser.add_argument("ids", nargs="*", default=None,
                        help="Eval ids to run (default: every id in DEFAULT_IDS)")
    vendor.add_vendor_arguments(parser)
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

    ids = args.ids if args.ids else DEFAULT_IDS
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

    # Sequential on purpose: keeps each worker's sandbox isolation
    # checks unambiguous and the host filesystem quiet.
    results = {i: run_one(i, run_dir, resolved, args.timeout, cache, args.force)
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
