---
description: "Make an agent_spinner fork the user has not answered hold the run open: close refuses it, the skill names the record for a fork the run raises itself, and no goal or self-answer can settle it."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T23:20:22Z
updated: 2026-11-17T10:06:07Z
status: open
reported-by: Andreas Hoffmann
---

# Make an unanswered agent_spinner fork hold the run open

## Goal

A decision the run routes to the user stays open until the user answers it. Plain `close` refuses while such a fork or gate is unanswered, and on a host with no later turn the run ends through `stop` and `close --stopped` with its decision packet, the way SKILL.md `<judgement>` already says. The skill names the ledger record for a fork the orchestrator raises itself, such as a widening, an estimate above the stated guideline, or a scope question. Nothing in the run can settle the fork in the user's place: not a completion goal waiting for a clean close, and not the orchestrator answering its own gate.

## Context

All paths are under `plugins/ai_dev/skills/agent_spinner/`.

- **`close` lets a surfaced fork pass.** SKILL.md `<judgement>` says to "keep each open in the ledger until answered" and that "an unanswered gate ends the run with its decision packet: run `stop` so `STOP` is written, then `close --stopped`". But `cmd_close` in `scripts/run_ledger.py` raises condition 6 only for a fork that is "neither surfaced nor decided" and for an unanswered `user_gate`; a fork disposed as `surfaced` passes. `references/run-protocol.md`'s close condition 6 says the same ("A fork is neither surfaced nor decided, or a user gate is unanswered"), and `show --packet` renders a packet only for a surfaced fork. So the documented way to render a packet leads straight to a clean close.
- **No record for a fork the run raises itself.** SKILL.md names `dispose --open-gate` only for disagreeing returns, and `references/recipes/prose-sweep.md` names it only for recording an approval. In the 2026-11-14 evening Claude run, `widening_needs_estimate_and_ask` made the 40 requested edits, raised the widening to the other 60 pages as a surfaced fork, and closed cleanly with no gate and no STOP; earlier Claude and Cursor runs opened a gate before dispatch and stopped with `close --stopped`.
- **A goal and a self-answer settled a gate.** SKILL.md `<run_state>` has the orchestrator arm a host completion goal where the host offers one. In the Cursor run of `unanswered_gate_stops_with_packet`, the worker first stopped correctly with the full packet and `close --stopped` exiting 3, but the goal it had armed waited for `close` to exit 0, which a stopped run never does. The goal kept the turn going, and the worker then answered its own gate, citing "An answer the request states is the user's answer" although the request asked for the decision to come back unanswered, closed with exit 0, and rewrote the report without the packet.

[The report-and-packet task](archive/ai-dev_agent-spinner-report-packet-enforcement.md) makes packets carry anchored passages and edits `scripts/run_ledger.py` and `references/run-protocol.md` too. The terminal-states, brief-contract, and report-and-packet tasks land before this one; this one lands before the stamped-write-routing, coverage-gates, and record-completeness tasks, which edit the same files.

## Approach

1. In `cmd_close`, make condition 6 refuse a fork whose dispositions are all `surfaced` and that has no answer record, the same way it refuses an unanswered gate, while `close --stopped` still accepts it as the stop's open decision. Rewrite `references/run-protocol.md`'s condition 6 in place to match.
2. In SKILL.md `<judgement>`, state that a fork the orchestrator raises itself (a widening, an estimate above the stated guideline, a scope question) is recorded as a fork and a user gate before any write it would govern, and use one term for the open decision in the no-later-turn sentence. Rewrite the matching passages in `references/run-protocol.md` (the P1 announcement and gate steps and the P6 checks) and the stop-and-ask sentence in `references/recipes/prose-sweep.md`.
3. In SKILL.md `<run_state>`, make an armed completion goal's condition one a stopped run can meet, such as `close` or `close --stopped` exiting as the run's end requires, and say that a goal never answers a gate.
4. In SKILL.md `<judgement>`, state that a request answers a fork only where it decides that fork in so many words, and that a request asking for the decision to come back leaves the fork for the user.

## Acceptance

- A `ledger_run.sh` scenario: with one fork disposed `surfaced` and unanswered, plain `close` exits non-zero naming condition 6, `stop` plus `close --stopped` exits 3 with the fork listed, and an answer record lets plain `close` pass.
- `references/run-protocol.md`'s condition 6 names the unanswered surfaced fork, and the old wording ("neither surfaced nor decided") no longer stands alone.
- SKILL.md `<judgement>` names the record for an orchestrator-raised fork and the rule that only an explicit decision in the request answers a fork; `<run_state>` names a goal condition a stopped run can meet.
- `widening_needs_estimate_and_ask` and `unanswered_gate_stops_with_packet` run on the default vendor, where Cursor's goal tool exercises the goal rule, and their verdicts are recorded in `tests/agent_spinner/evals/README.md`. If either still closes cleanly over an open fork, the record names the step it skipped and the task stays open.
