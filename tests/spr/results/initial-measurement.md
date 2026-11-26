# spr harness — initial recorded measurement

Recorded 2026-11-26 on the default vendor (Cursor `agent -p`, model `auto`),
`python3 tests/spr/evals/run.py --workers 2`.

Run dir: `tests/spr/workspace/run-20261126-233632` (gitignored).

| Eval | Deterministic grade | Judge | Failing check |
| :--- | :--- | :--- | :--- |
| `priming_basics` | pass (15 bullets, 4 paragraphs) | fail | `non_overlap`: one bullet collapses two distinct claims |
| `memory_systems` | pass (19 bullets, 4 paragraphs) | fail | `non_overlap`: two bullets restate the same trade-off |

The deterministic grader passes both evals: bullet coverage, no numbered
list, no trailing punctuation, no out-of-scope term, and the final rating all
hold. The refute-biased judge fails both on non-overlap, a genuine skill
finding about bullet atomicity. Per `TESTING.md` `## Test Integrity`, the
grader is not relaxed to pass; the finding is recorded for the operator.
