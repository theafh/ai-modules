# executive_summary harness — initial recorded measurement

Recorded 2026-11-26 on the default vendor (Cursor `agent -p`, model `auto`),
`python3 tests/executive_summary/evals/run.py --workers 2`.

Run dir: `tests/executive_summary/workspace/run-20261126-232731` (gitignored).

| Eval | Verdict | Failing check |
| :--- | :--- | :--- |
| `policy_brief` | fail | word count 116 is 19.2% of 603 (window 8-17%) |
| `technical_report` | fail | word count 104 is 20.0% of 520 (window 8-17%); no 1-to-10 self-rating |

Both evals graded: prose-only, invented-term, and self-rating checks behaved
as expected (`policy_brief` passed the rating check, `technical_report` did
not). Grading failed on the length window, so the runner skipped the judge and
the judge's verdict is unverified in this record; the recorded failure is a
skill finding, not a harness defect — the skill's own `<length>` target is
10 to 15% of the input, and on both fixtures the default-vendor worker wrote
about 19-20%.

Per `TESTING.md` `## Test Integrity`, the harness is not adjusted to pass. The
finding belongs to `executive_summary`'s length adherence and is left on
record for the operator.
