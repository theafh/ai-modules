#!/usr/bin/env python3
"""Re-grade an existing run's captured responses without re-sampling the skill.

Spawning a fresh worker draws a new sample from a stochastic model, which is
the one thing a below-the-bar run must not do, because a re-roll buries the
result it was supposed to report. Correcting a *grader* is different: the responses are
immutable once captured, so re-grading measures the same fifteen outputs with a
fixed instrument. This script does exactly that, walking a prior run directory,
re-running `grade.py` and (unless `--skip-judge`) `judge.py` over the artifacts
already on disk, and writing the corrected verdicts beside the originals.

Nothing is overwritten: each pass gains `verdict.regrade.json` next to its
original `verdict.json`, and the run gains `summary.regrade.{json,md}`. The
original measurement stays readable so the two can be compared and the
correction is auditable rather than a quiet edit of history.

Each re-grade record carries the original run's `vendor`, `worker_model`, and
`worker_effort`, because the captured responses are that worker's, and the
`judge_vendor`, `judge_model`, and `judge_effort` that produced its judge
verdicts. The comparison with the as-run rates isolates a grader fix only when
the judge is the one that produced the original verdicts, so a re-judged
re-grade on another judge vendor, model, or effort, or of a run whose judge is
unrecorded, writes its records without the comparison and exits 1 naming both
settings, the way the trigger-eval baseline check refuses a cross-setting
baseline. A `--skip-judge` re-grade carries the original judge verdicts and
their settings forward, so it keeps the comparison.

Usage:
    python3 regrade.py <run_dir> [scenario ...]
      [--vendor claude|cursor] [--judge-model opus|auto|'']
      [--judge-effort xhigh|<level>|''] [--judge-timeout 300] [--workers 4]
      [--worker-bin <bin>] [--skip-judge]
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
import vendor  # noqa: E402  (shared vendor helper in tests/lib)

import judge as judge_mod  # noqa: E402  (sibling module in this harness)
import run as run_mod  # noqa: E402  (reuse SCENARIOS, summarize, render, emit)


def original_settings(run_dir: pathlib.Path) -> dict:
    """Read the original run's summary.json, or nothing when it is unreadable."""

    try:
        data = json.loads((run_dir / "summary.json").read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def regrade_settings(original: dict, resolved: vendor.Resolved,
                     skip_judge: bool) -> dict:
    """Return the settings block every record of this re-grade carries.

    The worker fields come from the original run, because no worker re-runs.
    The judge fields name the judge behind the re-graded judge verdicts: the
    resolved judge when it re-runs, and the original's judge under
    --skip-judge, which carries the original verdicts forward. A field the
    original did not record reads as null.
    """

    record = {
        "vendor": original.get("vendor"),
        "worker_model": original.get("worker_model"),
        "worker_effort": original.get("worker_effort"),
    }
    if skip_judge:
        record.update({
            "judge_vendor": original.get("vendor"),
            "judge_model": original.get("judge_model"),
            "judge_effort": original.get("judge_effort"),
        })
    else:
        record.update({
            "judge_vendor": resolved.vendor,
            "judge_model": resolved.judge_model,
            "judge_effort": resolved.judge_effort,
        })
    return record


def judge_mismatch(original: dict, current: dict) -> str | None:
    """Name a judge vendor, model, or effort difference, or return None.

    Both sides normalize the way the trigger-eval baseline check does: a
    missing effort reads as the empty effort, and a missing vendor or judge
    model reads as `unknown`, which matches no judge, so a run recorded before
    its judge was recorded, or one that ran with --skip-judge, never compares
    against a re-judged re-grade.
    """

    def named(value: object) -> str:
        return "unknown" if value is None else str(value)

    base = (named(original.get("vendor")), named(original.get("judge_model")),
            str(original.get("judge_effort") or ""))
    cur = (named(current.get("judge_vendor")), named(current.get("judge_model")),
           str(current.get("judge_effort") or ""))
    if "unknown" not in base[:2] and base == cur:
        return None
    return (
        f"recorded with judge vendor {base[0]!r}, judge_model {base[1]!r}, and "
        f"judge_effort {base[2]!r}; this re-grade uses judge vendor {cur[0]!r}, "
        f"judge_model {cur[1]!r}, and judge_effort {cur[2]!r}"
    )


def regrade_pass(pass_dir: pathlib.Path, scenario: str, args) -> dict:
    sandbox = pass_dir / "sandbox"
    proj = sandbox / "proj"
    pristine = sandbox / ".fixture_pristine"
    delivered = proj / "delivered.md"
    response = pass_dir / "response.txt"
    sources = [p for p in (proj / "draft.md", proj / "notes.md") if p.exists()]
    n = int(pass_dir.name.split("-")[1])

    if not sources:
        run_mod.emit(f"  [{scenario} {pass_dir.name}] SKIP: no source document on disk")
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
            args.resolved.vendor, args.resolved.bin,
            args.resolved.judge_model or "", args.judge_timeout,
            effort=args.resolved.judge_effort or "",
        )

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
        **args.settings,
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
        run_mod.emit(f"  [{scenario} {pass_dir.name}] VOID{moved}: worker "
                     "answered but never wrote delivered.md")
    else:
        run_mod.emit(f"  [{scenario} {pass_dir.name}] {'PASS' if passed else 'FAIL'}"
                     f"{moved}"
                     f"{'' if passed else ', diverging: ' + ', '.join(diverging)}")
    return verdict


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir")
    ap.add_argument("scenarios", nargs="*", default=None)
    vendor.add_vendor_arguments(ap, with_judge=True)
    ap.add_argument("--judge-timeout", type=int, default=300)
    ap.add_argument(
        "--workers",
        type=int,
        default=vendor.DEFAULT_PARALLEL_WORKERS,
    )
    ap.add_argument("--skip-judge", action="store_true",
                    help="Re-run only the deterministic grader and carry the "
                         "original judge verdicts forward unchanged.")
    args = ap.parse_args()
    if args.model is not None or args.effort is not None:
        ap.error("regrade starts no worker, so it takes --judge-model and "
                 "--judge-effort in place of --model and --effort")
    args.resolved = vendor.resolve(args, with_judge=True)

    run_dir = pathlib.Path(args.run_dir).resolve()
    if not run_dir.is_dir():
        raise SystemExit(f"not a run directory: {run_dir}")
    original = original_settings(run_dir)
    args.settings = regrade_settings(original, args.resolved, args.skip_judge)
    mismatch = None
    if not args.skip_judge:
        detail = judge_mismatch(original, args.settings)
        if detail is not None:
            mismatch = (
                f"original judge mismatch: run {run_dir} was {detail}. "
                "Comparison with the as-run rates skipped."
            )

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
    judge_model_label = (
        "carried forward"
        if args.skip_judge
        else (
            f"{args.resolved.judge_model or '<inherit>'} "
            f"at effort {args.resolved.judge_effort or '<inherit>'}"
        )
    )
    print(
        f"Judge vendor: {args.resolved.vendor}; command: {args.resolved.config.label}; "
        f"judge model: {judge_model_label}; {workers} concurrent; no worker is re-run\n"
    )

    verdicts: dict[tuple[str, int], dict] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(regrade_pass, p, s, args): (s, p) for s, p in jobs}
        for fut in concurrent.futures.as_completed(futures):
            s, p = futures[fut]
            n = int(p.name.split("-")[1])
            try:
                verdicts[(s, n)] = fut.result()
            except Exception as exc:
                run_mod.emit(f"  [{s} {p.name}] ERROR, harness fault: {exc!r}")
                verdicts[(s, n)] = {"scenario": s, "pass": n, "passed": False,
                                    "assertions": {}, "integrity": {"regrade_ran": False},
                                    "delivered_words": None, "fixture_words": None}

    results = {s: [verdicts[(s, n)] for n in range(1, denominator + 1)
                   if (s, n) in verdicts] for s in scenarios}
    summary = run_mod.summarize(results, denominator, args.settings)
    summary["regrade_of"] = str(run_dir)
    if mismatch is None:
        summary["original_rates"] = {}
        for s, vs in results.items():
            was = sum(1 for v in vs if v.get("original_passed"))
            summary["original_rates"][s] = f"{was}/{denominator}"
    else:
        summary["original_mismatch"] = mismatch

    (run_dir / "summary.regrade.json").write_text(json.dumps(summary, indent=2))
    report = run_mod.render(summary)
    if mismatch is None:
        report += ("\n## As-run rates before the instrument fix\n\n"
                   + "\n".join(f"- `{s}`: {r}"
                               for s, r in summary["original_rates"].items())
                   + "\n")
    else:
        report += f"\n## As-run comparison refused\n\n{mismatch}\n"
    (run_dir / "summary.regrade.md").write_text(report)
    run_mod.RESULTS.mkdir(parents=True, exist_ok=True)
    stem = f"{run_dir.name}-regrade"
    (run_mod.RESULTS / f"{stem}.md").write_text(report)
    (run_mod.RESULTS / f"{stem}.json").write_text(json.dumps(summary, indent=2))

    print("=" * 60)
    print(report)
    print(f"Recorded: {run_dir}/summary.regrade.json (original left intact)")
    if mismatch is not None:
        print(f"WARNING: {mismatch}", file=sys.stderr)
        return 1
    return 0 if summary["all_scenarios_met_bar"] else 1


if __name__ == "__main__":
    sys.exit(main())
