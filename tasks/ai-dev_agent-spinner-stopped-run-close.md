---
description: "Let close --stopped end a stopped agent_spinner run by settling its in-flight and never-dispatched rows, so a stopped run closes cleanly instead of staying open forever."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-27T09:00:44Z
updated: 2026-11-27T09:00:44Z
status: open
reported-by: Andreas Hoffmann
---

# Let a stopped agent_spinner run close cleanly

## Goal

`close --stopped` ends a stopped run. It settles every row still in `pending`, `dispatched`, or `unknown` to a terminal outcome with a recorded reason and exits 0, while a `violation` row still refuses and keeps the run open. Today `TERMINAL` excludes those three states, and `cmd_close` calls `close_open_items` unconditionally, so a run that follows the skill's own stop path stays open forever.

## Context

- The defect lives in `plugins/ai_dev/skills/agent_spinner/scripts/run_ledger.py`: `TERMINAL` lists only `accepted`, `inability`, `failed`, `unreturned`, and `dropped`; `close_open_items` rejects every row outside that set; and `cmd_close` runs it whether or not `--stopped` is set, returning 3.
- The archived [terminal-states task](archive/ai-dev_agent-spinner-ledger-terminal-states.md) fixed the stop report's headings and added `dispose --rows`, but it did not relax the close condition. The skill still documents `stop` then `close --stopped` as the way to end a stopped run, so the code contradicts the documented path.
- The observed effect: runs in four repositories stayed open after a stop; one session deleted the run directory rather than fake a clean close, and another reported success while its run still showed `state: open`.
- The settlement must not turn unverified work into accepted work: an `unreturned` or `dropped` row is a recorded non-result, not a pass.

## Approach

1. In `cmd_close`, when `--stopped` is set, settle each non-terminal row before `close_open_items` runs. A row that had been dispatched (`dispatched`, `unknown`) becomes `unreturned`; a row never dispatched (`pending`) becomes `dropped`. Append one `stopped` record per settled row carrying the original state and the reason, so the tally and `ledger.jsonl` agree.
2. Leave `violation` rows refusing under condition 1, and leave `accepted`, `failed`, and `inability` untouched. A run with a violation still exits non-zero.
3. Make the settlement idempotent: a second `close --stopped` on a closed run exits 0 and prints the same tally block.
4. Rewrite the `close --stopped` entry in `references/run-protocol.md` and the `<run_state>` passage in `SKILL.md` in place so both state the settlement, the two terminal outcomes, and the `violation` exception.
5. Add one `tests/agent_spinner/script_tests/ledger_run.sh` scenario covering a dispatched row, a pending row, an `unknown` row, and a violation row.

**Out of scope:** changing what `dispose --rows` does; that verb already records an explicit drop and stays the path for a deliberate narrowing.

## Acceptance

- The new `ledger_run.sh` scenario stages a run with a dispatched row, a pending row, an `unknown` row, and a violation row. `close --stopped` exits 0, the first three rows end `unreturned`/`dropped`, each settled row has a `stopped` record with its original state and a reason, and the violation row still triggers condition 1 and a non-zero exit.
- A second `close --stopped` on the same run exits 0 and prints the same tally block, proving the settlement is idempotent.
- `rg -n "close --stopped" plugins/ai_dev/skills/agent_spinner/references/run-protocol.md plugins/ai_dev/skills/agent_spinner/SKILL.md` finds text that names the settlement and the violation exception, and no passage still promises a clean close without it.
- `bash tests/agent_spinner/script_tests/ledger_run.sh` passes, including every pre-existing scenario.
