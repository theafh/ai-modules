#!/usr/bin/env bash
# Bundled-script unit tests for tests/trigger_evals/run.py.
#
# Hermetic: exercises the pure helpers with synthetic in-memory fixtures,
# so nothing here depends on recorded runs under results/ (gitignored) or
# on spawning a `claude` worker. Fast, deterministic, no LLM cost.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 - "$HERE/.." <<'PY'
import importlib.util, json, sys, tempfile
from pathlib import Path

run_dir = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("trun", run_dir / "run.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

fails = []
def check(cond, msg):
    print(("  ok   " if cond else "  FAIL ") + msg)
    if not cond: fails.append(msg)

def run_out(rows):
    """Build a minimal deployed-mode output dict from (query, expected, precise_n, runs) tuples."""
    results = [{"query": q, "expected_skill": e, "precise_triggers": p, "runs": n,
                "precise_pass": p / n >= 0.5} for q, e, p, n in rows]
    return {"mode": "deployed", "results": results}

def write_baseline(out):
    d = Path(tempfile.mkdtemp())
    (d / "results.json").write_text(json.dumps(out))
    return d

# --- baseline captures a passing state; current drops one query below threshold
base = run_out([("a", "task", 3, 3), ("b", "task_fix", 2, 3), ("c", "task_audit", 0, 3)])
cur  = run_out([("a", "task", 3, 3), ("b", "task_fix", 1, 3), ("c", "task_audit", 0, 3)])
bp = write_baseline(base)
cmp = m.compare_to_baseline(cur, bp)
check(len(cmp["regressions"]) == 1 and cmp["regressions"][0]["query"] == "b",
      "regression: a query crossing pass->fail is flagged")
check(cmp["regressions"][0]["baseline_precise"] == 2 and cmp["regressions"][0]["current_precise"] == 1,
      "regression: carries baseline and current trigger counts")

# --- a flip that stays above threshold is NOT a regression (noise discrimination)
base2 = run_out([("a", "task", 3, 3)])
cur2  = run_out([("a", "task", 2, 3)])
cmp2 = m.compare_to_baseline(cur2, write_baseline(base2))
check(not cmp2["regressions"], "no regression: 3/3 -> 2/3 stays passing, not flagged")

# --- recovery is reported as an improvement
base3 = run_out([("a", "task", 1, 3)])
cur3  = run_out([("a", "task", 2, 3)])
cmp3 = m.compare_to_baseline(cur3, write_baseline(base3))
check(len(cmp3["improvements"]) == 1, "improvement: a query crossing fail->pass is flagged")

# --- self-compare shows no movement
cmp4 = m.compare_to_baseline(base, bp)
check(not cmp4["regressions"] and not cmp4["improvements"], "self-compare: zero movement")

# --- a baseline given as the results.json file works like the directory form
cmp5 = m.compare_to_baseline(cur, bp / "results.json")
check(len(cmp5["regressions"]) == 1, "baseline path accepts the results.json file directly")

# --- differing cohorts compare on the shared queries without crashing
big = run_out([("a", "task", 3, 3), ("b", "task_fix", 3, 3), ("new", "task", 3, 3)])
cmp6 = m.compare_to_baseline(big, bp)
check(cmp6["shared_queries"] == 2 and cmp6["only_in_current"] == ["new"],
      "cohort mismatch: shared set computed, extra query reported not crashed")

# --- the pure function never mutates its input
before = json.dumps(cur, sort_keys=True)
m.compare_to_baseline(cur, bp)
check(json.dumps(cur, sort_keys=True) == before, "compare_to_baseline leaves current output unmutated")

print()
if fails:
    print(f"FAIL: {len(fails)} assertion(s) failed")
    sys.exit(1)
print("PASS: baseline regression detector")
PY
