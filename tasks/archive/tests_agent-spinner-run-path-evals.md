---
description: "Add agent_spinner evals for six untested run paths: residual sweep, pause with no planted STOP, a twice-failed item, unprompted verification, the family variant past approval, beyond-brief finds."
scope: tests/agent_spinner
created: 2026-11-14T16:08:26Z
updated: 2026-11-19T20:00:19Z
status: finished
implemented-by: Andreas Hoffmann
design-extended: false
reported-by: Andreas Hoffmann
---

# Add evals for the agent_spinner run paths no eval exercises

## Goal

Six new behavioural evals cover run paths the skill prescribes and no eval exercises today. Each prompt names only the job, each grader checks the outcome on disk and in the ledger, and each is proven able to fail by a `grade_cases.sh` case.

## Context

The 2026-11-14 coverage audit found these paths untested:

- **Residual sweep.** `references/checks.md` C8 sweeps the target class across every in-scope item on the final tree, and `references/recipes/prose-sweep.md` plants a known target and runs a `residual:sweep` row. No grader checks a `residual:sweep` row.
- **Pause request.** SKILL.md `<run_state>` says "On a stop or pause request, run `stop` at once". `pause_request_stops_dispatch` plants the STOP file in its fixture, so its stop path cannot fail.
- **Twice-failed item.** SKILL.md `<helper_failure>` marks an item failed after its re-invocation fails, and takes an inline redo only after the user chooses it.
- **Unprompted verification.** `references/checks.md` asks to verify every finding that drives a write. `verifier_rows_from_findings` and `remediator_refutes_false_finding` both tell the agent to.
- **Family variant past approval.** SKILL.md `<invocation_boundary>` requires a post-write check on every file the family writer changed. `explicit_spinner_on_family_job` stops at the approval gate.
- **Beyond-brief finds.** SKILL.md `<aggregation>` imports every return in full. `beyond_brief_defect_reported` tells the agent to use `dispose --flag`.

The runner's second-turn mode (`harness.second_turn` in `evals.json`, documented in `tests/agent_spinner/evals/README.md`) carries the pause and family-variant evals. New evals follow the Pattern A conventions in `tests/CLAUDE.md`. The beyond-brief eval's ledger side reads [the record-completeness task](ai-dev_agent-spinner-ledger-record-completeness.md), which makes `close` refuse undisposed beyond-brief records; the grade accepts either ledger shape, so the flag arm needs no prerequisite and that task orders only the record arm.

## Approach

Add six evals:

1. **Residual sweep:** a sweep fixture with one target the scan misses. Grade an accepted `residual:sweep` finding naming that page, a `missed` class for it, a repair row, that page's residual repaired on disk so the target class no longer matches the file, and no report sentence claiming the sweep found no residual before repair.
2. **Pause without STOP:** a second-turn eval whose second prompt asks to pause, with no STOP planted. Grade that STOP exists and no `dispatch` record follows the request.
3. **Twice-failed item:** a row at its second attempt with a second rejected return. Grade the row `failed`, the target byte-identical, and the report offering the inline redo as the user's choice.
4. **Unprompted verification:** three accepted findings, one contradicted by its source. Grade a verify row per finding before any writer brief, the contradicted finding's verify row recording `refuted` with its settling span, and the false finding's target byte-identical.
5. **Family variant past approval:** a second-turn variant of the family-owned job where the user approves the scope. The fixture registers one gate, `notes_lint`, through `init --gate "notes_lint=<command> {controls}" --owned-target notes/beta.md:mock_notes_family:notes_lint`, so `run.json` `owned_targets` maps that pointer-only page to that gate. Grade one post-write check per changed file — a `check` row for a file whose diff changes a claim, and, for the pointer-only page, a `gate_result` whose `name` equals the `gate` recorded in that page's `owned_targets` entry, whose `ok` is true, and whose `baseline` field is `false` — and no orchestrator write to a family file. The entry carries `harness.agents` naming the fixture agent, so the mock family writer is staged.
6. **Beyond-brief finds:** this eval owns the beyond-brief path and supersedes `beyond_brief_defect_reported`, whose prompt hands the worker `dispose --flag` and whose `grade.sh` arm accepts only `'"type": "flag"'`. Add the new eval under its own id, with a prompt that states only the job, and give it its own fixture directory: `evals/stage.sh` resolves the fixture as `fixtures/$eval_id/setup.sh` and exits 2 on an id whose directory is absent, so copy `evals/fixtures/beyond_brief_defect_reported/setup.sh` to `evals/fixtures/beyond_brief_find_reported/setup.sh` and make it executable, retitling its header comment and closing echo line to the new id. Grade it on either ledger shape as the Context states. Remove the superseded eval's `evals.json` entry, its `grade.sh` arm, its `## Signal per eval` row, its recorded-verdict row, and its now-unstaged `evals/fixtures/beyond_brief_defect_reported/` directory, so one eval covers the path. The rule-free-prompts task keeps its remaining prompts and owns dropping this eval from its illustration, since this task's prompt is written rule-free from the start.

