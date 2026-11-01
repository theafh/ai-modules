#!/usr/bin/env python3
"""Vendor-aware worker runner for the git_review behavioral evals.

One vendor-resolved print-mode worker runs per eval, so the skill under test
uses one explicit worker policy each run: the worker runs on Cursor by
default (`auto`), `--vendor claude` (`sonnet`) runs where Claude is needed or
asked for, and `--model ''` inherits the vendor CLI default. The meta level on
top stays model-free: the deterministic `grade.sh`, and the operator's reading
of `response.txt` for the prose-verdict expectations.

Each eval is one job in the shared pool from `tests/lib/eval_runner.py`
(`--workers`, default `vendor.DEFAULT_PARALLEL_WORKERS`, each job with its own
TMPDIR). Every eval stages its own sandbox root, so no two jobs share a
repository. Per eval the job:

1. Stages a fresh sandbox via `stage.sh <id> <target>` under the job
   environment and reads back `sandbox_repo`, `prompt`, `target`, `gh_env`.
2. Micro-deploys git_review, git_checkout, git_commit, git_refresh, and the
   guardrail hub through the deploy script into a scratch home, wraps each
   deployed bundled script in a logging shim that appends to the sandbox's
   `script_calls.log` and then runs an unshimmed copy of the deployed script
   kept in that scratch home, points the worker's TMPDIR, TEMP, and TMP at the
   job's own directory, and runs a vendor-resolved print-mode worker with the
   sandbox repo as the working directory. When the eval staged a stub `gh`,
   its `gh_env` file is folded into the worker environment and its `bin`
   directory goes first on PATH, so the forge layer is served from fixture JSON
   and every call is recorded.
3. Captures `response.txt` / `stderr.txt` / `timing.json` (with `started_at`,
   `ended_at`, the job `tmpdir`, and the
   `artefacts_read_from_micro_deployment` integrity record) under
   `tests/git_review/workspace/run-<ts>/<id>/`.
4. Grades the post-run sandbox with `grade.sh <id> <sandbox_repo>
   <response.txt>` under the same job environment.

Exit code is 0 only when every eval's worker completed cleanly (CLI rc 0 with a
real response) AND its deterministic grade passed. A timed-out or crashed worker
fails the eval regardless of grade.sh, which would otherwise pass on the
partially-correct sandbox state an aborted run left.

Usage:
    python3 tests/git_review/evals/run.py [eval_id ...]   # default: all
      [--vendor claude|cursor] [--model sonnet|auto|'']
      [--workers 4] [--timeout 600] [--worker-bin <bin>] [--force] [--no-cache]
"""

from __future__ import annotations

import argparse
import datetime
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
import eval_cache  # noqa: E402  (shared local test helper; run output is gitignored)
import eval_runner  # noqa: E402  (shared Pattern A job pool)
import micro_deploy  # noqa: E402  (shared micro-deployment helper)
import vendor  # noqa: E402  (shared vendor helper)
import worker_isolation  # noqa: E402  (shared sandbox-root helper)

# The sole run root: tests/git_review/workspace, beside evals/.
WORKSPACE = eval_runner.resolve_workspace(THIS)

ARTEFACTS = ["git_review", "git_checkout", "git_commit", "git_refresh", "guardrail"]

ISOLATION_PREFIX = "git_review_"

DEFAULT_IDS = eval_runner.load_eval_ids(EVALS)


def source_roots_for():
    """Every skill a git_review verdict depends on, taken from the one
    declaration that also decides what each eval deploys. The git_review
    directory holds the SKILL.md the worker loads, its scripts/, and its
    references/. The sibling skills it hands work to (git_checkout, git_commit)
    join it, because a change to either one changes what a run of this skill
    does. git_refresh joins them because git_review detects the default branch
    the way that skill does, so a worker may load it by name. The guardrail hub
    joins them as well, because git_review ranks its findings by the authority
    hierarchy that skill defines and keeps no copy of that hierarchy itself.

    This hashes the source trees rather than the deployed copies, which live
    under a per-run scratch home, so the key stays stable across runs."""
    return micro_deploy.source_roots_for(ARTEFACTS)


