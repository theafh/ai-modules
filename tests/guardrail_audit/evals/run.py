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

Usage:
    python3 tests/guardrail_audit/evals/run.py [eval_id ...]
      [--vendor claude|cursor] [--model sonnet|auto|'']
      [--timeout 300] [--worker-bin <bin>]
      [--force] [--no-cache]
"""

from __future__ import annotations

import argparse
import datetime
import json
import pathlib
import subprocess
import sys
import time

THIS = pathlib.Path(__file__).resolve().parent
STAGE = THIS / "stage.sh"
GRADE = THIS / "grade.sh"
WORKSPACE = THIS / "workspace"

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import eval_cache  # noqa: E402
import micro_deploy  # noqa: E402
import vendor  # noqa: E402

ARTEFACTS = ["guardrail_audit", "guardrail"]

DEFAULT_IDS = [
    "presence_gate",
    "doc_vs_doc",
    "doc_vs_code",
    "direction_target",
    "missing_testing",
    "nature_mismatch",
]

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


def stage(eval_id: str, target: pathlib.Path) -> dict:
    out = subprocess.check_output(
        ["bash", str(STAGE), eval_id, str(target)],
        text=True,
    )
    env: dict[str, str] = {}
    for line in out.splitlines():
        if "=" not in line:
            continue
        key, raw = line.split("=", 1)
        env[key] = subprocess.check_output(
            ["bash", "-c", f"printf %s {raw}"], text=True
        ).rstrip("\n")
    return env


def worker_completed(rc: int, stdout: str) -> bool:
    return rc == 0 and bool(stdout.strip())


def run_one(eval_id: str, run_dir: pathlib.Path, resolved: vendor.Resolved,
            timeout: int, cache, force: bool):
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
                      f"(graded {hit.get('graded_at', '?')}, "
                      f"model={hit.get('model', '?')}) — skipped {resolved.config.label}; "
                      "--force to re-run\n", flush=True)
                return hit["passed"], True

    print(f"  [{eval_id}] running {resolved.config.label} "
          f"(model={model_label}) ...", flush=True)
    start = time.time()
    with micro_deploy.micro_deploy(
        resolved.vendor, ARTEFACTS, pathlib.Path(workdir), preflight=False
    ) as md:
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
        integrity = micro_deploy.integrity_record(
            worker.read_paths, worker.out_of_set_paths
        )
    duration_s = time.time() - start

    (eval_dir / "response.txt").write_text(stdout)
    (eval_dir / "stderr.txt").write_text(stderr)
    (eval_dir / "timing.json").write_text(json.dumps({
        "eval_id": eval_id,
        "duration_s": duration_s,
        "worker_rc": rc,
        "claude_rc": rc,
        "model": model_label,
        "artefacts_read_from_micro_deployment": integrity,
    }, indent=2))

    grade = subprocess.run(
        ["bash", str(GRADE), eval_id, workdir, str(eval_dir / "response.txt")],
        capture_output=True, text=True
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
        print(f"  [{eval_id}] FAIL — worker did not complete ({why})\n",
              flush=True)
    elif not integrity["passed"]:
        print(f"  [{eval_id}] FAIL — worker read artefacts outside the "
              f"micro-deployment: {integrity['out_of_set']}\n", flush=True)
    else:
        print(f"  [{eval_id}] {'PASS' if passed else 'FAIL'} (worker rc={rc})\n",
              flush=True)

    if cache is not None and completed and key is not None:
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
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--no-cache", action="store_true")
    args = parser.parse_args()

    ids = args.ids if args.ids else DEFAULT_IDS
    cache = None if args.no_cache else eval_cache.EvalCache(THIS / ".eval_cache")
    resolved = vendor.resolve(args)
    model_label = resolved.worker_model or "<inherit>"

    micro_deploy.preflight_auth(resolved.vendor, resolved.bin, resolved.worker_model)

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{ts}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")
    print(
        f"Worker vendor: {resolved.vendor}; command: {resolved.config.label}; "
        f"model: {model_label}"
    )

    failures = []
    for eval_id in ids:
        ok, _cached = run_one(
            eval_id, run_dir, resolved, args.timeout,
            cache, args.force,
        )
        if not ok:
            failures.append(eval_id)

    if failures:
        print("FAILED:", ", ".join(failures))
        return 1
    print("All evals passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
