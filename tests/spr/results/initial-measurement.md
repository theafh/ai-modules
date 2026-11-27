# spr harness — recorded measurement

Recorded 2026-11-27 on the default vendor (Cursor `agent -p`, model `auto`),
`python3 tests/spr/evals/run.py --workers 2 --force`, after the rating check
was tightened and the runner gained the read-check gate.

Run dir: `tests/spr/workspace/run-20261127-010941` (gitignored).

| Eval | Deterministic grade | Judge | Failing check |
| :--- | :--- | :--- | :--- |
| `priming_basics` | pass (12 bullets, 4 paragraphs) | fail | `non_overlap`: one bullet collapses two distinct concepts |
| `memory_systems` | pass (16 bullets, 4 paragraphs) | fail | `non_overlap`: two bullets restate the same trade-off |

The deterministic grader passes both evals: bullet coverage, no numbered
list, no trailing punctuation, no out-of-scope term, and a final
`Reconstructability: 9` rating all hold. The refute-biased judge passes
`reconstructability` and fails `non_overlap` on both, a genuine skill finding
about bullet atomicity. Per `TESTING.md` `## Test Integrity`, the grader is
not relaxed to pass; the finding is recorded for the operator.
