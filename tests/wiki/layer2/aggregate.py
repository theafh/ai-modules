#!/usr/bin/env python3
"""Aggregate per-pass grading.json into a benchmark.json + benchmark.md.

Roll-ups per scenario:
    pass_rate (mean across passes)
    pass_rate_stddev
    duration_s (mean / stddev)
    total_tokens (mean / stddev)
    per-assertion pass rate (1.0 = always pass, 0.0 = always fail)

Compares to a previous benchmark.json (regression detection) when given.

Run:
    python3 aggregate.py <run_dir> [--previous <previous_benchmark.json>]
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import statistics
import sys


def load_pass(pass_dir: pathlib.Path) -> dict:
    grading_file = pass_dir / "grading.json"
    timing_file = pass_dir / "timing.json"

    grading = json.loads(grading_file.read_text()) if grading_file.is_file() else {}
    timing = json.loads(timing_file.read_text()) if timing_file.is_file() else {}
    return {"grading": grading, "timing": timing}


def stats(values: list[float]) -> dict:
    if not values:
        return {"mean": None, "stddev": None, "min": None, "max": None, "n": 0}
    if len(values) == 1:
        return {"mean": values[0], "stddev": 0.0, "min": values[0], "max": values[0], "n": 1}
    return {
        "mean": statistics.mean(values),
        "stddev": statistics.stdev(values),
        "min": min(values),
        "max": max(values),
        "n": len(values),
    }


def aggregate_scenario(scen_dir: pathlib.Path, scenario_id: str, scenario_name: str) -> dict:
    passes = []
    for pd in sorted(scen_dir.glob("pass-*")):
        passes.append((pd.name, load_pass(pd)))

    pass_rates = [p[1]["grading"].get("pass_rate", 0.0) for p in passes]
    durations = [p[1]["timing"].get("duration_ms", 0) / 1000 for p in passes if p[1]["timing"]]
    tokens = [t for p in passes if p[1]["timing"]
              for t in [p[1]["timing"].get("total_tokens")] if t is not None]

    # per-assertion pass rate
    assertion_results: dict[str, list[bool]] = {}
    for _, p in passes:
        for exp in p["grading"].get("expectations", []):
            assertion_results.setdefault(exp["text"], []).append(exp["passed"])
    per_assertion = {
        name: {
            "pass_rate": sum(results) / len(results),
            "passes": sum(results),
            "total": len(results),
        }
        for name, results in assertion_results.items()
    }

    return {
        "scenario_id": scenario_id,
        "scenario_name": scenario_name,
        "n_passes": len(passes),
        "pass_rate": stats(pass_rates),
        "duration_s": stats(durations),
        "total_tokens": stats(tokens),
        "per_pass": [
            {
                "pass": name,
                "pass_rate": p["grading"].get("pass_rate", 0.0),
                "passed": p["grading"].get("passed", False),
                "remediation_mechanism": p["grading"].get("remediation_mechanism"),
                "duration_ms": p["timing"].get("duration_ms"),
                "total_tokens": p["timing"].get("total_tokens"),
            }
            for name, p in passes
        ],
        "per_assertion": per_assertion,
        "all_passes_clean": all(p[1]["grading"].get("passed", False) for p in passes),
    }


def build_markdown(benchmark: dict, regressions: list[str]) -> str:
    lines = []
    lines.append(f"# Wiki skill regression benchmark — {benchmark['run_id']}")
    lines.append("")
    baseline = benchmark.get("baseline")
    if baseline:
        lines.append(
            f"Baseline: {baseline['run_id']} — "
            f"{baseline['n_scenarios']} scenario(s): "
            f"{', '.join(baseline['scenario_ids']) or '(none)'}"
        )
        if baseline.get("narrowed"):
            lines.append("")
            lines.append(
                "!! COMPARE WARNING: the baseline does not cover every "
                "scenario in this run; not covered by the baseline: "
                f"{', '.join(baseline['uncovered_scenario_ids'])}"
            )
        lines.append("")
    lines.append(f"Total scenarios: {len(benchmark['scenarios'])}")
    clean = sum(1 for s in benchmark["scenarios"] if s["all_passes_clean"])
    lines.append(f"All-passes clean: {clean}/{len(benchmark['scenarios'])}")
    lines.append("")
    if regressions:
        lines.append(f"## Regressions vs. previous run")
        lines.append("")
        for r in regressions:
            lines.append(f"- {r}")
        lines.append("")

    lines.append("## Per-scenario summary")
    lines.append("")
    lines.append("| Scenario | Passes | Pass rate (mean ± sd) | Duration (s) | Tokens |")
    lines.append("| --- | --- | --- | --- | --- |")
    for s in benchmark["scenarios"]:
        pr = s["pass_rate"]
        d = s["duration_s"]
        t = s["total_tokens"]

        def fmt(stat, fmt_spec):
            if stat["mean"] is None:
                return "—"
            return f"{stat['mean']:{fmt_spec}} ± {stat['stddev']:{fmt_spec}}"

        lines.append(
            f"| {s['scenario_id']} {s['scenario_name']} | {s['n_passes']} | "
            f"{fmt(pr, '.1%')} | {fmt(d, '.1f')} | {fmt(t, '.0f')} |"
        )

    mechanism_rows = [
        (s["scenario_id"], p["pass"], p.get("remediation_mechanism"), p["pass_rate"])
        for s in benchmark["scenarios"]
        for p in s["per_pass"]
        if p.get("remediation_mechanism") is not None
    ]
    if mechanism_rows:
        lines.append("")
        lines.append("## Remediation mechanism per pass")
        lines.append("")
        lines.append("| Scenario | Pass | Mechanism | Pass rate |")
        lines.append("| --- | --- | --- | --- |")
        for sid, pass_name, mechanism, rate in mechanism_rows:
            lines.append(f"| {sid} | {pass_name} | {mechanism} | {rate:.1%} |")

    lines.append("")
    lines.append("## Per-assertion pass rate (across all passes)")
    lines.append("")
    for s in benchmark["scenarios"]:
        lines.append(f"### {s['scenario_id']}")
        lines.append("")
        for name, stats_ in s["per_assertion"].items():
            mark = "ok" if stats_["pass_rate"] == 1.0 else "MISS"
            lines.append(f"- [{mark}] {name} — {stats_['passes']}/{stats_['total']}")
        lines.append("")
    return "\n".join(lines)


def detect_regressions(curr: dict, prev: dict) -> list[str]:
    regressions = []
    prev_by_id = {s["scenario_id"]: s for s in prev.get("scenarios", [])}
    for s in curr["scenarios"]:
        sid = s["scenario_id"]
        ps = prev_by_id.get(sid)
        if not ps:
            continue
        # Per-assertion regressions: assertion was 100% before and dropped now.
        for name, curr_stats in s["per_assertion"].items():
            prev_stats = ps.get("per_assertion", {}).get(name)
            if not prev_stats:
                continue
            if prev_stats["pass_rate"] == 1.0 and curr_stats["pass_rate"] < 1.0:
                regressions.append(
                    f"{sid} :: {name} — was {prev_stats['passes']}/{prev_stats['total']} "
                    f"(100%), now {curr_stats['passes']}/{curr_stats['total']} "
                    f"({curr_stats['pass_rate']:.0%})"
                )
        # Scenario-level: was clean, no longer clean.
        if ps.get("all_passes_clean") and not s["all_passes_clean"]:
            regressions.append(
                f"{sid} :: scenario was 100% clean across passes, now has at least one fail"
            )
    return regressions


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_dir")
    parser.add_argument("--previous", help="Path to previous benchmark.json (optional)")
    args = parser.parse_args()

    run_dir = pathlib.Path(args.run_dir).resolve()
    evals_path = pathlib.Path(__file__).resolve().parent / "evals.json"
    evals = json.loads(evals_path.read_text())

    evals_by_id = {e["id"]: e for e in evals["evals"]}
    scenarios = []
    for path in sorted(run_dir.iterdir()):
        spec = evals_by_id.get(path.name)
        if spec is None or not path.is_dir():
            continue
        scenarios.append(aggregate_scenario(path, spec["id"], spec["name"]))

    benchmark = {
        "run_id": run_dir.name,
        "skill_name": evals["skill_name"],
        "n_scenarios": len(scenarios),
        "scenarios": scenarios,
    }

    regressions = []
    if args.previous:
        prev_path = pathlib.Path(args.previous)
        if prev_path.is_file():
            previous = json.loads(prev_path.read_text())
            regressions = detect_regressions(benchmark, previous)

            baseline_ids = [
                s["scenario_id"] for s in previous.get("scenarios", [])
            ]
            current_ids = [s["scenario_id"] for s in scenarios]
            baseline_run_id = (
                previous.get("run_id")
                or prev_path.parent.name
                or prev_path.name
            )
            uncovered = [
                sid for sid in current_ids if sid not in set(baseline_ids)
            ]
            narrowed = bool(uncovered)
            benchmark["baseline"] = {
                "run_id": baseline_run_id,
                "n_scenarios": len(baseline_ids),
                "scenario_ids": baseline_ids,
                "narrowed": narrowed,
                "uncovered_scenario_ids": uncovered,
            }

            print(
                f"Baseline: {baseline_run_id} — {len(baseline_ids)} "
                f"scenario(s): {', '.join(baseline_ids) or '(none)'}"
            )
            if narrowed:
                print(
                    "!! COMPARE WARNING: baseline covered "
                    f"{len(baseline_ids)} scenario(s) but the current run "
                    f"covers {len(current_ids)}; not covered by the baseline: "
                    f"{', '.join(uncovered) or '(none)'}. This comparison is "
                    "narrowed. Exit status still reflects assertion/scenario "
                    "regressions only."
                )
    benchmark["regressions"] = regressions

    (run_dir / "benchmark.json").write_text(json.dumps(benchmark, indent=2))
    (run_dir / "benchmark.md").write_text(build_markdown(benchmark, regressions))
    print(f"Wrote {run_dir}/benchmark.json")
    print(f"Wrote {run_dir}/benchmark.md")
    if regressions:
        print(f"\n!! REGRESSIONS DETECTED ({len(regressions)}):")
        for r in regressions:
            print(f"  - {r}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
