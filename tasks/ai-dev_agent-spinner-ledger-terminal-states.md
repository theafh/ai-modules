---
description: "Fix agent_spinner's ledger terminal states: a failed row records its source, a narrowing retires its rows, an unreturned row gets its one re-dispatch, and stop reports split unknown rows."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T16:08:26Z
updated: 2026-11-14T23:45:46Z
status: open
reported-by: Andreas Hoffmann
---

# Fix the agent_spinner ledger's terminal states

## Goal

A run whose helper row ends `failed` after its one re-invocation, or whose unrun rows a named narrowing drops, reaches a clean `close` once every other close condition holds. A row past its bound gets the one re-invocation the skill promises it. `close --stopped` lists rows that were never dispatched apart from the rows the skill calls unknown, which are rows in flight at the stop. Today four ledger paths keep a run that follows SKILL.md exactly from closing cleanly, block its retry, or mislabel its stop report.

## Context

All four paths live in `plugins/ai_dev/skills/agent_spinner/scripts/run_ledger.py`:

- **A failed row never gets a source.** `cmd_accept`'s rejection branch, the block that sets `row["state"] = "violation" if not prior else "failed"`, records the return's source only on the `accept_reject` record and leaves `row["source"]` unset. `cmd_close` refuses with "condition 8: row %s has no recorded source" for every `accepted`, `inability`, or `failed` row without a source, so one twice-rejected return keeps `close` refusing for the rest of the run.
- **A narrowing never retires its rows.** SKILL.md `<coverage_tradeoff>` says "a row left unrun is dropped by a named narrowing through `dispose`, with its reason". `cmd_dispose`'s `--narrowing` branch only appends a `narrowing` record carrying free `--drops` text. No code path sets a row's state to `dropped`, although `TERMINAL` lists that state. The dropped rows stay pending, and `close` refuses on condition 1.
- **An unreturned row cannot be re-dispatched.** SKILL.md `<helper_failure>` says "A row past its bound is unreturned, earns the same single re-invocation". `accept --wait` sets such a row to `unreturned`, and `cmd_dispatch` refuses it with "row %s is already terminal (%s)" because its terminal-state list includes `unreturned`. `ledger_run.sh` never calls `accept --wait`.
- **"unknown:" mixes two kinds of row.** SKILL.md `<run_state>` says to "mark in-flight rows unknown" after a stop and to "Report the modified, untouched, and unknown rows". `close --stopped` prints every non-terminal row under `unknown:`, including pending rows that were never dispatched, and `references/run-protocol.md` repeats that ("`close --stopped` also prints the modified, untouched, and unknown rows").

The 2026-11-14 Claude suite run (`opus` at high effort) hit the failed-row, narrowing, and unknown-label paths. `containment_one_path` could not close on condition 8 alone, `planted_defect` partly on it, and `clean_corpus` and `roster_partial_stop` on condition 1 after narrowings that dropped rows. In the stop report, `roster_partial_stop`'s worker settled the "unknown" clash by calling never-dispatched rows "pending (never dispatched)". Each of these runs follows the skill's retry and narrowing rules, so the defect sits in the ledger, not in the model.

This task, [the brief-contract task](ai-dev_agent-spinner-ledger-brief-contract.md), and [the report-and-packet task](ai-dev_agent-spinner-report-packet-enforcement.md) all edit `run_ledger.py`, `references/run-protocol.md`, and `tests/agent_spinner/script_tests/ledger_run.sh`. Land them one at a time in that order, each on top of the one before.

## Approach

1. In `cmd_accept`'s rejection branch, set `row["source"]` to the rejected return's source whenever the branch marks the row `failed`, so a failed row carries the channel its last return came through. Leave the `violation` state for a first rejection unchanged.
2. Give `dispose` a `--rows LABEL[,LABEL...]` option that works only together with `--narrowing`. It sets each named row's state to `dropped` and records the narrowing text as that row's reason. It refuses a label that is not a pending row and changes nothing when it refuses. `--drops` keeps its meaning, the checks the narrowing removes.
3. Let `cmd_dispatch` re-dispatch an `unreturned` row once: its second attempt moves it back to `dispatched`, and the existing two-attempt limit refuses a third. A late return for the first attempt is still reported as over its bound, as SKILL.md `<helper_failure>` says.
4. In `close --stopped`, print rows dispatched but not returned under `unknown:` and pending rows never dispatched under their own `not dispatched:` heading.
5. Rewrite in place the passages that describe these verbs: the `dispose` option list in `references/run-protocol.md` (the `--narrowing TEXT`, `--drops TEXT` bullet) gains `--rows`, and the `close --stopped` sentence names the four lists. Do the same for the stop-report lines in `references/report-shapes.md` that list the modified, untouched, and unknown rows, and for the SKILL.md `<coverage_tradeoff>` sentence when its wording no longer matches the verb.

## Acceptance

- A new `ledger_run.sh` scenario rejects one row's return twice. The row ends `failed` with a recorded `source`, and once every other condition holds, `close` exits 0.
- A new scenario runs `dispose --narrowing TEXT --rows a,b` on two pending rows. Both end `dropped`, `close` lists no condition 1 entry for them, and the same command naming a row that is not pending exits non-zero and leaves every row unchanged.
- A new scenario dispatches a row with `--bound 1`, lets `accept --wait` mark it `unreturned`, re-dispatches it once successfully, and has a third dispatch refused.
- A new scenario stops a run that has one dispatched, unreturned row and one never-dispatched row. `close --stopped` prints the first under `unknown:` and the second under `not dispatched:`.
- `unanswered_gate_stops_with_packet`'s "the report lists unknown rows" check in `tests/agent_spinner/evals/grade.sh` also accepts an explicit empty unknown list ("Unknown: none") or a `not dispatched:` list, because a stop before dispatch leaves every row never dispatched; a `grade_cases.sh` case pins both forms.
- `references/run-protocol.md`'s `dispose` option list documents `--rows`, and its `close --stopped` sentence names all four lists. A grep for the old three-list sentence finds nothing.