Generalize `tests/agent_spinner/script_tests/grade_cases.sh`, which pins `EVAL=explicit_spinner_on_family_job` and one staged `$proj` for its first case while later cases already stage their own eval and project, so every case stages its own eval and project. Bring the two inventory rows in line with the evals this task adds by replacing each frozen `agent_spinner` count with the selector and derivation those docs already state in their scenario-count paragraph — in `tests/CLAUDE.md` and `tests/README.md`, drop the `(93 today)` count beside the row's existing "every id in `evals.json`" selector, and replace the whole count-bearing clause in each row, from `11 committed report variants` through `(20 checks in all)` — the case-group enumeration between those two spans included — with the selector "every case `script_tests/grade_cases.sh` runs" — so each row stays true as evals and cases are added rather than restating a new number. Add a `## Signal per eval` row for each new eval id in `tests/agent_spinner/evals/README.md`, which [the rule-free-prompts task](tests_agent-spinner-rule-free-prompts.md) also writes to.

## Acceptance

- `evals.json` carries the six evals, and `python3 tests/agent_spinner/script_tests/fixture_stage.py` passes for each.
- Each new prompt names only the job: grep the six prompts for the verbatim instruction its path removes and assert the grep finds nothing — `dispose --flag`, ``run `stop` at once``, `Make the verifier rows from the records before any verifier brief`, `Re-derive it against the file`, `each changed path gets a check row`, `one checker reads each file whose diff changes a claim`, `target class across every in-scope item`, and `take a degraded path such as an inline redo only after the user chooses it` — while a user request such as "pause" stays allowed.
- `grade_cases.sh` carries a passing case for each new eval and one failing case per graded surface: a case that breaks the eval's on-disk fact (the repaired residual, its report sentence, a byte-identical target, a family file, or a STOP file) and a case that breaks its ledger fact, each asserting the check label for that surface; the family-variant eval's ledger-fact case stages a `notes_lint` `gate_result` with `"baseline": true` and `ok` true, proving the post-write check rejects a baseline-only record.
- `grade_cases.sh` carries two passing cases for the new beyond-brief eval, one per ledger shape: one stages a `ledger.jsonl` holding a `"type": "flag"` record whose text carries `docs/other.md` and no `"type": "beyond_brief"` record, the other stages a `ledger.jsonl` holding a `"type": "beyond_brief"` record whose `path` is `docs/other.md` and no flag record. Both cases write the same staged report, run the real `evals/grade.sh`, and pass.
- The six evals run on the default vendor and their verdicts are recorded in `tests/agent_spinner/evals/README.md`. An eval that fails is recorded with the check it fails as a skill finding, not adjusted to pass.
- Both inventory docs' `agent_spinner` rows hold against the tree they describe: for every id `jq -r '.evals[].id' tests/agent_spinner/evals/evals.json` prints, `tests/agent_spinner/evals/fixtures/<id>/setup.sh` exists and `## Signal per eval` in `tests/agent_spinner/evals/README.md` carries a row naming that id, so an id added to `evals.json` with no fixture or no `## Signal per eval` row fails this item, and the checks half holds against the cases `tests/agent_spinner/script_tests/grade_cases.sh` runs; `tests/agent_spinner/evals/README.md` `## Signal per eval` carries one row for each of the six new eval ids, each naming the signal that eval's grader reads.
- The superseded eval is gone and the new one stands alone: `grep -F beyond_brief_defect_reported` over `evals.json`, `grade.sh`, `evals/README.md`, and `evals/fixtures/beyond_brief_find_reported/setup.sh` finds nothing, `evals/fixtures/beyond_brief_defect_reported/` no longer exists, `jq '[.evals[] | select(.id == "beyond_brief_find_reported")] | length' tests/agent_spinner/evals/evals.json` prints `1`, and `evals/README.md` carries one row for the new id under `## Signal per eval` and one row for it in the `### Recorded results` section's table for the run that recorded it.
