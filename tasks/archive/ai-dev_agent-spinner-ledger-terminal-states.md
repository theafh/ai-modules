---
description: "Fix agent_spinner's ledger terminal states: a failed row records its source, a narrowing retires its rows, an unreturned row gets its one re-dispatch, and stop reports split unknown rows."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T16:08:26Z
updated: 2026-11-17T14:24:44Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
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

This task, [the brief-contract task](../ai-dev_agent-spinner-ledger-brief-contract.md), and [the report-and-packet task](../ai-dev_agent-spinner-report-packet-enforcement.md) all edit `run_ledger.py`, `references/run-protocol.md`, and `tests/agent_spinner/script_tests/ledger_run.sh`. Land them one at a time in that order, each on top of the one before.

## Approach

1. In `cmd_accept`'s rejection branch, set `row["source"]` to the rejected return's source whenever the branch marks the row `failed`, so a failed row carries the channel its last return came through. Leave the `violation` state for a first rejection unchanged.
2. Give `dispose` a `--rows LABEL[,LABEL...]` option that works only together with `--narrowing`. It validates every named label against the roster before it writes anything, then sets each named row's state to `dropped` and appends one `{"type": "dropped", "label": LABEL, "reason": args.narrowing}` record per row, so the reason lands in `ledger.jsonl` the way the `row_source` record already carries a row's source, with no roster column added. It refuses a label that is not a pending row and changes nothing when it refuses. `--drops` keeps its meaning, the checks the narrowing removes.
3. Let `cmd_dispatch` re-dispatch an `unreturned` row once: its second attempt moves it back to `dispatched`, and the existing two-attempt limit refuses a third.
4. In `close --stopped`, route every row whose state is not in `TERMINAL` to exactly one heading: `dispatched` and `unknown` rows go under `unknown:`, `pending` rows go under `not dispatched:` (only `init` creates that state, so a pending row was never dispatched), and `violation` rows go under their own `violation:` heading, each line keeping its `state=` field. `unreturned` is terminal, so a row in flight is a `dispatched` row with no return file.
5. Rewrite in place the passages that describe these verbs: the `dispose` option list in `references/run-protocol.md` (the `--narrowing TEXT`, `--drops TEXT` bullet) gains `--rows`, and the `close --stopped` sentence names every list it prints. Do the same in `references/report-shapes.md`: in its first `## Stop report` example (the block opening "refusing while 2 rows were pending") the line `Unknown at stop, now settled by reading: docs/upgrade.md, docs/rollback.md.` becomes `Not dispatched: docs/upgrade.md, docs/rollback.md.` and the block carries `Unknown: none.`, so no example lists a never-dispatched row under an unknown-style label; keep that block's `Untouched:` line unchanged, because that list is derived from the diff rather than from a row's state; and its "prints the tally block and the three row lists" opener and its "the stop report carries the unanswered decision packet above the three lists" sentence name the lists `close --stopped` prints. Rewrite the SKILL.md `<run_state>` sentence "Report the modified, untouched, and unknown rows" so it names the same lists, and leave the `<coverage_tradeoff>` sentence as written, because "a row left unrun is dropped by a named narrowing through `dispose`, with its reason" already matches the `--rows` verb.

6. Widen the three `tests/agent_spinner/evals/grade.sh` checks that require the literal word `unknown` — `unanswered_gate_stops_with_packet`, `pause_request_stops_dispatch`, and `roster_partial_stop` — so each also accepts an explicit empty unknown list ("Unknown: none") or a `not dispatched:` list, because each of their fixtures leaves rows never dispatched and a compliant report after this change lists those rows there.

**Out of scope:** detecting a return from a superseded attempt, or refusing one as stale; SKILL.md `<helper_failure>` puts the over-bound marking on the orchestrator.

## Acceptance

- A new `ledger_run.sh` scenario rejects one row's return twice. The row ends `failed` with a recorded `source`, and once every other condition holds, `close` exits 0.
- A new scenario runs `dispose --narrowing TEXT --rows a,b` on two pending rows. Both end `dropped`, `ledger.jsonl` carries a `dropped` record naming each of them with TEXT as its reason, `close` lists no condition 1 entry for them, and the same command naming a row that is not pending exits non-zero, leaves every row unchanged, and appends no `dropped` record.
- A new scenario opens the run with `init --bound 1`, dispatches a row, lets `accept --wait` mark it `unreturned`, re-dispatches it once successfully, and has a third dispatch refused.
- A new scenario stops a run with a `dispatched` row holding no return file, a `pending` row never dispatched, a row whose state is set directly to `unknown`, and a `violation` row. `close --stopped` prints the dispatched and `unknown` rows under `unknown:`, the pending row under `not dispatched:`, and the `violation` row under `violation:`.
- The three `tests/agent_spinner/evals/grade.sh` checks that require the literal word `unknown` — `unanswered_gate_stops_with_packet` ("the report lists unknown rows", `report_has 'unknown'`), `pause_request_stops_dispatch` ("the stop report lists unknown rows", `report_has 'unknown'`), and `roster_partial_stop` ("accounts for unknown-state artifacts", `response_has 'unknown'`) — each also accepts an explicit empty unknown list ("Unknown: none") or a `not dispatched:` list, because each fixture leaves rows never dispatched. A `grade_cases.sh` case per widened check stages that eval's fixture plus the roster or ledger state the check reads, writes the report or response form the check reads with its never-dispatched rows under `not dispatched:` and no "unknown" word, and asserts the widened check passes it — the form the old check failed although the property held, which is the broadening evidence `TESTING.md` `## Test Integrity` requires; the `unanswered_gate_stops_with_packet` case covers both forms.
- `references/run-protocol.md`'s `dispose` option list documents `--rows`, and its `close --stopped` sentence names every list the report prints (modified, untouched, unknown, not dispatched, violation). `references/report-shapes.md`'s `## Stop report` opener and its "above the three lists" sentence name the lists `close --stopped` prints; its first example block (the block opening "refusing while 2 rows were pending") carries `Not dispatched: docs/upgrade.md, docs/rollback.md.` beside `Unknown: none.`, and its second block carries `Unknown: none.` and lists no never-dispatched row under an unknown-style label. `SKILL.md`'s `<run_state>` names the same lists. A grep across `plugins/ai_dev/skills/agent_spinner/` for `modified, untouched, and unknown`, `the three row`, `above the three lists`, and `Unknown at stop` finds nothing.
