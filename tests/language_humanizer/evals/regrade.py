#!/usr/bin/env python3
"""Re-grade an existing run's captured responses without re-sampling the skill.

Spawning a fresh worker draws a new sample from a stochastic model, which is
the one thing a below-the-bar run must not do — a re-roll buries the result it
was supposed to report. Correcting a *grader* is different: the responses are
immutable once captured, so re-grading measures the same fifteen outputs with a
fixed instrument. This script does exactly that, walking a prior run directory,
re-running `grade.py` and (unless `--skip-judge`) `judge.py` over the artifacts
already on disk, and writing the corrected verdicts beside the originals.

Nothing is overwritten: each pass gains `verdict.regrade.json` next to its
original `verdict.json`, and the run gains `summary.regrade.{json,md}`. The
original measurement stays readable so the two can be compared and the
correction is auditable rather than a quiet edit of history.

Usage:
    python3 regrade.py <run_dir> [scenario ...]
      [--judge-model claude-sonnet-4-6] [--judge-timeout 300]
      [--workers 5] [--claude-bin claude] [--skip-judge]
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import pathlib
import subprocess
import sys

THIS = pathlib.Path(__file__).resolve().parent
GRADE = THIS / "grade.py"

sys.path.insert(0, str(THIS.parents[1] / "lib"))

import judge as judge_mod  # noqa: E402  (sibling module in this harness)
import run as run_mod  # noqa: E402  (reuse SCENARIOS, summarize, render, emit)


def regrade_pass(pass_dir: pathlib.Path, scenario: str, args) -> dict:
    sandbox = pass_dir / "sandbox"
    proj = sandbox / "proj"
    pristine = sandbox / ".fixture_pristine"
    delivered = proj / "delivered.md"
    response = pass_dir / "response.txt"
    sources = [p for p in (proj / "draft.md", proj / "notes.md") if p.exists()]
    n = int(pass_dir.name.split("-")[1])

    if not sources:
        run_mod.emit(f"  [{scenario} {pass_dir.name}] SKIP — no source document on disk")
        return {"scenario": scenario, "pass": n, "passed": False,
                "assertions": {}, "integrity": {"artifacts_present": False},
                "delivered_words": None, "fixture_words": None}

    graded = subprocess.run(
        [sys.executable, str(GRADE), scenario, str(proj), str(sources[0]), "--json"],
        capture_output=True, text=True)
    try:
        mech = json.loads(graded.stdout)
    except json.JSONDecodeError:
        mech = {"mechanical": {}, "integrity": {},
                "error": (graded.stderr or graded.stdout)[:400]}

    original = {}
    orig_path = pass_dir / "verdict.json"
    if orig_path.exists():
        original = json.loads(orig_path.read_text())

    if args.skip_judge:
        qual = original.get("judge_detail", {})
    else:
        qual = judge_mod.judge(
            scenario, pristine.read_text() if pristine.exists() else "",
            delivered.read_text() if delivered.exists() else "",
            response.read_text() if response.exists() else "",
            args.claude_bin, args.judge_model, args.judge_timeout)

    assertions = {
        **{k: v["passed"] for k, v in mech.get("mechanical", {}).items()},
        **{k: v["passed"] for k, v in qual.items()},
    }
    integrity = {k: v["passed"] for k, v in mech.get("integrity", {}).items()}
    # The worker's completion is a property of the original run, not of this
    # re-grade: a pass whose worker died has no output worth re-grading.
    completed = original.get("worker_completed", True)
    # Same void rule as run.py: a pass with no delivered.md was never measured,
    # so it stays void through a re-grade rather than being reported as a wall
    # of content failures against an empty file.
    void = completed and not integrity.get("delivered_file_written", True)
    if void:
        assertions = {}
    passed = (completed and not void
              and all(assertions.values()) and all(integrity.values()))

    verdict = {
        "scenario": scenario, "pass": n, "passed": passed, "void": void,
        "void_reason": ("worker answered but never wrote delivered.md"
                        if void else None),
        "regraded_from": str(orig_path),
        "original_passed": original.get("passed"),
        "worker_completed": completed,
        "delivered_words": mech.get("delivered_words"),
        "fixture_words": mech.get("fixture_words"),
        "assertions": assertions, "integrity": integrity,
        "mechanical_detail": mech.get("mechanical", {}),
        "judge_detail": qual,
    }
    (pass_dir / "verdict.regrade.json").write_text(json.dumps(verdict, indent=2))

    diverging = [k for k, ok in {**assertions, **integrity}.items() if not ok]
    was = original.get("passed")
    moved = "" if was is None or was == passed else f"  (was {'PASS' if was else 'FAIL'})"
    if void:
        run_mod.emit(f"  [{scenario} {pass_dir.name}] VOID{moved} — worker "
                     "answered but never wrote delivered.md")
    else:
        run_mod.emit(f"  [{scenario} {pass_dir.name}] {'PASS' if passed else 'FAIL'}"
                     f"{moved}"
                     f"{'' if passed else ' — diverging: ' + ', '.join(diverging)}")
    return verdict


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir")
    ap.add_argument("scenarios", nargs="*", default=None)
    ap.add_argument("--judge-model", default="claude-sonnet-4-6")
    ap.add_argument("--judge-timeout", type=int, default=300)
    ap.add_argument("--workers", type=int, default=5)
    ap.add_argument("--claude-bin", default="claude")
    ap.add_argument("--skip-judge", action="store_true",
                    help="Re-run only the deterministic grader and carry the "
                         "original judge verdicts forward unchanged.")
    args = ap.parse_args()

    run_dir = pathlib.Path(args.run_dir).resolve()
    if not run_dir.is_dir():
        raise SystemExit(f"not a run directory: {run_dir}")

    scenarios = args.scenarios or [s for s in run_mod.SCENARIOS if (run_dir / s).is_dir()]
    jobs: list[tuple[str, pathlib.Path]] = []
    for s in scenarios:
        jobs += [(s, p) for p in sorted((run_dir / s).glob("pass-*"),
                                        key=lambda q: int(q.name.split("-")[1]))]
    if not jobs:
        raise SystemExit(f"no passes found under {run_dir}")

    denominator = max(int(p.name.split("-")[1]) for _, p in jobs)
    workers = max(1, min(args.workers, len(jobs)))
    print(f"Re-grading {len(jobs)} captured passes from {run_dir}")
    print(f"Judge: {'carried forward' if args.skip_judge else args.judge_model}; "
          f"{workers} concurrent; no worker is re-run\n")

    verdicts: dict[tuple[str, int], dict] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(regrade_pass, p, s, args): (s, p) for s, p in jobs}
        for fut in concurrent.futures.as_completed(futures):
            s, p = futures[fut]
            n = int(p.name.split("-")[1])
            try:
                verdicts[(s, n)] = fut.result()
            except Exception as exc:
                run_mod.emit(f"  [{s} {p.name}] ERROR — harness fault: {exc!r}")
                verdicts[(s, n)] = {"scenario": s, "pass": n, "passed": False,
                                    "assertions": {}, "integrity": {"regrade_ran": False},
                                    "delivered_words": None, "fixture_words": None}

    results = {s: [verdicts[(s, n)] for n in range(1, denominator + 1)
                   if (s, n) in verdicts] for s in scenarios}
    summary = run_mod.summarize(results, denominator)
    summary["regrade_of"] = str(run_dir)
    summary["original_rates"] = {}
    for s, vs in results.items():
        was = sum(1 for v in vs if v.get("original_passed"))
        summary["original_rates"][s] = f"{was}/{denominator}"

    (run_dir / "summary.regrade.json").write_text(json.dumps(summary, indent=2))
    report = run_mod.render(summary)
    report += ("\n## As-run rates before the instrument fix\n\n"
               + "\n".join(f"- `{s}` — {r}" for s, r in summary["original_rates"].items())
               + "\n")
    (run_dir / "summary.regrade.md").write_text(report)
    run_mod.RESULTS.mkdir(parents=True, exist_ok=True)
    stem = f"{run_dir.name}-regrade"
    (run_mod.RESULTS / f"{stem}.md").write_text(report)
    (run_mod.RESULTS / f"{stem}.json").write_text(json.dumps(summary, indent=2))

    print("=" * 60)
    print(report)
    print(f"Recorded: {run_dir}/summary.regrade.json (original left intact)")
    return 0 if summary["all_scenarios_met_bar"] else 1


if __name__ == "__main__":
    sys.exit(main())
