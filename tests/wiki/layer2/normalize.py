#!/usr/bin/env python3
"""Normalize a Layer 2 run dir so every pass has a clean report.md.

For each <run_dir>/<scenario>/<pass>/:
  - If report.md is missing, extract the TEST REPORT block from response.txt.
  - Strip well-known harness-noise preambles from response.txt (e.g.,
    "The harness blocked the file write...") so the HTML viewer renders
    the agent's actual output cleanly.

The grader and renderer both treat report.md as the source of truth, so
this lets us recover from inconsistent agent file-Write behavior without
re-running the scenarios.

Run:
    python3 normalize.py <run_dir>
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

REPORT_RE = re.compile(
    r"(====\s*TEST REPORT\s*====.*?====\s*END REPORT\s*====)",
    re.DOTALL,
)

NOISE_PATTERNS = [
    re.compile(r"^The harness (?:blocks?|blocked) (?:the )?(?:file )?[Ww]rite[^\n]*\n+", re.MULTILINE),
    re.compile(r"^Report file written\.[^\n]*\n+", re.MULTILINE),
    re.compile(r"^The harness is blocking the file write,[^\n]*\n+", re.MULTILINE),
    re.compile(r"^I'll include the report block[^\n]*\n+", re.MULTILINE),
    re.compile(r"^Including the same TEST REPORT block[^\n]*\n+", re.MULTILINE),
    re.compile(r"^Note: the harness blocked[^\n]*\n*", re.MULTILINE),
    re.compile(r"^Note: The prompt mandated[^\n]*\n*", re.MULTILINE | re.DOTALL),
    # If a "Note:" paragraph at the very end mentions the harness, strip it
    re.compile(r"\n*Note:[^\n]*harness[^\n]*\n.*$", re.DOTALL),
]


def extract_report(text: str) -> str | None:
    m = REPORT_RE.search(text)
    return m.group(1) if m else None


def clean_response(text: str) -> str:
    out = text
    for pat in NOISE_PATTERNS:
        out = pat.sub("", out)
    return out.strip() + "\n"


def normalize_pass(pass_dir: pathlib.Path) -> dict:
    response = pass_dir / "response.txt"
    report = pass_dir / "report.md"
    result = {"pass_dir": str(pass_dir), "actions": []}

    if not response.is_file():
        result["actions"].append("no response.txt; skipping")
        return result

    text = response.read_text()

    # Extract report into report.md if missing or empty
    if not report.is_file() or not report.read_text().strip():
        block = extract_report(text)
        if block:
            report.write_text(block + "\n")
            result["actions"].append("wrote report.md from response.txt")
        else:
            result["actions"].append("no TEST REPORT block found in response.txt")

    # Clean up the response: strip harness-noise preambles
    cleaned = clean_response(text)
    if cleaned != text:
        response.write_text(cleaned)
        result["actions"].append("stripped harness-noise from response.txt")

    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_dir")
    args = parser.parse_args()

    run_dir = pathlib.Path(args.run_dir).resolve()
    # Match every scenario family the harness ships — L2-* (wiki), WI-* (wiki_import),
    # WU-* (wiki_wrapup). Sibling-skill scenarios live in the same workspace.
    pass_dirs = sorted(p for prefix in ("L2-*", "WI-*", "WU-*")
                       for p in run_dir.glob(f"{prefix}/pass-*"))
    print(f"Normalizing {len(pass_dirs)} pass dirs under {run_dir}\n")
    for pd in pass_dirs:
        r = normalize_pass(pd)
        for a in r["actions"]:
            print(f"  [{pd.parent.name}/{pd.name}] {a}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
