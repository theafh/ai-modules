#!/usr/bin/env python3
"""Vendor-aware multi-pass runner for the language_humanizer behavioral evals.

Each of the three scenarios runs over a **fixed denominator** of passes
(default 5) and the recorded per-scenario pass rate over that denominator is
the deliverable. The bar is every assertion holding on every pass; a scenario
that misses it reports its measured rate and the diverging assertions rather
than being re-rolled for a better draw. There is deliberately no verdict
cache here, because the repeated draws are the measurement and replaying a
stored verdict would defeat it. `--passes` changes the denominator explicitly,
and the chosen denominator is recorded in the summary alongside the rates.

Every pass runs isolated from the host. Its sandbox root comes from
`tests/lib/worker_isolation.py`, which places it under the system temporary
directory, outside the home directory and outside any git repository, so no
host standing-instruction file reaches the worker. The worker also carries the
helper's arguments for the resolved vendor. The judge in `judge.py` runs the
same way from an isolated root of its own. The skill under test is
micro-deployed through the deploy script into a scratch home, path-read from
that deployed copy, never from the repository, and copied into the pass's
sandbox record afterwards.

Passes run **concurrently** (`--workers`, default
`vendor.DEFAULT_PARALLEL_WORKERS`). Every pass owns its own isolated sandbox
and writes only inside it, so the passes share nothing but the model endpoint,
which caps useful concurrency without touching correctness. The deep
sequential-only rule in `tests/CLAUDE.md` covers multi-turn repair loops that
run for 15 to 25 minutes each; these passes are one worker call plus one judge
call, so they parallelize cleanly. Push `--workers` too high and the passes
contend for the model, which shows up as slower wall-clock per pass and
eventually as timeouts rather than as wrong verdicts.

Per scenario and pass the runner:

1. Creates an isolated sandbox root and stages the fixture into it via
   `stage.sh <id> <root>`.
2. Micro-deploys `language_humanizer` for the staged project through the deploy
   script (scratch home, preflight off) and names the deployed `SKILL.md` path
   in the worker prompt. It then spawns one vendor-resolved print-mode worker
   with the staged project as its cwd and Cursor workspace, telling it to load
   the deployed skill and carry out the staged prompt, then to save the
   delivered document verbatim to `delivered.md`. The deployed `SKILL.md` is
   copied to `<root>/language_humanizer/SKILL.md` before the scratch home goes
   away, so the record keeps exactly what the pass measured.
3. Grades the staged project deterministically with `grade.py` (word counts,
   ledger items, bullet shape, harness integrity).
4. Grades the qualitative assertions with `judge.py` using the vendor-resolved
   judge policy: on Claude the default judge model inherits (`''`), while on
   Cursor it defaults to `auto`.
5. Writes `response.txt` / `stderr.txt` / `timing.json` / `verdict.json` under
   `workspace/run-<ts>/<scenario>/pass-<n>/`, copies the finished sandbox to
   `pass-<n>/sandbox/` so `regrade.py` can re-grade it later, and removes the
   temporary root.

The recorded measurement runs on `--vendor cursor`, per `TESTING.md`; the
Claude worker stays available for a Claude-pinned sample under the same
isolation contract.

Usage:
    python3 tests/language_humanizer/evals/run.py [scenario ...]
      [--passes 5] [--workers 4] [--vendor claude|cursor]
      [--model sonnet|auto|''] [--timeout 600]
      [--judge-model ''|auto|<override>] [--judge-timeout 300]
      [--worker-bin <bin>] [--skip-judge]
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import json
import pathlib
import shlex
import shutil
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
import micro_deploy  # noqa: E402  (shared micro-deployment helper in tests/lib)
import vendor  # noqa: E402  (shared vendor helper in tests/lib)
import worker_isolation  # noqa: E402  (shared helper in tests/lib)

import judge as judge_mod  # noqa: E402  (sibling module in this harness)

# Every isolated sandbox root this runner creates starts with this prefix, so a
# leftover root is easy to find under the system temporary directory.
ISOLATION_PREFIX = "lh_pass_"

ARTEFACTS = ["language_humanizer"]

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
   delivering verbatim to {workdir}/delivered.md. Save only the document text
   itself, with none of the surrounding commentary, notes, findings, headers
   about the process, or metadata lines. Write that file before you finish, even
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


def run_pass(scenario: str, n: int, run_dir: pathlib.Path,
             args, resolved: vendor.Resolved) -> dict:
    """Run one pass inside an isolated sandbox root, then keep a copy of it.

    The live sandbox sits under the system temporary directory, so neither the
    worker nor the judge runs inside the repository. Once the pass is graded,
    the finished sandbox is copied to `pass-<n>/sandbox/` for `regrade.py` and
    for reading, and the temporary root is removed whatever the outcome.
    """
    pass_dir = run_dir / scenario / f"pass-{n}"
    pass_dir.mkdir(parents=True, exist_ok=True)
    root = worker_isolation.create_sandbox_root(
        f"{ISOLATION_PREFIX}{scenario}_{n}_")
    try:
        return run_isolated_pass(scenario, n, pass_dir, root, args, resolved)
    finally:
        try:
            shutil.copytree(root, pass_dir / "sandbox", symlinks=True,
                            dirs_exist_ok=True)
        finally:
            shutil.rmtree(root, ignore_errors=True)


def run_isolated_pass(scenario: str, n: int, pass_dir: pathlib.Path,
                      root: pathlib.Path, args,
                      resolved: vendor.Resolved) -> dict:
    staged = stage(scenario, root)
    workdir = staged["sandbox_proj"]
    skill_src = pathlib.Path(staged["skill_path"])
    # Fail fast with a named cause when the checkout lacks the skill, rather
    # than letting the deploy script fail mid-pass.
    if not skill_src.is_file():
        raise FileNotFoundError(
            f"language_humanizer SKILL.md missing at {skill_src}; "
            "this harness needs a checkout that carries the ai_editorial plugin"
        )
    worker_model_label = resolved.worker_model or "<inherit>"

    emit(f"  [{scenario} pass-{n}] running {resolved.config.label} "
         f"(model={worker_model_label}) ...")
    start = time.time()
    # The skill lands in a scratch home that hides the host's deployed skills,
    # and the prompt names that deployed path. The project (not the root) is
    # the micro-deployment's sandbox, so the root keeps holding only the graded
    # project, the pristine fixture, and the skill record copied below.
    with micro_deploy.micro_deploy(
        resolved.vendor, ARTEFACTS, pathlib.Path(workdir), preflight=False
    ) as md:
        deployed_skill = md.path_map["language_humanizer"]
        prompt = WORKER_PROMPT.format(skill_path=deployed_skill,
                                      workdir=workdir, prompt=staged["prompt"])
        worker = micro_deploy.run_worker(
            vendor_name=resolved.vendor, bin_name=resolved.bin,
            model=resolved.worker_model, prompt=prompt, deploy=md,
            timeout=args.timeout, cwd=pathlib.Path(workdir),
            extra_args=worker_isolation.isolation_args(resolved.vendor),
        )
        rc, stdout, stderr = worker.returncode, worker.stdout, worker.stderr
        integrity_record = micro_deploy.integrity_record(
            worker.read_paths, worker.out_of_set_paths
        )
        # The scratch home goes away on exit; keep the measured SKILL.md in the
        # root so pass-<n>/sandbox/language_humanizer/SKILL.md records it.
        record_dir = root / "language_humanizer"
        record_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(deployed_skill, record_dir / "SKILL.md")
    duration = time.time() - start

    (pass_dir / "response.txt").write_text(stdout)
    (pass_dir / "stderr.txt").write_text(stderr)
    (pass_dir / "timing.json").write_text(json.dumps(
        {
            "scenario": scenario,
            "pass": n,
            "duration_s": duration,
            "worker_rc": rc,
            "claude_rc": rc,
            "model": worker_model_label,
            "artefacts_read_from_micro_deployment": integrity_record,
        },
        indent=2,
    ))

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
            stdout, resolved.vendor, resolved.bin, resolved.judge_model or "",
            args.judge_timeout,
        )

    assertions = {
        **{k: v["passed"] for k, v in mech.get("mechanical", {}).items()},
        **{k: v["passed"] for k, v in qual.items()},
    }
    integrity = {k: v["passed"] for k, v in mech.get("integrity", {}).items()}
    integrity["artefacts_read_from_micro_deployment"] = integrity_record["passed"]

    # A worker that answered but skipped the harness's save-to-delivered.md
    # step leaves nothing to measure, so every content assertion reads FAIL on
    # an empty file. That is a void measurement rather than a skill result, in
    # the same category as a timeout, and reporting it as content failures
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
        "artefacts_read_from_micro_deployment": integrity_record,
    }
    (pass_dir / "verdict.json").write_text(json.dumps(verdict, indent=2))

    diverging = [k for k, ok in {**assertions, **integrity}.items() if not ok]
    if void:
        label, tail = "VOID", ": worker answered but never wrote delivered.md"
    else:
        label = "PASS" if passed else "FAIL"
        tail = "" if passed else (
            f", diverging: {', '.join(diverging) or 'worker did not complete'}")
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
    lines = [f"# language_humanizer eval run, denominator {summary['denominator']}", ""]
    for scenario, s in summary["scenarios"].items():
        lines.append(f"## {scenario}: {s['pass_rate']} "
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
                lines.append(f"- `{name}`: {rate}")
        else:
            lines.append("Every assertion held on every measured pass.")
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("scenarios", nargs="*", default=None)
    ap.add_argument("--passes", type=int, default=5,
                    help="Fixed denominator of passes per scenario (default 5).")
    ap.add_argument(
        "--workers",
        type=int,
        default=vendor.DEFAULT_PARALLEL_WORKERS,
        help=(
            "Passes run concurrently, up to this many "
            f"(default: {vendor.DEFAULT_PARALLEL_WORKERS}). "
            "Each pass owns its own sandbox; the shared model "
            "endpoint is what caps useful concurrency."
        ),
    )
    vendor.add_vendor_arguments(ap, with_judge=True)
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--judge-timeout", type=int, default=300)
    ap.add_argument("--skip-judge", action="store_true",
                    help="Mechanical checks only. Leaves the qualitative "
                         "assertions ungraded, so the run is diagnostic, not a "
                         "measurement of the bar.")
    args = ap.parse_args()
    resolved = vendor.resolve(args, with_judge=True)
    worker_model_label = resolved.worker_model or "<inherit>"
    judge_model_label = (
        "off" if args.skip_judge else (resolved.judge_model or "<inherit>")
    )

    scenarios = args.scenarios or SCENARIOS
    for s in scenarios:
        if s not in SCENARIOS:
            raise SystemExit(f"unknown scenario: {s} (known: {', '.join(SCENARIOS)})")

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{ts}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")
    print(
        f"Worker vendor: {resolved.vendor}; command: {resolved.config.label}; "
        f"worker model: {worker_model_label}; judge: {judge_model_label}"
    )
    print(f"Scenarios: {scenarios}; passes per scenario: {args.passes}\n")

    # Workers run in the micro-deployment environment and the judge in the host
    # worker environment, so both logins are probed before the first pass.
    vendor.preflight_auth(resolved.vendor, resolved.bin, resolved.worker_model)
    micro_deploy.preflight_auth(resolved.vendor, resolved.bin, resolved.worker_model)

    jobs = [(s, n) for s in scenarios for n in range(1, args.passes + 1)]
    workers = max(1, min(args.workers, len(jobs)))
    print(f"Running {len(jobs)} passes across {workers} concurrent worker(s)\n")

    wall_start = time.time()
    verdicts: dict[tuple[str, int], dict] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {
            pool.submit(run_pass, s, n, run_dir, args, resolved): (s, n)
            for s, n in jobs
        }
        for fut in concurrent.futures.as_completed(futures):
            scenario, n = futures[fut]
            try:
                verdicts[(scenario, n)] = fut.result()
            except Exception as exc:  # a harness fault, not a skill verdict
                emit(f"  [{scenario} pass-{n}] ERROR, harness fault: {exc!r}")
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
