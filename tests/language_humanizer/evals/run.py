#!/usr/bin/env python3
"""Multi-pass runner for the language_humanizer behavioral evals.

Each of the three scenarios runs over a **fixed denominator** of passes
(default 5) and the recorded per-scenario pass rate over that denominator is
the deliverable. The bar is every assertion holding on every pass; a scenario
that misses it reports its measured rate and the diverging assertions rather
than being re-rolled for a better draw. There is deliberately no verdict
cache here — the repeated draws are the measurement, so replaying a stored
verdict would defeat it. `--passes` changes the denominator explicitly, and
the chosen denominator is recorded in the summary alongside the rates.

Passes run **concurrently** (`--workers`, default 5). Every pass owns its own
staged sandbox and writes only inside it, so the passes share nothing but the
model endpoint — which is what caps useful concurrency, not correctness. The
deep sequential-only rule in `tests/CLAUDE.md` covers multi-turn repair loops
that run for 15–25 minutes each; these passes are one worker call plus one
judge call, so they parallelize cleanly. Push `--workers` too high and the
passes contend for the model, which shows up as slower wall-clock per pass and
eventually as timeouts, not as wrong verdicts.

Per scenario × pass the runner:

1. Stages a fresh sandbox via `stage.sh <id> <target>`.
2. Spawns one pinned-sonnet `claude -p` worker with the sandbox as its cwd,
   telling it to load the skill and carry out the staged prompt, then to save
   the delivered document verbatim to `delivered.md`.
3. Grades the sandbox deterministically with `grade.py` (word counts, ledger
   items, bullet shape, harness integrity).
4. Grades the qualitative assertions with `judge.py` (one pinned-sonnet call).
5. Writes `response.txt` / `stderr.txt` / `timing.json` / `verdict.json` under
   `workspace/run-<ts>/<scenario>/pass-<n>/`.

Usage:
    python3 tests/language_humanizer/evals/run.py [scenario ...]
      [--passes 5] [--workers 5] [--model claude-sonnet-4-6] [--timeout 600]
      [--judge-model claude-sonnet-4-6] [--judge-timeout 300]
      [--claude-bin claude] [--skip-judge]
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import json
import pathlib
import shlex
import subprocess
import sys
import threading
import time

THIS = pathlib.Path(__file__).resolve().parent
HARNESS = THIS.parent
STAGE = THIS / "stage.sh"
GRADE = THIS / "grade.py"
WORKSPACE = HARNESS / "workspace"
RESULTS = HARNESS / "results"

sys.path.insert(0, str(THIS.parents[1] / "lib"))
from worker_auth import preflight_auth, worker_env  # noqa: E402  (shared; tests/ gitignored)

import judge as judge_mod  # noqa: E402  (sibling module in this harness)

SCENARIOS = ["fidelity_padded", "compression_trap", "write_path"]

# Passes run in a thread pool, so every line a job emits goes out under this
# lock as one block. Interleaved half-lines from concurrent passes would make
# the run log unreadable exactly when a failure needs reading.
PRINT_LOCK = threading.Lock()


def emit(*lines: str) -> None:
    with PRINT_LOCK:
        for line in lines:
            print(line, flush=True)

WORKER_PROMPT = """\
You are running an automated skill regression eval. Do exactly this:

1. Read the skill definition file in full: {skill_path}
2. Follow that skill's instructions exactly as written.
3. Carry out the user request below, operating only inside the current working
   directory ({workdir}). Leave every file that is already there unchanged.
4. Emit your full reply to the request in the response itself, exactly as the
   skill specifies.
5. REQUIRED, and the run is discarded without it: save the document you are
   delivering — only the document text itself, with none of the surrounding
   commentary, notes, findings, headers about the process, or metadata lines —
   verbatim to {workdir}/delivered.md. Write that file before you finish, even
   when you have already put the same text in your reply. When the mode you
   selected returns no document, write the single line NO_DELIVERED_TEXT to
   that file instead.

