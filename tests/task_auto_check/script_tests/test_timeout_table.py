#!/usr/bin/env python3
"""Pin the RUNBOOK per-eval timeout table to the evals.json timeout keys.

`evals/run.py` reads a per-eval budget only from `evals.json`, so a RUNBOOK
row without the matching key documents a budget no run receives. Every table
row must carry the budget of that eval's `evals.json` key, and every key must
have a row. The mutation cases prove that a dropped key, a changed budget, an
extra row, and a duplicated row each read as a disagreement.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

HARNESS = pathlib.Path(__file__).resolve().parents[1]
RUNBOOK = HARNESS / "RUNBOOK.md"
EVALS = HARNESS / "evals" / "evals.json"
HEADING = "## Per-eval timeouts, and which evals need them"
ROW = re.compile(r"^\|\s*`([A-Za-z0-9_]+)`\s*\|\s*([0-9]+)s\s*\|")

FAILURES: list[str] = []


def check(label: str, ok: bool) -> None:
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")
    if not ok:
        FAILURES.append(label)


def table_rows(text: str) -> list[tuple[str, int]]:
    parts = text.split(HEADING, 1)
    if len(parts) < 2:
        return []
    section = re.split(r"(?m)^## ", parts[1], maxsplit=1)[0]
    return [
        (match.group(1), int(match.group(2)))
        for match in map(ROW.match, section.splitlines())
        if match
    ]


def eval_budgets(data: dict) -> dict[str, int]:
    return {
        entry["id"]: int(entry["timeout"])
        for entry in data["evals"]
        if "timeout" in entry
    }


def disagreements(rows: list[tuple[str, int]], budgets: dict[str, int]) -> list[str]:
    problems = []
    table: dict[str, int] = {}
    for eval_id, budget in rows:
        if eval_id in table:
            problems.append(f"{eval_id}: RUNBOOK lists it twice")
        table[eval_id] = budget
    for eval_id in sorted(set(table) | set(budgets)):
        if table.get(eval_id) != budgets.get(eval_id):
            problems.append(
                f"{eval_id}: RUNBOOK {table.get(eval_id)} vs evals.json "
                f"{budgets.get(eval_id)}"
            )
    return problems


def main() -> int:
    rows = table_rows(RUNBOOK.read_text(encoding="utf-8"))
    budgets = eval_budgets(json.loads(EVALS.read_text(encoding="utf-8")))
    check("RUNBOOK carries a per-eval timeout table", bool(rows))
    problems = disagreements(rows, budgets)
    for problem in problems:
        print(f"    {problem}")
    check("every RUNBOOK timeout row matches its evals.json key, and back", not problems)

    if rows and budgets:
        first = rows[0][0]
        dropped = {k: v for k, v in budgets.items() if k != first}
        check("a dropped evals.json key reads as a disagreement",
              bool(disagreements(rows, dropped)))
        changed = dict(budgets, **{first: budgets.get(first, 0) + 1})
        check("a changed budget reads as a disagreement",
              bool(disagreements(rows, changed)))
        check("an extra RUNBOOK row reads as a disagreement",
              bool(disagreements(rows + [("unlisted_eval", 3600)], budgets)))
        check("a duplicated RUNBOOK row reads as a disagreement",
              bool(disagreements(rows + [rows[0]], budgets)))

    print(f"timeout table checks: {len(FAILURES)} fail")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
