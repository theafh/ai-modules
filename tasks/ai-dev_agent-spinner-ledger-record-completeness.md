---
description: "Make agent_spinner's ledger hold every return field and report claim the skill relies on: import beyond-brief finds, dispose own-authority calls, fill the repair list, and ship the report lint."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T16:08:26Z
updated: 2026-11-14T23:20:22Z
status: open
reported-by: Andreas Hoffmann
---

# Make the agent_spinner ledger hold what the skill says it holds

## Goal

Every mechanism the skill and its references attribute to the run ledger exists and is checked at `close`. A helper's beyond-brief finds become ledger records, its own-authority calls and dropped suspicions need a disposition before a clean close, recall provenance holds when a brief pastes a producer's finding, the repair list fills from failed verification, shared rules are compared between a producer and its checker, and the report lint the references describe flags uncited assertions. Today each of these is stated in the skill and missing from `scripts/run_ledger.py`, so a run that ignores them still closes cleanly.

## Context

All paths are under `plugins/ai_dev/skills/agent_spinner/`. The coverage audit of 2026-11-14 confirmed each gap by reading or running the ledger.

- **Beyond-brief and own-authority records.** SKILL.md `<aggregation>` says "The ledger imports every return in full", and `<reporting>` requires the report to separate what a helper found beyond its brief from what it decided on its own authority. `RECORD_LISTS` in `run_ledger.py` leaves out `beyond_brief`, although the return template lists it, so those finds never become records. `close` condition 2 asks for a disposition only for findings, incidents, alternatives, and objections, so `own_authority` and `dropped_suspicions` records need none.
- **Recall provenance.** SKILL.md `<confirmation_provenance>` defines recall-confirmed. `references/run-protocol.md` lets a brief paste the producer's material below a stated cap instead of relaying it. The ledger tags a confirmation recall-confirmed only when the row has a producer, which only `brief --relay` sets, so a checker whose brief pastes the finding is tagged independently surfaced.
- **The repair list.** SKILL.md `<remediation>` says the repair list holds every item that failed verification. `run.json`'s `repair_list` is initialised empty and read by `rows --from-repair-list` and `status`, but no verb ever fills it.
- **Shared rules across phases.** SKILL.md `<prompt_assembly>` requires a producer and its checker to share the rules file byte for byte. `cmd_brief` compares shared blocks only within one phase, while a producer and its checker usually sit in different phases.
- **The report lint.** `references/run-protocol.md` says "The report lint flags an assertion word, such as verified or complete" that carries no ledger citation, and `references/checks.md` and `references/report-shapes.md` rely on the same lint. The ledger has no report lint; `close` condition 7 only checks that `report.md` carries the current tally block. The skill states the citation rule in four places, so the ledger implements the lint rather than the references dropping it.

The terminal-states, brief-contract, report-and-packet, unanswered-fork, stamped-write-routing, and coverage-gates tasks edit the same ledger file and `tests/agent_spinner/script_tests/ledger_run.sh`; land this one last.

## Approach

1. Add `beyond_brief` to `RECORD_LISTS` so each entry becomes a record, and extend `close` condition 2 to require a disposition or flag for `beyond_brief`, `own_authority`, and `dropped_suspicions` records.
2. Let `brief` record a producer when its body pastes a producer's accepted finding, through an explicit `--pasted-from LABEL` option, and tag the resulting confirmation recall-confirmed the way `--relay` does.
3. Fill `repair_list` from every verification record whose verdict is a failure, so `rows --from-repair-list` and `status` read real entries.
4. Compare the shared rules block of a checker's brief with its producer's brief, wherever the two rows sit, and refuse a mismatch the way the same-phase comparison does.
5. Add the report lint as a `close` condition: an assertion word from a fixed list (verified, complete, confirmed, all, none, and the list the references name) in `report.md` must carry a ledger citation in the same sentence. Define the citation form once in `references/report-shapes.md` and point the other three references at it.
6. Rewrite in place each reference passage that describes these mechanisms, so it states what the ledger now does.

## Acceptance

- `ledger_run.sh` scenario: a return carrying `beyond_brief`, `own_authority`, and `dropped_suspicions` entries yields records for each, and `close` refuses until each is disposed or flagged.
- `ledger_run.sh` scenario: a checker briefed with `--pasted-from` the producer's label confirms the finding, and the confirmation is tagged recall-confirmed.
- `ledger_run.sh` scenario: a failed verification fills `repair_list`, and `rows --from-repair-list` creates a row for it without hand-editing `run.json`.
- `ledger_run.sh` scenario: a checker brief whose shared rules differ from its producer's, in another phase, is refused.
- `ledger_run.sh` scenario: `close` refuses a report that says "verified" in a sentence with no ledger citation and accepts it once the citation is present.
