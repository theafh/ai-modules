#!/usr/bin/env python3
"""Vendor-aware worker runner for the git_refresh behavioral evals.

One vendor-resolved print-mode worker runs per eval. By default that is the
Cursor worker (`agent -p`, model `auto`); `--vendor claude` (model `sonnet`)
runs where Claude is needed or the operator asks for it, and `--model ''`
inherits the vendor CLI default. Grading stays model-free: the deterministic
`grade.sh`, plus the operator's reading of `response.txt` for the expectations
grade.sh prints as `response` lines.

Each eval is one job in the shared pool from `tests/lib/eval_runner.py`
(`--workers`, default 4, each job with its own TMPDIR). Every job stages into
its own sandbox root, so no two jobs share a repository. Per eval the job:

1. Replays the stored verdict when the cache holds one for unchanged inputs.
2. Otherwise takes a fresh sandbox root from
   `worker_isolation.create_sandbox_root`, stages the eval's fixture there via
   `stage.sh <id> <root>`, and reads back `sandbox_repo` and `prompt`.
3. Micro-deploys the declared artefacts into a scratch home, wraps the
   deployed `refresh_repo.sh` in a logging shim that appends each call to the
   sandbox root's `script_calls.log` and then runs an unshimmed copy kept in
   that scratch home, and runs the worker with the sandbox clone as its
   working directory and a prompt that tells it to load the deployed SKILL.md.
4. Writes `response.txt`, `stderr.txt`, and `timing.json` (with the
   `artefacts_read_from_micro_deployment` and `checkout_unread` records) under
   `tests/git_refresh/workspace/run-<ts>-<pid>/<id>/`, then grades the clone
   with `grade.sh <id> <sandbox_repo>`.

The auth probe runs once, before the first job, and only when at least one
requested eval will spawn a worker, so a run that replays every verdict from
the cache spawns no worker process at all.

Exit code is 0 only when every eval's worker completed cleanly (CLI rc 0 with
a real response), both read checks passed, and its grade passed. A timed-out
or crashed worker fails the eval regardless of grade.sh, which would otherwise
pass on the untouched sandbox an aborted run leaves behind.

Usage:
    python3 tests/git_refresh/evals/run.py [eval_id ...]   # default: all
      [--vendor claude|cursor] [--model sonnet|auto|''] [--worker-bin <bin>]
      [--workers 4] [--timeout 300] [--force] [--no-cache]
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import pathlib
import shlex
import shutil
import subprocess
import sys
import time
from collections.abc import Mapping

THIS = pathlib.Path(__file__).resolve().parent
STAGE = THIS / "stage.sh"
GRADE = THIS / "grade.sh"
EVALS = THIS / "evals.json"

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import eval_cache  # noqa: E402  (shared verdict cache)
import eval_runner  # noqa: E402  (shared Pattern A job pool)
import micro_deploy  # noqa: E402  (shared micro-deployment helper)
import vendor  # noqa: E402  (shared vendor helper)
import worker_isolation  # noqa: E402  (shared sandbox-root helper)

WORKSPACE = eval_runner.resolve_workspace(THIS)

SKILL = "git_refresh"

# The one declaration of what a worker may load. It feeds the deploy script's
# --only list through micro_deploy() and the cache key through
# source_roots_for(). git_refresh names no sibling skill, agent, or style, so
# the skill under test is the whole list.
ARTEFACTS = ["git_refresh"]

ISOLATION_PREFIX = "git_refresh_"

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


def source_roots_for() -> list[pathlib.Path]:
    """Every artefact source a verdict depends on, from the one declaration."""

    return micro_deploy.source_roots_for(ARTEFACTS)


def eval_prompts() -> dict[str, str]:
    """Map each eval id (as a string) to its prompt in evals.json.

    stage.sh prints the same prompt from the same file, so the cache key can
    be computed before any fixture is staged.
    """

    data = json.loads(EVALS.read_text(encoding="utf-8"))
    return {str(entry["id"]): entry["prompt"] for entry in data["evals"]}


def cache_key(eval_id: str, prompt: str, resolved: vendor.Resolved) -> str:
    """The content key for one eval's verdict."""

    return eval_cache.content_key(
        source_roots=source_roots_for(),
        harness_dir=THIS,
        model=resolved.worker_model,
        eval_id=eval_id,
        prompt=prompt,
        dependencies=eval_cache.dependencies_for(EVALS, eval_id),
    )


