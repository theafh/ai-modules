# language_humanizer measurement summary

The shipped skill misses the bar on all three scenarios: `fidelity_padded`
1/5, `compression_trap` 3/5, and `write_path` 3/5 over the fixed five-pass
denominator. Under the harness's measurement contract that rate is the
deliverable, and the decision on what to do about the miss belongs to the user.

## The recorded measurement

- **Run:** `run-20261008-122138`, three scenarios × five passes.
- **Worker and judge:** Cursor (`agent -p`, model `auto`) for both, every call
  from an isolated root through `tests/lib/worker_isolation.py`, with the skill
  copy staged as a project skill of that root and named by path in the prompt.
- **Deployed copy:** `make deploy` ran right before this run, so the deployed
  user-level copies of the skill were byte-identical to the staged copy. Whichever
  copy a worker read, it read the version under test. This is the only run below
  for which that holds.
- **Instrument:** the thirteen-item `fidelity_padded` ledger, graded by
  `grade.py` (including the 340 ms check) and the thirteen-item judge rubric.
- **Skill version:** fix iteration 4.

| Scenario | Pass rate | Diverging assertions |
| --- | --- | --- |
| `fidelity_padded` | 1/5 | `reads_plainly` 3/5, `strength_unchanged` 2/5 |
| `compression_trap` | 3/5 | `argument_stays_connected_prose` 3/5 |
| `write_path` | 3/5 | `no_filler_or_restatement` 3/5 |

## How the skill got here

| Run | Worker | Skill version | fidelity_padded | compression_trap | write_path | Clean passes |
| --- | --- | --- | --- | --- | --- | --- |
| `run-20261008-101519` | Claude `sonnet`, unisolated | as audited | 1/5 | 1/5 | 0/5 | 2/15 |
| `run-20261008-105117` | Cursor `auto`, isolated | as audited | 2/5 | 2/5 | 0/5 | 4/15 |
| `run-20261008-105954` | Cursor `auto`, isolated | fix iteration 1 | 1/5 | 2/5 | 4/5 | 7/15 |
| `run-20261008-110901` | Cursor `auto`, isolated | fix iteration 2 | 1/5 | 1/5 | 3/5 | 5/15 |
| `run-20261008-111827` | Cursor `auto`, isolated | fix iteration 3 | 2/5 | 1/5 | 4/5 | 7/15 |
| `run-20261008-122138` | Cursor `auto`, isolated, deployed copy matched | fix iteration 4 | 1/5 | 3/5 | 3/5 | 7/15 |

Each fix iteration followed a skill change, so each run measures a new
artifact rather than redrawing an old one. Before the third run, the rule for
choosing the shipped version was fixed: the version with the most clean passes
ships, and a tie goes to the later version. Iterations 1, 3, and 4 tied at
7/15, so iteration 4 ships. Picking the best of several five-pass draws favours
a lucky draw, so treat the shipped rate as an optimistic estimate.

During the earlier fix runs, the deployed copy was the skill as audited, and a
traced Cursor worker had read a deployed copy in place of a staged one in other
layouts. Two traced runs with this harness's staging read the staged copy, but
those earlier rates carry that caveat, while the iteration 4 run does not.

`write_path` rose from 0/5 to 3/5 or 4/5 under every fix iteration, and that
gain tracks the moves that give each ledger item one home and every sentence
and clause a job. `compression_trap` reached 3/5 once the rewrite walks an
argument in the input's own order after stating its point. The failures that
remain fall into three patterns:

- **Two causal links merging.** In `fidelity_padded` the opening sentence tends
  to fold the deadline's reason (the commitment is contractual) and the fix's
  reason (the latency is above the commitment) into one clause chain, which
  either reads as stacked or loses one of the two links.
- **A split contrast.** In `compression_trap` the recovery-versus-compounding
  contrast still comes apart when the conclusion moves to the top.
- **Small restatements.** In `write_path` a preview sentence or a repeated fact
  survives.

The judge also passed and failed near-identical texts on different draws, so
part of what remains is judge noise at this quality level, and a five-pass run
cannot separate versions whose totals differ by one or two passes.

The two runs of the skill as audited used the earlier nine-item ledger, while
the fix iterations used the thirteen-item ledger and the 340 ms check, which
are stricter. The comparison across that line therefore understates the fixes
rather than overstating them. The Claude run is unisolated and on another
vendor, so it serves as history only.

## What stays open

The bar is unmet for every scenario. The options are to accept the shipped
rate, to iterate further on the skill against the three remaining failure
patterns, or to revisit an assertion where the judge's verdict proves too noisy
to separate versions. Each of those is the user's call.