def shim_deployed_scripts(
    deploy: micro_deploy.MicroDeployHandle, target_root: pathlib.Path
) -> None:
    """Wrap each deployed bundled script in a logging shim.

    Which bundled script a run invoked is a transcript fact the runner does
    not keep, so every deployed `scripts/*.sh` becomes a shim that records the
    invocation in `<target>/script_calls.log` and then runs the deployed
    script. The untouched deployed skill tree is copied under the scratch home
    first and the shim execs that copy, so the behaviour under test is the
    deployed script's and a worker that follows a shim never leaves the
    micro-deployment for the repository checkout.
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
                "# Logging shim written by tests/git_review/evals/run.py. Records the\n"
                "# call, then runs the unshimmed deployed bundled script.\n"
                f"printf '%s %s\\n' {shlex.quote(deployed_script.name)} \"$*\" "
                f">> {shlex.quote(str(log))}\n"
                f"exec {shlex.quote(str(real_script))} \"$@\"\n"
            )
            deployed_script.chmod(0o755)


WORKER_PROMPT = """\
You are running an automated skill regression eval. Do exactly this:

1. Read the skill definition file in full: {skill_path}
2. Follow that skill's instructions exactly as written. Resolve any
   bundled scripts it references relative to that SKILL.md's directory.
3. When that skill hands work to git_checkout or git_commit, resolve those
   named sibling handoffs through these staged copies and their bundled
   scripts (do not search elsewhere for them):
   - git_checkout: {checkout_skill_path}
   - git_commit: {commit_skill_path}
4. Carry out the user request below, operating only inside the current
   working directory ({workdir}):