def evals_needing_worker(
    ids: list[str],
    prompts: Mapping[str, str],
    resolved: vendor.Resolved,
    cache: eval_cache.EvalCache | None,
    force: bool,
) -> list[str]:
    """The requested ids whose verdict the cache cannot replay."""

    if cache is None or force:
        return list(ids)
    return [
        eval_id
        for eval_id in ids
        if cache.lookup(eval_id, cache_key(eval_id, prompts[eval_id], resolved))
        is None
    ]


def stage(
    eval_id: str, target: pathlib.Path, env: Mapping[str, str]
) -> dict[str, str]:
    """Run stage.sh and read back the staged sandbox_repo and prompt.

    stage.sh prints printf-%q-quoted `name=value` lines meant to be `eval`'d in
    bash, so bash evaluates them and re-emits the raw values NUL-separated.
    The script captures stage.sh's output before evaluating it and exits with
    stage.sh's status when it fails, so a failed stage raises here. An empty
    or missing sandbox_repo raises too, because pathlib.Path("") is the
    current directory and the worker would otherwise start in the checkout.
    """

    emit = (
        f'out="$(bash {shlex.quote(str(STAGE))} {shlex.quote(eval_id)} '
        f'{shlex.quote(str(target))})" || exit $?; eval "$out"; '
        'printf "%s\\0%s\\0" "$sandbox_repo" "$prompt"'
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
    sandbox_repo, prompt, _rest = result.stdout.split("\0")
    if not sandbox_repo or not pathlib.Path(sandbox_repo).is_dir():
        raise RuntimeError(
            f"stage.sh staged no sandbox repository for eval {eval_id}: "
            f"{sandbox_repo!r}"
        )
    return {"sandbox_repo": sandbox_repo, "prompt": prompt}


def shim_deployed_scripts(
    deploy: micro_deploy.MicroDeployHandle, target_root: pathlib.Path
) -> None:
    """Wrap each deployed bundled script in a logging shim.

    Which helper calls a run made, and in what order, is a transcript fact the
    runner does not keep, so every deployed `scripts/*.sh` becomes a shim that
    appends `<script> <args>` to `<target>/script_calls.log` and then runs the
    deployed script. The untouched deployed skill tree is copied under the
    scratch home first and the shim execs that copy, so the behaviour under
    test is the deployed script's and a worker that follows a shim never
    leaves the micro-deployment for the repository checkout. grade.sh reads
    the log to prove eval 3's default run came before its `--prune-gone` call.
    """

    log = target_root / "script_calls.log"
    unshimmed_root = deploy.scratch_home / "unshimmed"
    for name in ARTEFACTS:
        deployed_dir = deploy.path_map[name].parent
        scripts_dir = deployed_dir / "scripts"
        if not scripts_dir.is_dir():
            continue
        unshimmed_dir = unshimmed_root / name
        shutil.copytree(deployed_dir, unshimmed_dir)
        for deployed_script in sorted(scripts_dir.glob("*.sh")):
            real_script = unshimmed_dir / "scripts" / deployed_script.name
            deployed_script.write_text(
                "#!/usr/bin/env bash\n"
                "# Logging shim written by tests/git_refresh/evals/run.py. Records\n"
                "# the call, then runs the unshimmed deployed bundled script.\n"
                f"printf '%s %s\\n' {shlex.quote(deployed_script.name)} \"$*\" "
                f">> {shlex.quote(str(log))}\n"
                f"exec {shlex.quote(str(real_script))} \"$@\"\n"
            )
            deployed_script.chmod(0o755)


def worker_completed(rc: int, stdout: str) -> bool:
    """Whether a worker run is trustworthy for grading.

    The CLI must have exited 0 and produced a final response. A non-zero rc
    (timeout is -1, crash, API error) or an empty response means the skill did
    not finish, so grade.sh's checks reflect only partial state.
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
    prompt_text: str,
    run_dir: pathlib.Path,
    resolved: vendor.Resolved,
    timeout: int,
    cache: eval_cache.EvalCache | None,
    force: bool,
    env: Mapping[str, str],
) -> tuple[bool, bool]:
    """Run one eval inside the caller's job. Returns (passed, was_cached)."""

    eval_dir = run_dir / eval_id
    eval_dir.mkdir(parents=True, exist_ok=True)
    model_label = resolved.worker_model or "<inherit>"

    key = cache_key(eval_id, prompt_text, resolved) if cache is not None else None
    hit = eval_runner.cache_lookup(cache, eval_id, key, eval_dir, force=force)
    if hit is not None:
        verdict = "PASS" if hit["passed"] else "FAIL"
        print(
            f"  [{eval_id}] CACHED {verdict} "
            f"(graded {hit.get('graded_at', '?')}, "
            f"model={hit.get('model', '?')}) — skipped "
            f"{resolved.config.label}; --force to re-run\n",
            flush=True,
        )
        return bool(hit["passed"]), True

    root = worker_isolation.create_sandbox_root(ISOLATION_PREFIX)
    try:
        staged = stage(eval_id, root, env)
        workdir = staged["sandbox_repo"]
        print(
            f"  [{eval_id}] running {resolved.config.label} "
            f"(model={model_label}) ...",
            flush=True,
        )
        started_at = time.time()
        # The scratch home sits beside the sandbox, never inside the clone, so
        # the deployment adds nothing to the worktree the grader compares.
        with micro_deploy.micro_deploy(
            resolved.vendor, ARTEFACTS, pathlib.Path(workdir), preflight=False
        ) as deploy:
            shim_deployed_scripts(deploy, pathlib.Path(workdir).parent)
            _apply_job_temp(deploy.env, env)
            prompt = WORKER_PROMPT.format(
                skill_path=deploy.path_map[SKILL],
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
            artefacts_read_from_micro_deployment=integrity,
            checkout_unread=checkout_unread,
            started_at=started_at,
            ended_at=ended_at,
        )

        grade = subprocess.run(
            ["bash", str(GRADE), eval_id, workdir],
            capture_output=True,
            text=True,
            env=dict(env),
        )
        grading_output = grade.stdout + grade.stderr
        (eval_dir / "grading.txt").write_text(grading_output)
        print(f"  [{eval_id}] grade.sh\n{grading_output}", end="", flush=True)
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
                print(f"  [{eval_id}] FAIL — {fail}\n", flush=True)
            else:
                word = "PASS" if passed else "FAIL"
                print(f"  [{eval_id}] {word} (worker rc={rc})\n", flush=True)

        # Cache only a conclusive verdict from a completed worker: a timeout or
        # crash is environmental, so caching it would replay a spurious verdict.
        if completed:
            eval_runner.cache_record(
                cache,
                eval_id,
                key,
                passed=passed,
                model=model_label,
                duration_s=duration_s,
                worker_rc=rc,
                grading_output=grading_output,
                response_excerpt=stdout[: eval_cache.RESPONSE_EXCERPT_CHARS],
            )
        return passed, False
    finally:
        worker_isolation.preserve_sandbox_copy(root, eval_dir / "sandbox")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run the git_refresh behavioral evals on a vendor worker."
    )
    parser.add_argument(
        "ids",
        nargs="*",
        default=None,
        help=f"Eval ids to run (default: {' '.join(DEFAULT_IDS)}).",
    )
    vendor.add_vendor_arguments(parser)
    eval_runner.add_workers_argument(parser)
    parser.add_argument(
        "--timeout",
        type=int,
        default=300,
        help="Per-eval worker timeout in seconds (default 300).",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help=(
            "Ignore cached verdicts and re-run every eval, refreshing the "
            "cache with the new result."
        ),
    )
    parser.add_argument(
        "--no-cache",
        action="store_true",
        help="Neither read nor write the verdict cache.",
    )
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
    prompts = eval_prompts()

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{stamp}-{os.getpid()}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")
    print(
        f"Worker vendor: {resolved.vendor}; command: {resolved.config.label}; "
        f"model: {model_label}; workers: {args.workers}; evals: {ids}"
    )
    if cache is None:
        cache_mode = "off"
    elif args.force:
        cache_mode = "force-refresh"
    else:
        cache_mode = "on"
    print(f"Verdict cache: {cache_mode}\n")

    if evals_needing_worker(ids, prompts, resolved, cache, args.force):
        micro_deploy.preflight_auth(
            resolved.vendor, resolved.bin, resolved.worker_model
        )
    else:
        print("Every requested verdict replays from the cache; no worker runs.\n")

    def make_job(eval_id: str) -> eval_runner.JobFn:
        def job(env: Mapping[str, str]) -> tuple[bool, bool]:
            return run_one(
                eval_id,
                prompts[eval_id],
                run_dir,
                resolved,
                args.timeout,
                cache,
                args.force,
                env,
            )

        return job

    def on_error(index: int, exc: Exception) -> tuple[bool, bool]:
        print(f"  [{ids[index]}] FAIL — harness fault: {exc}\n", flush=True)
        return False, False

    results = eval_runner.run_jobs(
        [make_job(eval_id) for eval_id in ids],
        workers=args.workers,
        on_error=on_error,
    )
    rows = [
        (eval_id, passed, was_cached)
        for eval_id, (passed, was_cached) in zip(ids, results)
    ]
    eval_runner.print_summary(rows)
    return 0 if all(passed for _eval_id, passed, _cached in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
