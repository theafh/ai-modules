#!/usr/bin/env python3
"""Standalone Layer 2 re-runner — fires `claude -p` per (scenario × pass).

This is the regression-test entrypoint for the wiki skill. Each invocation:

1. Restages all sandboxes via setup_scenarios.sh (one full pass).
2. Submits one worker per scenario to a ThreadPoolExecutor (default 4 workers).
   Inside each worker, passes run sequentially:
     - Build the prompt via build_prompt.py.
     - Run `claude -p --permission-mode bypassPermissions <prompt>`;
       capture stdout/stderr/timing into the pass dir.
     - Between passes within the same scenario, restage just that one
       sandbox so pass-2 starts from the same initial state as pass-1.
3. Runs grade.py and aggregate.py.
4. Compares to the most recent prior benchmark.json (if any) and reports
   regressions.

Sandbox isolation guarantees concurrent scenarios cannot collide: each scenario
has its own dir under tests/wiki/layer2/<sid>/ and each pass writes to its own
workspace/run-<ts>/<sid>/pass-N/ dir.

Layout:
    workspace/run-<ts>/
        L2-1/pass-1/{prompt.md, response.txt, report.md, timing.json, grading.json}
        L2-1/pass-2/...
        ...
        benchmark.json
        benchmark.md
        grading_summary.json

Use `--passes N` to override the default from evals.json. Use `--scenario L2-1`
to run a single scenario (useful when iterating on a specific failure).
Use `--workers N` to tune parallelism (default 4).
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time

THIS = pathlib.Path(__file__).resolve().parent
WIKI_TESTS = THIS.parent
EVALS_PATH = THIS / "evals.json"
SETUP_SCRIPT = THIS / "setup_scenarios.sh"
BUILD_PROMPT = THIS / "build_prompt.py"
NORMALIZE = THIS / "normalize.py"
GRADE = THIS / "grade.py"
AGGREGATE = THIS / "aggregate.py"
WORKSPACE = THIS / "workspace"

sys.path.insert(0, str(WIKI_TESTS.parent / "lib"))
from worker_auth import worker_env  # noqa: E402  (shared; tests/ is gitignored)


def latest_previous_benchmark() -> pathlib.Path | None:
    if not WORKSPACE.is_dir():
        return None
    candidates = sorted(WORKSPACE.glob("run-*/benchmark.json"))
    return candidates[-1] if candidates else None


def restage_one(scenario_id: str) -> None:
    """Restage a single scenario's sandbox. Safe to call concurrently from
    different worker threads only when each call targets a distinct scenario id.
    Within one scenario, callers must serialize this with that scenario's
    in-flight claude -p subprocess."""
    subprocess.run(
        [str(SETUP_SCRIPT), scenario_id],
        check=True, stdout=subprocess.DEVNULL,
    )


def run_pass(scenario: dict, pass_num: int, run_dir: pathlib.Path,
             claude_bin: str, timeout: int, model: str | None) -> dict:
    sid = scenario["id"]
    sandbox_root = THIS / scenario["sandbox_path"]
    pass_dir = run_dir / sid / f"pass-{pass_num}"
    pass_dir.mkdir(parents=True, exist_ok=True)

    report_path = pass_dir / "report.md"
    prompt_path = pass_dir / "prompt.md"

    # Build prompt
    prompt = subprocess.run(
        [
            sys.executable, str(BUILD_PROMPT),
            sid, str(pass_num),
            "--report-path", str(report_path),
            "--sandbox-root", str(sandbox_root),
        ],
        capture_output=True, text=True, check=True,
    ).stdout
    prompt_path.write_text(prompt)

    print(f"  [{sid} pass-{pass_num}] running claude -p ...", flush=True)
    cmd = [claude_bin, "-p", "--permission-mode", "bypassPermissions"]
    if model:
        cmd += ["--model", model]
    cmd.append(prompt)
    start = time.time()
    try:
        result = subprocess.run(
            cmd, env=worker_env(), capture_output=True, text=True, timeout=timeout,
        )
        rc = result.returncode
        stdout = result.stdout
        stderr = result.stderr
    except subprocess.TimeoutExpired as e:
        rc = -1
        stdout = e.stdout or ""
        stderr = (e.stderr or "") + f"\n[TIMEOUT after {timeout}s]"
    duration_s = time.time() - start

    (pass_dir / "response.txt").write_text(stdout)
    (pass_dir / "stderr.txt").write_text(stderr)

    # If the agent didn't Write report.md, fall back to extracting from response.
    if not report_path.is_file():
        report_path.write_text(stdout)

    # `claude -p` doesn't expose token counts via the CLI; only duration.
    timing = {
        "duration_s": duration_s,
        "duration_ms": int(duration_s * 1000),
        "claude_rc": rc,
        "total_tokens": None,
        "model": model or "<cli-default>",
    }
    (pass_dir / "timing.json").write_text(json.dumps(timing, indent=2))

    # Snapshot the sandbox as this pass left it. Sandboxes are restaged between
    # passes, so without a per-pass copy every filesystem assertion grades
    # against whatever the LAST pass left behind — each pass reads an identical
    # verdict and per-pass state is unrecoverable. grade.py prefers this
    # snapshot and falls back to the live sandbox when it is absent.
    snapshot = pass_dir / "sandbox-snapshot"
    if snapshot.exists():
        shutil.rmtree(snapshot)
    shutil.copytree(sandbox_root, snapshot, symlinks=True)

    return timing


def run_scenario(s: dict, passes: int, run_dir: pathlib.Path,
                 claude_bin: str, timeout: int, model: str | None) -> None:
    """Run all passes of a single scenario sequentially. Between passes,
    restage just this scenario's sandbox so pass-2 sees the same initial
    state as pass-1."""
    sid = s["id"]
    for p in range(1, passes + 1):
        if p > 1:
            restage_one(sid)
        run_pass(s, p, run_dir, claude_bin, timeout, model)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--passes", type=int, default=None,
                        help="Override the number of passes per scenario")
    parser.add_argument("--scenario",
                        help="Run only these scenario ids — one id or a "
                             "comma-separated list (e.g. L2-1 or AS-13,AS-14). "
                             "A subset run keeps one run dir and one grading "
                             "pass, so a targeted re-run after a skill change "
                             "still produces a single comparable benchmark.")
    parser.add_argument("--claude-bin", default="claude",
                        help="Path to the claude CLI binary (default: claude on PATH)")
    parser.add_argument("--model", default="claude-sonnet-4-6",
                        help="Model the worker `claude -p` subprocess runs as "
                             "(default: claude-sonnet-4-6). The skill under "
                             "test is pinned to sonnet; the meta-level "
                             "grade.py / aggregate.py layer is pure Python and "
                             "uses no model. Pass '' to inherit the CLI default.")
    parser.add_argument("--timeout", type=int, default=600,
                        help="Per-pass timeout in seconds (default: 600)")
    parser.add_argument("--workers", type=int, default=4,
                        help="Number of scenarios to run in parallel (default: 4). "
                             "Passes within one scenario stay sequential.")
    args = parser.parse_args()

    if shutil.which(args.claude_bin) is None:
        print(f"ERROR: '{args.claude_bin}' not found on PATH. Install the Claude CLI or pass --claude-bin.", file=sys.stderr)
        return 2

    evals = json.loads(EVALS_PATH.read_text())
    passes = args.passes if args.passes is not None else evals.get("passes", 2)
    wanted = {s.strip() for s in args.scenario.split(",") if s.strip()} if args.scenario else None
    scenarios = [e for e in evals["evals"] if wanted is None or e["id"] in wanted]
    if not scenarios:
        print(f"No scenarios match {args.scenario!r}", file=sys.stderr)
        return 2
    if wanted is not None:
        unknown = sorted(wanted - {e["id"] for e in evals["evals"]})
        if unknown:
            print(f"ERROR: unknown scenario id(s): {', '.join(unknown)}", file=sys.stderr)
            return 2

    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{timestamp}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")
    print(f"Worker model: {args.model or '<cli-default>'}")
    print(f"Scenarios: {[s['id'] for s in scenarios]}, passes per scenario: {passes}")

    # Initial full restage (covers all scenarios). After this, per-scenario
    # restages happen inline between passes inside each scenario worker.
    subprocess.run([str(SETUP_SCRIPT)], check=True)

    workers = max(1, min(args.workers, len(scenarios)))
    print(f"Running {len(scenarios)} scenario(s) with {workers} parallel worker(s)")
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {
            pool.submit(run_scenario, s, passes, run_dir,
                        args.claude_bin, args.timeout, args.model): s["id"]
            for s in scenarios
        }
        for fut in concurrent.futures.as_completed(futures):
            sid = futures[fut]
            try:
                fut.result()
            except Exception as e:
                print(f"  [{sid}] scenario failed: {e}", flush=True)

    # Normalize: extract report.md from response.txt where missing,
    # strip harness-noise from response.txt
    print("\nNormalizing ...")
    subprocess.run([sys.executable, str(NORMALIZE), str(run_dir)], check=False)

    # Grade
    print("\nGrading ...")
    subprocess.run([sys.executable, str(GRADE), str(run_dir)], check=True)

    # Aggregate (with optional regression compare)
    print("\nAggregating ...")
    prev = latest_previous_benchmark()
    cmd = [sys.executable, str(AGGREGATE), str(run_dir)]
    if prev:
        cmd += ["--previous", str(prev)]
        print(f"Comparing against {prev}")
    rc = subprocess.run(cmd).returncode

    # Render HTML report (best-effort)
    render = THIS / "render_report.py"
    if render.is_file():
        subprocess.run([sys.executable, str(render), str(run_dir)], check=False)

    print(f"\nDone. See:\n  {run_dir}/report.html\n  {run_dir}/benchmark.md\n  {run_dir}/grading_summary.json")
    return rc


if __name__ == "__main__":
    sys.exit(main())
