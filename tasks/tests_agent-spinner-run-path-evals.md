---
description: "Add agent_spinner evals for six untested run paths: residual sweep, pause with no planted STOP, a twice-failed item, unprompted verification, the family variant past approval, beyond-brief finds."
scope: tests/agent_spinner/evals
created: 2026-11-14T16:08:26Z
updated: 2026-11-17T12:38:29Z
status: checked
reported-by: Andreas Hoffmann
---

# Add evals for the agent_spinner run paths no eval exercises

## Goal

Six new behavioural evals cover run paths the skill prescribes and no eval exercises today. Each prompt names only the job, each grader checks the outcome on disk and in the ledger, and each is proven able to fail by a `grade_cases.sh` case.

## Context

The 2026-11-14 coverage audit found these paths untested:

- **Residual sweep.** `references/checks.md` C8 sweeps the target class across every in-scope item on the final tree, and `references/recipes/prose-sweep.md` plants a known target and runs a `residual:sweep` row. No grader mentions `residual`.
- **Pause request.** SKILL.md `<run_state>` says "On a stop or pause request, run `stop` at once". `pause_request_stops_dispatch` plants the STOP file in its fixture, so it cannot fail.
- **Twice-failed item.** SKILL.md `<helper_failure>` marks an item failed after its re-invocation fails, and takes an inline redo only after the user chooses it.
- **Unprompted verification.** `references/checks.md` asks to verify every finding that drives a write. `verifier_rows_from_findings` and `remediator_refutes_false_finding` both tell the agent to.
- **Family variant past approval.** SKILL.md `<invocation_boundary>` requires a post-write check on every file the family writer changed. `explicit_spinner_on_family_job` stops at the approval gate.
- **Beyond-brief finds.** SKILL.md `<aggregation>` imports every return in full. `beyond_brief_defect_reported` tells the agent to use `dispose --flag`.

The runner's second-turn mode (`harness.second_turn` in `evals.json`, documented in `tests/agent_spinner/evals/README.md`) carries the pause and family-variant evals. New evals follow the Pattern A conventions in `tests/CLAUDE.md`. The beyond-brief eval's ledger side depends on [the record-completeness task](ai-dev_agent-spinner-ledger-record-completeness.md), which makes `close` refuse undisposed beyond-brief records; land that task first.

## Approach

Add six evals:

1. **Residual sweep:** a sweep fixture with one target the scan misses, such as one split across a hard wrap. Grade an accepted `residual:sweep` finding naming that page, a kept-or-missed class for it, a repair row, and no report sentence claiming zero residuals.
2. **Pause without STOP:** a second-turn eval whose second prompt asks to pause, with no STOP planted. Grade that STOP exists and no `dispatch` record follows the request.
3. **Twice-failed item:** a row at its second attempt with a second rejected return. Grade the row `failed`, the target byte-identical, and the report offering the inline redo as the user's choice.
4. **Unprompted verification:** three accepted findings, one contradicted by its source. Grade a verify row per finding before any writer brief, and the false finding's target byte-identical.
5. **Family variant past approval:** a second-turn variant of the family-owned job where the user approves the scope. Grade a check row per file the family writer changed and no orchestrator write to a family file.
6. **Beyond-brief finds:** the `beyond_brief_defect_reported` situation with the `dispose --flag` instruction removed. Grade that the find is flagged or disposed in the ledger and named in the report.

## Acceptance

- `evals.json` carries the six evals, and `python3 tests/agent_spinner/script_tests/fixture_stage.py` passes for each.
- `grade_cases.sh` carries a failing and a passing case for each new eval.
- The six evals run on the default vendor and their verdicts are recorded in `tests/agent_spinner/evals/README.md`. An eval that fails is recorded with the check it fails as a skill finding, not adjusted to pass.
