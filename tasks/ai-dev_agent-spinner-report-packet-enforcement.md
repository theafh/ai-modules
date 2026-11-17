---
description: "Make agent_spinner's report-opening and decision-packet rules hold: every restatement and the P6 check name all four opening facts, and the ledger refuses a fork without an anchored passage."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T16:08:26Z
updated: 2026-11-14T23:20:22Z
status: open
reported-by: Andreas Hoffmann
---

# Make agent_spinner's report-opening and decision-packet rules hold

## Goal

An orchestrator that follows agent_spinner writes a report whose opening sentence carries the answer, the tier, helpers dispatched against returned, and whether `close` exited 0. Every decision packet it renders names each passage the fork touches, verbatim with its anchor. Today both rules live only in reference prose, and the 2026-11-14 Claude run (`opus` at high effort) broke both while it kept every rule that `accept` or `show` enforces.

## Context

All paths are under `plugins/ai_dev/skills/agent_spinner/`.

**The opening sentence.** SKILL.md `<reporting>` states the rule: "The opening sentence gives the answer, the tier, helpers dispatched against returned, and whether `close` exited 0". Every other place that restates the opening names only one of those facts:

- SKILL.md `<degradation>` says "State the tier reached in the run's opening sentence".
- SKILL.md `<run_state>` and `references/run-protocol.md`'s no-clean-close rule name the close status alone.
- The P6 self-check in `references/run-protocol.md`, the report's only self-check, tests the close status alone.
- `references/recipes/fidelity-review.md` names per-phase counts.
- `references/report-shapes.md`'s stop template ("Stopped after 2 of 4 writers, at the spawned-roles tier, 2 dispatched against 2 returned.") puts the close status in a second sentence.

Across the 71 Opus reports of that run, 29 carried the tier and dispatched-against-returned within the first two sentences, and 61 carried both somewhere in the opening paragraph. A run that did not close cleanly tended to lead with the failure, as the close-status restatements ask, and pushed the other facts to sentences three to five. The four evals `clean_corpus`, `containment_one_path`, `planted_defect`, and `roster_partial_stop` fail on that; their grader already allows two sentences. The evening Claude run of the repaired suite failed the same rule in `containment_one_path`, `roster_partial_stop`, `report_rederivation`, and `skipped_close_reported`, the last on "the report's opening says no clean close exists".

**The decision packet.** `references/report-shapes.md` says a packet carries "each passage the fork touches verbatim with its anchor", and its stop-report example shows a "Passages touched:" block with "anchor: request, sentence 2". `references/run-protocol.md` asks to "Render each decision packet with `show --packet ID` … rather than by hand". But the fork schema there says "A fork may also carry `passages`", `validate_return` in `scripts/run_ledger.py` checks `passages` only when it is present, and `show --packet` prints "Passages touched:" followed by "none" for a fork that carries none. A fully compliant run can therefore render a packet with no passage. `unanswered_gate_stops_with_packet` failed because its worker wrote the packet by hand without passages; the gap would survive a run that used `show`.

This task, [the terminal-states task](archive/ai-dev_agent-spinner-ledger-terminal-states.md), and [the brief-contract task](ai-dev_agent-spinner-ledger-brief-contract.md) all edit `scripts/run_ledger.py` and `references/run-protocol.md`. Land this one after both.

## Approach

1. Keep the opening rule as SKILL.md `<reporting>` states it, and rewrite each restatement listed above in place so it names all four opening facts or points at `<reporting>` instead of naming one of them. The no-clean-close restatements keep their instruction to say so first, inside that same opening sentence.
2. Rewrite the P6 self-check in `references/run-protocol.md` so it checks all four facts in the opening sentence, and rewrite `references/report-shapes.md`'s stop template so its first sentence carries all four, the close status included.
3. Make an anchored passage part of the fork contract. `validate_return` refuses a fork with no `passages` entry carrying an anchor, `show --packet` refuses to render a fork without one, and `references/run-protocol.md`'s fork schema states the requirement in place of "A fork may also carry `passages`". A fork that touches only the request names the request sentence as its passage.
4. Run `python3 tests/agent_spinner/script_tests/fixture_stage.py`. Each fixture whose staged return carries a fork without an anchored passage now fails it; give each such fork a passage taken from its fixture's own text.

## Acceptance

- A static check in `tests/agent_spinner/script_tests/run.sh` finds every passage in SKILL.md and `references/` that defines what the opening sentence carries, by the phrase "opening sentence", and asserts that each names all four facts or points at `<reporting>`.
- The P6 self-check text and the stop template's first sentence each carry all four facts.
- A `ledger_run.sh` scenario: `accept` rejects a return whose fork has no anchored passage and takes the same return once the fork carries one; `show --packet` on a fork without an anchored passage exits non-zero.
- `python3 tests/agent_spinner/script_tests/fixture_stage.py` passes for every eval.
- The opening-cluster evals (`clean_corpus`, `containment_one_path`, `planted_defect`, `roster_partial_stop`, `report_rederivation`, `skipped_close_reported`) and `unanswered_gate_stops_with_packet` run on the default vendor, and the result is recorded in `tests/agent_spinner/evals/README.md`. If any of them fails on the opening or the packet, the record says which fact or field was missing, and the task stays open for another pass on the wording rather than adjusting the grader to the miss.