Before finishing, confirm {workdir}/delivered.md exists and holds the document
text. A reply without that file is an incomplete run.

The user request:

{prompt}
"""


def stage(scenario: str, target: pathlib.Path) -> dict:
    """Run stage.sh and read back the staged values (printf %q quoted, so let
    bash eval them and re-emit NUL-separated)."""
    emit = (
        f'eval "$({shlex.quote(str(STAGE))} {shlex.quote(scenario)} '
        f'{shlex.quote(str(target))})"; '
        'printf "%s\\0%s\\0%s\\0%s\\0%s\\0" '
        '"$sandbox_proj" "$source_file" "$skill_name" "$skill_path" "$prompt"'
    )
    out = subprocess.run(["bash", "-c", emit], capture_output=True, text=True,
                         check=True).stdout
    sandbox_proj, source_file, skill_name, skill_path, prompt, _ = out.split("\0")
    return {"sandbox_proj": sandbox_proj, "source_file": source_file,
            "skill_name": skill_name, "skill_path": skill_path, "prompt": prompt}


def run_pass(scenario: str, n: int, run_dir: pathlib.Path, args) -> dict:
    pass_dir = run_dir / scenario / f"pass-{n}"
    target = pass_dir / "sandbox"
    target.mkdir(parents=True, exist_ok=True)
    staged = stage(scenario, target)
    workdir = staged["sandbox_proj"]

    prompt = WORKER_PROMPT.format(skill_path=staged["skill_path"], workdir=workdir,
                                  prompt=staged["prompt"])
    cmd = [args.claude_bin, "-p", "--permission-mode", "bypassPermissions"]
    if args.model:
        cmd += ["--model", args.model]
    cmd.append(prompt)

    emit(f"  [{scenario} pass-{n}] running claude -p "
         f"(model={args.model or '<cli-default>'}) ...")
    start = time.time()
    try:
        res = subprocess.run(cmd, cwd=workdir, env=worker_env(), capture_output=True,
                             text=True, timeout=args.timeout)
        rc, stdout, stderr = res.returncode, res.stdout, res.stderr
    except subprocess.TimeoutExpired as e:
        rc, stdout = -1, (e.stdout or "")
        stderr = (e.stderr or "") + f"\n[TIMEOUT after {args.timeout}s]"
    duration = time.time() - start

    if isinstance(stdout, bytes):
        stdout = stdout.decode("utf-8", "replace")
    if isinstance(stderr, bytes):
        stderr = stderr.decode("utf-8", "replace")

    (pass_dir / "response.txt").write_text(stdout)
    (pass_dir / "stderr.txt").write_text(stderr)
    (pass_dir / "timing.json").write_text(json.dumps(
        {"scenario": scenario, "pass": n, "duration_s": duration, "claude_rc": rc,
         "model": args.model or "<cli-default>"}, indent=2))

    completed = rc == 0 and bool(stdout.strip())

    graded = subprocess.run(
        [sys.executable, str(GRADE), scenario, workdir, staged["source_file"], "--json"],
        capture_output=True, text=True)
    try:
        mech = json.loads(graded.stdout)
    except json.JSONDecodeError:
        mech = {"passed": False, "mechanical": {}, "integrity": {},
                "error": (graded.stderr or graded.stdout)[:400]}

    delivered_file = pathlib.Path(workdir) / "delivered.md"
    pristine = pathlib.Path(workdir).parent / ".fixture_pristine"
    if args.skip_judge or not completed:
        qual = {}
    else:
        qual = judge_mod.judge(
            scenario, pristine.read_text() if pristine.exists() else "",
            delivered_file.read_text() if delivered_file.exists() else "",
            stdout, args.claude_bin, args.judge_model, args.judge_timeout)

    assertions = {
        **{k: v["passed"] for k, v in mech.get("mechanical", {}).items()},
        **{k: v["passed"] for k, v in qual.items()},
    }
    integrity = {k: v["passed"] for k, v in mech.get("integrity", {}).items()}

    # A worker that answered but skipped the harness's save-to-delivered.md
    # step leaves nothing to measure, so every content assertion reads FAIL on
    # an empty file. That is a void measurement, not a skill result — the same
    # category as a timeout — and reporting it as thirteen content failures
    # would blame the skill for a harness miss and poison the per-assertion
    # rates. Mark it void, and record the assertions as not-measured.
    void = completed and not integrity.get("delivered_file_written", True)
    if void:
        assertions = {}
    passed = (completed and not void
              and all(assertions.values()) and all(integrity.values()))

    verdict = {
        "scenario": scenario, "pass": n, "passed": passed, "void": void,
        "void_reason": ("worker answered but never wrote delivered.md"
                        if void else None),
        "worker_completed": completed, "worker_rc": rc, "duration_s": duration,
        "delivered_words": mech.get("delivered_words"),
        "fixture_words": mech.get("fixture_words"),
        "assertions": assertions, "integrity": integrity,
        "mechanical_detail": mech.get("mechanical", {}),
        "judge_detail": qual,
    }
    (pass_dir / "verdict.json").write_text(json.dumps(verdict, indent=2))

    diverging = [k for k, ok in {**assertions, **integrity}.items() if not ok]
    if void:
        label, tail = "VOID", " — worker answered but never wrote delivered.md"
    else:
        label = "PASS" if passed else "FAIL"
        tail = "" if passed else (
            f" — diverging: {', '.join(diverging) or 'worker did not complete'}")
    emit(f"  [{scenario} pass-{n}] {label} "
         f"({mech.get('delivered_words')}w/{mech.get('fixture_words')}w, "
         f"{duration:.0f}s){tail}")
    return verdict


def summarize(results: dict, denominator: int) -> dict:
    summary = {"denominator": denominator, "scenarios": {}}
    for scenario, verdicts in results.items():
        clean = sum(1 for v in verdicts if v["passed"])
        voids = [v["pass"] for v in verdicts if v.get("void")]
        # Per-assertion rates count only the passes that were actually
        # measured, so a void pass neither credits nor penalises an assertion
        # it never got to see. The scenario's own denominator stays fixed.
        measured = [v for v in verdicts if not v.get("void")]
        names = sorted({k for v in measured for k in
                        list(v["assertions"]) + list(v["integrity"])})
        per_assertion = {}
        for name in names:
            hits = sum(1 for v in measured
                       if {**v["assertions"], **v["integrity"]}.get(name) is True)
            per_assertion[name] = f"{hits}/{len(measured)}"
        diverging = {n: r for n, r in per_assertion.items()
                     if r != f"{len(measured)}/{len(measured)}"}
        summary["scenarios"][scenario] = {
            "pass_rate": f"{clean}/{denominator}",
            "met_bar": clean == denominator,
            "void_passes": voids,
            "measured_passes": len(measured),
            "per_assertion": per_assertion,
            "diverging_assertions": diverging,
            "delivered_words": [v["delivered_words"] for v in verdicts],
            "fixture_words": next((v["fixture_words"] for v in verdicts
                                   if v.get("fixture_words")), None),
        }
    summary["all_scenarios_met_bar"] = all(
        s["met_bar"] for s in summary["scenarios"].values())
    return summary


def render(summary: dict) -> str:
    lines = [f"# language_humanizer eval run — denominator {summary['denominator']}", ""]
    for scenario, s in summary["scenarios"].items():
        lines.append(f"## {scenario} — {s['pass_rate']} "
                     f"({'met the bar' if s['met_bar'] else 'below the bar'})")
        lines.append("")
        lines.append(f"Delivered word counts per pass: {s['delivered_words']} "
                     f"(fixture: {s['fixture_words']})")
        lines.append("")
        if s.get("void_passes"):
            lines.append(
                f"Void passes (worker answered but never wrote delivered.md, so "
                f"nothing was measured): {s['void_passes']}. These count against "
                f"the fixed denominator and are excluded from the per-assertion "
                f"rates below, which run over {s['measured_passes']} measured "
                f"pass(es).")
            lines.append("")
        if s["diverging_assertions"]:
            lines.append("Diverging assertions:")
            lines.append("")
            for name, rate in s["diverging_assertions"].items():
                lines.append(f"- `{name}` — {rate}")
        else:
            lines.append("Every assertion held on every measured pass.")
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("scenarios", nargs="*", default=None)
    ap.add_argument("--passes", type=int, default=5,
                    help="Fixed denominator of passes per scenario (default 5).")
    ap.add_argument("--workers", type=int, default=5,
                    help="Passes run concurrently, up to this many (default 5). "
                         "Each pass owns its own sandbox; the shared model "
                         "endpoint is what caps useful concurrency.")
    ap.add_argument("--model", default="claude-sonnet-4-6",
                    help="Worker model for the skill under test.")
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--judge-model", default="claude-sonnet-4-6")
    ap.add_argument("--judge-timeout", type=int, default=300)
    ap.add_argument("--claude-bin", default="claude")
    ap.add_argument("--skip-judge", action="store_true",
                    help="Mechanical checks only — leaves the qualitative "
                         "assertions ungraded, so the run is diagnostic, not a "
                         "measurement of the bar.")
    args = ap.parse_args()

    scenarios = args.scenarios or SCENARIOS
    for s in scenarios:
        if s not in SCENARIOS:
            raise SystemExit(f"unknown scenario: {s} (known: {', '.join(SCENARIOS)})")

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{ts}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")
    print(f"Worker model: {args.model or '<cli-default>'}; "
          f"judge: {'off' if args.skip_judge else args.judge_model}")
    print(f"Scenarios: {scenarios}; passes per scenario: {args.passes}\n")

    preflight_auth(args.claude_bin, args.model)

    jobs = [(s, n) for s in scenarios for n in range(1, args.passes + 1)]
    workers = max(1, min(args.workers, len(jobs)))
    print(f"Running {len(jobs)} passes across {workers} concurrent worker(s)\n")

    wall_start = time.time()
    verdicts: dict[tuple[str, int], dict] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(run_pass, s, n, run_dir, args): (s, n) for s, n in jobs}
        for fut in concurrent.futures.as_completed(futures):
            scenario, n = futures[fut]
            try:
                verdicts[(scenario, n)] = fut.result()
            except Exception as exc:  # a harness fault, not a skill verdict
                emit(f"  [{scenario} pass-{n}] ERROR — harness fault: {exc!r}")
                verdicts[(scenario, n)] = {
                    "scenario": scenario, "pass": n, "passed": False,
                    "worker_completed": False, "harness_error": repr(exc),
                    "assertions": {}, "integrity": {"harness_ran": False},
                    "delivered_words": None, "fixture_words": None,
                }
    wall_s = time.time() - wall_start

    # Reassemble in submission order so the summary reads the same however the
    # pool happened to schedule the passes.
    results = {s: [verdicts[(s, n)] for n in range(1, args.passes + 1)]
               for s in scenarios}
    print(f"\nAll {len(jobs)} passes done in {wall_s / 60:.1f} min wall-clock "
          f"({workers} concurrent)\n")

    summary = summarize(results, args.passes)
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    report = render(summary)
    (run_dir / "summary.md").write_text(report)
    RESULTS.mkdir(parents=True, exist_ok=True)
    (RESULTS / f"run-{ts}.md").write_text(report)
    (RESULTS / f"run-{ts}.json").write_text(json.dumps(summary, indent=2))

    print("=" * 60)
    print(report)
    print(f"Recorded: {run_dir}/summary.json and {RESULTS}/run-{ts}.json")
    return 0 if summary["all_scenarios_met_bar"] else 1


if __name__ == "__main__":
    sys.exit(main())
