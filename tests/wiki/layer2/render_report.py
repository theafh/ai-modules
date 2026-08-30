#!/usr/bin/env python3
"""Render a self-contained HTML report for a Layer 2 run.

Embeds prompts, responses, gradings, and benchmark data into one HTML file
so a human can step through every (scenario × pass) run, inspect what the
agent did, and see which assertions passed.

Run:
    python3 render_report.py <run_dir> [--open]
"""

from __future__ import annotations

import argparse
import html
import json
import pathlib
import sys
import webbrowser

THIS = pathlib.Path(__file__).resolve().parent


def safe_read(p: pathlib.Path) -> str:
    if not p.is_file():
        return ""
    try:
        return p.read_text()
    except UnicodeDecodeError:
        return p.read_bytes().decode(errors="replace")


def render(run_dir: pathlib.Path) -> str:
    benchmark_file = run_dir / "benchmark.json"
    if not benchmark_file.is_file():
        sys.exit(f"benchmark.json missing in {run_dir} — run aggregate.py first")
    bench = json.loads(benchmark_file.read_text())
    scenarios = bench["scenarios"]
    n_clean = sum(1 for s in scenarios if s["all_passes_clean"])

    # Per-scenario sections
    scenario_sections = []
    for s in scenarios:
        sid = s["scenario_id"]
        scen_dir = run_dir / sid

        pass_blocks = []
        for pass_info in s["per_pass"]:
            pname = pass_info["pass"]
            pdir = scen_dir / pname
            grading = json.loads((pdir / "grading.json").read_text()) if (pdir / "grading.json").is_file() else {}
            prompt = safe_read(pdir / "prompt.md")
            response = safe_read(pdir / "response.txt")
            report = safe_read(pdir / "report.md")
            timing = safe_read(pdir / "timing.json")

            assertions_html = "\n".join(
                f'<li class="assert {"ok" if e["passed"] else "fail"}">'
                f'<code>{html.escape(e["text"])}</code> — {html.escape(e["evidence"])}</li>'
                for e in grading.get("expectations", [])
            )

            pass_status = "PASS" if pass_info["passed"] else "FAIL"
            pass_class = "pass-ok" if pass_info["passed"] else "pass-fail"
            duration = pass_info.get("duration_ms")
            duration_s = f"{duration/1000:.1f}s" if duration else "—"
            tokens = pass_info.get("total_tokens") or "—"

            pass_blocks.append(f"""
<div class="pass-block {pass_class}">
  <h3>{html.escape(pname)} — <span class="status">{pass_status}</span> ({pass_info['pass_rate']:.0%})  ·  {duration_s}  ·  {tokens} tokens</h3>
  <details><summary>Assertions ({sum(1 for e in grading.get('expectations', []) if e['passed'])}/{len(grading.get('expectations', []))})</summary>
    <ul class="assertions">{assertions_html}</ul>
  </details>
  <details><summary>TEST REPORT</summary><pre>{html.escape(report or "(missing)")}</pre></details>
  <details><summary>Agent response</summary><pre>{html.escape(response[:50000] or "(empty)")}</pre></details>
  <details><summary>Prompt</summary><pre>{html.escape(prompt[:50000])}</pre></details>
  <details><summary>Timing</summary><pre>{html.escape(timing)}</pre></details>
</div>""")

        per_assertion_rows = "\n".join(
            f'<tr class="{"ok" if v["pass_rate"] == 1.0 else "fail"}"><td><code>{html.escape(name)}</code></td>'
            f'<td>{v["passes"]}/{v["total"]}</td><td>{v["pass_rate"]:.0%}</td></tr>'
            for name, v in s["per_assertion"].items()
        )

        clean_class = "scenario-ok" if s["all_passes_clean"] else "scenario-fail"
        scenario_sections.append(f"""
<section class="scenario {clean_class}">
  <h2>{html.escape(sid)} — {html.escape(s["scenario_name"])}</h2>
  <p class="meta">{s['n_passes']} passes · pass rate {s['pass_rate']['mean']:.0%} ± {s['pass_rate']['stddev']:.0%} · {s['duration_s']['mean']:.1f}s ± {s['duration_s']['stddev']:.1f}s</p>
  <details open><summary>Per-assertion pass rate</summary>
    <table class="assertion-table">
      <thead><tr><th>Assertion</th><th>Passes</th><th>Rate</th></tr></thead>
      <tbody>{per_assertion_rows}</tbody>
    </table>
  </details>
  {"".join(pass_blocks)}
</section>""")

    regressions_block = ""
    if bench.get("regressions"):
        regressions_html = "\n".join(f"<li>{html.escape(r)}</li>" for r in bench["regressions"])
        regressions_block = f'<div class="regressions"><h2>Regressions vs previous run</h2><ul>{regressions_html}</ul></div>'

    css = """
body { font-family: -apple-system, system-ui, sans-serif; max-width: 1200px; margin: 24px auto; padding: 0 16px; color: #222; }
header { border-bottom: 2px solid #ddd; padding-bottom: 8px; margin-bottom: 16px; }
h1 { margin: 0; font-size: 22px; }
h2 { font-size: 18px; margin-top: 16px; }
h3 { font-size: 15px; margin: 8px 0; }
.summary-cards { display: flex; gap: 16px; margin: 16px 0; }
.card { padding: 12px 16px; border-radius: 8px; background: #f6f8fa; border: 1px solid #d0d7de; flex: 1; }
.card.green { background: #ddf4dd; border-color: #6cbb6c; }
.card.red { background: #ffe0e0; border-color: #d04040; }
section.scenario { border: 1px solid #d0d7de; border-radius: 8px; padding: 12px 16px; margin: 16px 0; }
section.scenario.scenario-ok { border-left: 4px solid #2da44e; }
section.scenario.scenario-fail { border-left: 4px solid #cf222e; }
.meta { color: #57606a; font-size: 13px; margin: 4px 0 12px; }
.pass-block { border: 1px solid #d0d7de; border-radius: 6px; padding: 8px 12px; margin: 8px 0; background: #fafbfc; }
.pass-block.pass-ok { border-left: 3px solid #2da44e; }
.pass-block.pass-fail { border-left: 3px solid #cf222e; }
.pass-block .status { font-weight: bold; }
.pass-block.pass-ok .status { color: #2da44e; }
.pass-block.pass-fail .status { color: #cf222e; }
ul.assertions { list-style: none; padding-left: 0; }
li.assert { padding: 3px 8px; border-radius: 3px; margin: 2px 0; font-size: 13px; }
li.assert.ok { background: #e6ffec; }
li.assert.fail { background: #ffe0e0; font-weight: 500; }
table.assertion-table { border-collapse: collapse; width: 100%; font-size: 13px; }
table.assertion-table th, table.assertion-table td { padding: 4px 8px; border-bottom: 1px solid #eaecef; text-align: left; }
table.assertion-table tr.fail td { background: #ffe0e0; }
pre { background: #f6f8fa; padding: 8px 12px; border-radius: 4px; overflow-x: auto; font-size: 12px; max-height: 600px; }
details { margin: 4px 0; }
summary { cursor: pointer; user-select: none; font-size: 13px; color: #57606a; padding: 2px 0; }
.regressions { background: #fff5f5; border: 1px solid #cf222e; border-radius: 8px; padding: 12px 16px; margin: 16px 0; }
.regressions h2 { color: #cf222e; margin-top: 0; }
"""

    summary_class = "green" if n_clean == len(scenarios) and not bench.get("regressions") else "red"
    summary_text = f"{n_clean}/{len(scenarios)} scenarios clean across all passes"
    if bench.get("regressions"):
        summary_text += f" · {len(bench['regressions'])} regression(s)"

    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Wiki skill regression — {html.escape(bench['run_id'])}</title>
<style>{css}</style></head>
<body>
<header>
  <h1>Wiki skill regression — {html.escape(bench['run_id'])}</h1>
  <p class="meta">Skill: <code>{html.escape(bench['skill_name'])}</code> · {len(scenarios)} scenarios · 2 passes each</p>
</header>
<div class="summary-cards">
  <div class="card {summary_class}"><strong>{summary_text}</strong></div>
</div>
{regressions_block}
{"".join(scenario_sections)}
</body></html>
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_dir")
    parser.add_argument("--open", action="store_true", help="Open the report in the default browser")
    args = parser.parse_args()

    run_dir = pathlib.Path(args.run_dir).resolve()
    out = run_dir / "report.html"
    out.write_text(render(run_dir))
    print(f"Wrote {out}")
    if args.open:
        webbrowser.open(f"file://{out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