{prompt}
"""


def stage(eval_id: str, target: pathlib.Path, env: Mapping[str, str]) -> dict:
    """Run stage.sh and read back the staged values. stage.sh prints
    printf-%q-quoted `name=value` lines meant to be `eval`'d in bash, so we let
    bash eval them and re-emit the raw values NUL-separated. The script
    captures stage.sh's output before evaluating it and exits with stage.sh's
    status when it fails, so a failed stage raises here. An empty or missing
    sandbox_repo raises too, because pathlib.Path("") is the current directory
    and the worker would otherwise start in the checkout."""
    emit = (
        f'out="$({shlex.quote(str(STAGE))} {shlex.quote(eval_id)} '
        f'{shlex.quote(str(target))})" || exit $?; eval "$out"; '
        'printf "%s\\0%s\\0%s\\0%s\\0" '
        '"$sandbox_repo" "$prompt" "$target" "$gh_env"'
    )
    result = subprocess.run(
        ["bash", "-c", emit], capture_output=True, text=True, env=dict(env)
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"stage.sh failed for eval {eval_id} (rc={result.returncode}): "
            f"{result.stderr.strip()}"
        )
    sandbox_repo, prompt, fixture_target, gh_env, _ = result.stdout.split("\0")
    if not sandbox_repo or not pathlib.Path(sandbox_repo).is_dir():
        raise RuntimeError(
            f"stage.sh staged no sandbox repository for eval {eval_id}: "
            f"{sandbox_repo!r}"
        )
    return {
        "sandbox_repo": sandbox_repo,
        "prompt": prompt,
        "target": fixture_target,
        "gh_env": gh_env,
    }


def path_without_gh(path_value: str) -> str:
    """PATH with every directory holding a `gh` executable dropped.

    A git-only eval asserts the run names the forge layer unavailable, which is
    only a real assertion when `gh` is genuinely absent. The operator's own
    machine usually has one, and the worker inherits their PATH, so the runner
    removes it rather than leaving the eval to pass or fail on who ran it."""
    kept = []
    for entry in path_value.split(os.pathsep):
        if not entry:
            continue
        candidate = pathlib.Path(entry) / "gh"
        if candidate.is_file() and os.access(candidate, os.X_OK):
            continue
        kept.append(entry)
    return os.pathsep.join(kept)


def env_for(base_env: dict, gh_env: str) -> dict:
    """The worker environment, with the stub gh folded in when the eval staged
    one. The env file holds plain KEY=VALUE lines; GH_STUB_BIN goes first on
    PATH so the stub outranks a real gh on the operator's machine. An eval that
    staged no stub runs with `gh` stripped from PATH entirely."""
    env = dict(base_env)
    if not gh_env:
        env["PATH"] = path_without_gh(env.get("PATH", ""))
        return env
    for line in pathlib.Path(gh_env).read_text().splitlines():
        if not line.strip() or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key] = value
    stub_bin = env.get("GH_STUB_BIN")
    if stub_bin:
        env["PATH"] = stub_bin + ":" + env.get("PATH", "")
    return env


def worker_completed(rc: int, stdout: str) -> bool:
    """Whether a worker run is trustworthy for grading. The CLI must have exited
    0 and produced a final response. A non-zero rc (timeout → -1, crash, API
    error) or an empty response means the skill did not finish, so grade.sh's
    checks reflect only partial state and must not count as a pass."""
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
                  f"model={hit.get('model', '?')}); skipped {resolved.config.label}, "
                  "--force to re-run\n", flush=True)
            return bool(hit["passed"]), True

        target_root = pathlib.Path(staged["target"])
        stub = " (stub gh)" if staged["gh_env"] else ""
        print(f"  [eval-{eval_id}] running {resolved.config.label} "
              f"(model={model_label}){stub} ...", flush=True)
        started_at = time.time()
        # The skills deploy into a scratch home beside, never inside, the repo
        # under review, so a review never sees a copied skill tree in its worktree.
        with micro_deploy.micro_deploy(
            resolved.vendor, ARTEFACTS, pathlib.Path(workdir), preflight=False
        ) as md:
            shim_deployed_scripts(md, target_root)
            # The worker writes its scratch files into the job's own TMPDIR.
            # A fixture that sets TMPDIR in gh_env (push_approval points it at
            # the eval target so report.md's mtime is gradeable) folds over it.
            _apply_job_temp(md.env, env)
            md.env.update(env_for(md.env, staged["gh_env"]))
            prompt = WORKER_PROMPT.format(
                skill_path=md.path_map["git_review"],
                workdir=workdir,
                prompt=staged["prompt"],
                checkout_skill_path=str(md.path_map["git_checkout"]),
                commit_skill_path=str(md.path_map["git_commit"]),
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
            tmpdir=env.get("TMPDIR"),
            artefacts_read_from_micro_deployment=integrity,
            checkout_unread=checkout_unread,
        )

        # Keep the call logs beside the response: they are half the evidence for
        # every publishing eval and the sandbox is discarded with the run directory.
        for log_name in ("gh_calls.log", "script_calls.log"):
            src_log = target_root / log_name
            if src_log.exists():
                (eval_dir / log_name).write_text(src_log.read_text())

        # The grader runs under the job's environment, so its mktemp stays in
        # the job's TMPDIR. The three-argument form is this harness's canonical
        # grade call: eval id, sandbox repo, and the captured response path.
        response_path = eval_dir / "response.txt"
        grade = subprocess.run(
            ["bash", str(GRADE), eval_id, workdir, str(response_path)],
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
            print(f"  [eval-{eval_id}] FAIL, worker did not complete ({why}); "
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
        # crash is transient rather than a property of the inputs, so caching it
        # would replay a spurious verdict on a later clean run.
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
        description="Run the git_review behavioral evals on a vendor worker."
    )
    parser.add_argument("ids", nargs="*", default=None,
                        help=f"Eval ids to run (default: {' '.join(DEFAULT_IDS)}).")
    vendor.add_vendor_arguments(parser)
    eval_runner.add_workers_argument(parser)
    parser.add_argument("--timeout", type=int, default=600,
                        help="Per-eval worker timeout in seconds (default 600). "
                             "A full review reads every changed file, so these "
                             "runs are longer than the git_commit ones.")
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

    # Parallel by default: every eval stages its own sandbox root and
    # eval_runner gives every job its own TMPDIR, so no two jobs share a
    # repository or a temp directory. Model contention is a --timeout and
    # --workers tuning concern; pass --workers 1 to serialize.
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
