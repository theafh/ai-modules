#!/usr/bin/env python3
"""Vendor-aware worker runner for the git_review behavioral evals.

One vendor-resolved print-mode worker runs per eval, so the skill under test
uses one explicit worker policy each run: the worker runs on Cursor by
default (`auto`), `--vendor claude` (`sonnet`) runs where Claude is needed or asked for, and `--model ''` inherits the vendor CLI default. The meta level on top stays model-free: the deterministic
`grade.sh`, and the operator's reading of `response.txt` for the prose-verdict
expectations.

Per eval the runner:

1. Stages a fresh sandbox via `stage.sh <id> <target>` and reads back
   `sandbox_repo`, `prompt`, `target`, `gh_env`.
2. Micro-deploys git_review, git_checkout, git_commit, git_refresh, and the
   guardrail hub through the deploy script into a scratch home, wraps each
   deployed bundled script in a logging shim that appends to the sandbox's
   `script_calls.log` and then runs an unshimmed copy of the deployed script
   kept in that scratch home, and runs a vendor-resolved print-mode worker
   with the sandbox repo as the working directory. When the eval staged a
   stub `gh`, its `gh_env` file is folded into the worker environment and its
   `bin` directory goes first on PATH, so the forge layer is served from
   fixture JSON and every call is recorded.
3. Captures `response.txt` / `stderr.txt` / `timing.json` (with the
   `artefacts_read_from_micro_deployment` integrity record) under
   `workspace/run-<ts>/<id>/`.
4. Grades the post-run sandbox with `grade.sh <id> <sandbox_repo>
   <response.txt>`.

Exit code is 0 only when every eval's worker completed cleanly (CLI rc 0 with a
real response) AND its deterministic grade passed. A timed-out or crashed worker
fails the eval regardless of grade.sh, which would otherwise pass on the
partially-correct sandbox state an aborted run left.

Usage:
    python3 tests/git_review/evals/run.py [eval_id ...]   # default: all
      [--vendor claude|cursor] [--model sonnet|auto|'']
      [--timeout 600] [--worker-bin <bin>] [--force] [--no-cache]
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

THIS = pathlib.Path(__file__).resolve().parent
STAGE = THIS / "stage.sh"
GRADE = THIS / "grade.sh"
EVALS = THIS / "evals.json"
WORKSPACE = THIS / "workspace"

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import eval_cache  # noqa: E402  (shared local test helper; run output is gitignored)
import micro_deploy  # noqa: E402  (shared micro-deployment helper)
import vendor  # noqa: E402  (shared vendor helper)

ARTEFACTS = ["git_review", "git_checkout", "git_commit", "git_refresh", "guardrail"]


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


def default_ids():
    return [str(e["id"]) for e in json.loads(EVALS.read_text())["evals"]]


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


def stage(eval_id: str, target: pathlib.Path) -> dict:
    """Run stage.sh and read back the staged values. stage.sh prints
    printf-%q-quoted `name=value` lines meant to be `eval`'d in bash, so we let
    bash eval them and re-emit the raw values NUL-separated."""
    emit = (
        f'eval "$({shlex.quote(str(STAGE))} {shlex.quote(eval_id)} '
        f'{shlex.quote(str(target))})"; '
        'printf "%s\\0%s\\0%s\\0%s\\0" '
        '"$sandbox_repo" "$prompt" "$target" "$gh_env"'
    )
    out = subprocess.run(
        ["bash", "-c", emit], capture_output=True, text=True, check=True
    ).stdout
    sandbox_repo, prompt, fixture_target, gh_env, _ = out.split("\0")
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


def run_one(eval_id: str, run_dir: pathlib.Path, resolved: vendor.Resolved,
            timeout: int, cache, force: bool):
    eval_dir = run_dir / eval_id
    target = eval_dir / "sandbox"
    target.mkdir(parents=True, exist_ok=True)

    staged = stage(eval_id, target)
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
        )
        if not force:
            hit = cache.lookup(eval_id, key)
            if hit is not None:
                eval_cache.write_replay_artifacts(eval_dir, hit)
                verdict = "PASS" if hit["passed"] else "FAIL"
                print(f"  [eval-{eval_id}] CACHED {verdict} "
                      f"(graded {hit.get('graded_at', '?')}, "
                      f"model={hit.get('model', '?')}); skipped {resolved.config.label}, "
                      "--force to re-run\n", flush=True)
                return hit["passed"], True

    target_root = pathlib.Path(staged["target"])
    stub = " (stub gh)" if staged["gh_env"] else ""
    print(f"  [eval-{eval_id}] running {resolved.config.label} "
          f"(model={model_label}){stub} ...", flush=True)
    start = time.time()
    # The skills deploy into a scratch home beside, never inside, the repo
    # under review, so a review never sees a copied skill tree in its worktree.
    with micro_deploy.micro_deploy(
        resolved.vendor, ARTEFACTS, pathlib.Path(workdir), preflight=False
    ) as md:
        shim_deployed_scripts(md, target_root)
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
        integrity = micro_deploy.integrity_record(
            worker.read_paths, worker.out_of_set_paths
        )
    duration_s = time.time() - start

    response_path = eval_dir / "response.txt"
    response_path.write_text(stdout if isinstance(stdout, str) else stdout.decode())
    (eval_dir / "stderr.txt").write_text(
        stderr if isinstance(stderr, str) else stderr.decode())
    (eval_dir / "timing.json").write_text(json.dumps({
        "eval_id": eval_id,
        "duration_s": duration_s,
        "worker_rc": rc,
        "claude_rc": rc,
        "model": model_label,
        "artefacts_read_from_micro_deployment": integrity,
    }, indent=2))

    # Keep the call logs beside the response: they are half the evidence for
    # every publishing eval and the sandbox is discarded with the run directory.
    for log_name in ("gh_calls.log", "script_calls.log"):
        src_log = pathlib.Path(staged["target"]) / log_name
        if src_log.exists():
            (eval_dir / log_name).write_text(src_log.read_text())

    grade = subprocess.run(
        ["bash", str(GRADE), eval_id, workdir, str(response_path)],
        capture_output=True, text=True,
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
        print(f"  [eval-{eval_id}] FAIL, worker did not complete ({why}); "
              f"grade.sh ran on partial sandbox state and cannot be trusted "
              f"(grade alone would have said {'PASS' if grade_passed else 'FAIL'})\n",
              flush=True)
    elif not integrity["passed"]:
        print(f"  [eval-{eval_id}] FAIL, worker read artefacts outside the "
              f"micro-deployment: {integrity['out_of_set']}\n", flush=True)
    else:
        print(f"  [eval-{eval_id}] {'PASS' if passed else 'FAIL'} (worker rc={rc})\n",
              flush=True)

    # Cache only a conclusive verdict from a completed worker: a timeout or
    # crash is transient rather than a property of the inputs, so caching it
    # would replay a spurious verdict on a later clean run.
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
                        help="Eval ids to run (default: every id in evals.json)")
    vendor.add_vendor_arguments(parser)
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

    ids = args.ids if args.ids else default_ids()
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

    # Sequential on purpose: two review workers on one machine contend for the
    # model and both slow past the per-eval timeout.
    results = {i: run_one(i, run_dir, resolved, args.timeout, cache, args.force)
               for i in ids}

    ok = sum(1 for passed, _ in results.values() if passed)
    cached_n = sum(1 for _, was_cached in results.values() if was_cached)
    print("=" * 56)
    print(f"graded: {ok}/{len(results)} evals passed ({cached_n} from cache)")
    for i, (passed, was_cached) in results.items():
        print(f"  eval-{i}: {'PASS' if passed else 'FAIL'}"
              f"{' (cached)' if was_cached else ''}")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
