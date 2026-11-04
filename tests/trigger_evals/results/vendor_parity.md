# Trigger evals on Cursor: vendor parity run

This note records the live trigger-eval runs that prove the harness measures on
Cursor, the default vendor. It sits beside the per-run output directories under
`results/`, which stay gitignored; this note is committed and linted.

## Final run

| Field | Value |
| :--- | :--- |
| Eval set | `tests/trigger_evals/wiki.json` |
| Vendor | Cursor |
| CLI version | `2026.10.22-27dcf5f` |
| Worker model | `auto` |
| Date | 2026-11-04 |
| Run directory | `tests/trigger_evals/results/wiki/2026-11-04_144439` |
| Runs per query | 3 |
| Timeout | 45 s |
| Workers | `vendor.DEFAULT_PARALLEL_WORKERS` (4) |
| Baseline | none; no prior Cursor run existed on this machine |

### Results

- Precise: 19/20 queries passed.
- Family: 20/20 queries passed. A family pass means the first tool call loaded
  some skill from the family list.
- Summed precise triggers over the entries that expect `wiki`: 26.

One positive entry missed its precise target while staying in the family:
`audit my wiki for broken links and missing index entries` expects `wiki_fix`
and loaded `wiki` in all three runs. That is the known sibling description
bleed, and the detector measured it as a real load, so it is not a detection
fault.

The null entries, all passing:

| Query | Per-run load | Verdict |
| :--- | :--- | :--- |
| `i want a relational database for tracking these decisions, not a wiki` | `null`, `null`, `null` | pass |
| `format the python file in src/ingestion/loader.py — it's a mess` | `format_python` ×3 | pass (non-family load) |
| `summarize the attached paper into 2 paragraphs, executive-summary style` | `executive_summary` ×3 | pass (non-family load) |
| `lint my code and fix style issues` | `null`, `null`, `null` | pass |

No null entry failed, so no failing-null measured load needed recording.

## Drift and baseline

- Drift warning: none. Every copy under Cursor's skill roots matched the source
  description.
- Baseline comparison: none, because no prior Cursor run existed to pass as
  `--baseline`.

## Directory change across this run

Runs recorded before this change started each worker in the launching shell's
directory, usually the checkout, so a baseline comparison across this change
also measures the move to a fresh per-worker directory. That is why this run
carries no cross-change baseline comparison.

## Earlier runs

- `tests/trigger_evals/results/wiki/2026-11-04_143521` scored precise 20/20 and
  family 20/20 with a summed precise-trigger count of 27, on the same eval set,
  vendor, CLI, and model. It ran before a robustness fix that waits briefly
  after stdout EOF so a clean exit is not misread as a timeout; that fix does
  not change the detector for a tool-call query.
- A first attempt at 14:33 exited non-zero through the escape guard, naming
  `tasks/ai-dev_git-auto-review-round-report.md`. A concurrent process outside
  this harness changed that file during the run. The guard did its job; the
  tree was stable for the runs above.
