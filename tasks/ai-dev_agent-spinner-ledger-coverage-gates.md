---
description: "Close four agent_spinner ledger paths that let a run overstate its coverage: --classify accepting a rejected check, the writer-only wave cap, the blind count gate, and the probe's read-only verdict."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T16:08:26Z
updated: 2026-11-14T23:20:22Z
status: open
reported-by: Andreas Hoffmann
---

# Close the agent_spinner ledger paths that let a run overstate its coverage

## Goal

The run ledger refuses, or records honestly, four situations in which a run today closes cleanly and reports more checking than it did. A check row closed by classification is counted and reported as unchecked unless a named narrowing covers it. The wave cap bounds unchecked writes rather than writers in flight. A count gate needs a counter whose own positive control passed. The probe records the read-only lever as enforced only when the helper actually could not write.

## Context

Every path is in `plugins/ai_dev/skills/agent_spinner/scripts/run_ledger.py`, and `tests/agent_spinner/script_tests/ledger_run.sh` exercises none of the four failure cases. The coverage audit of 2026-11-14 reproduced each one in a scratch repository.

- **`--classify` accepts a rejected return.** In `cmd_accept`, the branch `if errors and args.classify:` marks the row `accepted`, sets its source, and records only a `classification`. `change_covered` then counts that row as the check its path needs, `close` exits 0, and the tally reports it under `accepted`. The recipes prescribe exactly this command to close sampled-out check rows (`references/recipes/prose-sweep.md` and `references/recipes/multi-file-task.md`, the `accept check:<slug> --stdin --classify` line), and with nothing on stdin that command exits 2 ("return for check:... is empty"). SKILL.md `<coverage_tradeoff>` says "Name every narrowing out loud, printed from the ledger", and `references/checks.md` says `close` refuses "while a changed path lacks an accepted check from another row".
- **The wave cap counts writers in flight.** `cmd_dispatch` counts writer rows in state `dispatched` against `wave_size`, while its error says "written rows are unchecked". Three writers can be dispatched, written, and accepted one after another under `--wave 1` with no check row at all. SKILL.md `<phase_plan>` says "Run writes and their checks in waves, so a stop leaves at most one wave unchecked", and `references/run-protocol.md` says to run "pending checks ahead of queued writes".
- **A count gate accepts a blind count.** `cmd_gate`'s `count` branch only checks that some counter is registered. `references/checks.md` says "`count` needs a counter whose positive control passed", and SKILL.md `<checking>` says "a probe fires on a known positive before its empty result counts".
- **The probe trusts a missing marker.** `accept_probe` records `read_only: enforced` whenever `returns/probe:<slug>.start` is absent, but the probe brief rendered by `init --probe` only says "Attempt one write inside the run directory" and never names that file. A helper that writes any other file is recorded as enforced. `references/run-protocol.md` P1 counts the lever as enforced "only when the probe's write attempt inside the run directory left no file". Separately, `checker_spawned_through_role` grades the spawn route from roster rows the orchestrator fills in itself through `dispatch --route`.

The terminal-states, brief-contract, report-and-packet, unanswered-fork, and stamped-write-routing tasks edit the same ledger file and `ledger_run.sh`; land this one after them and before the record-completeness task.

## Approach

1. Count a check row closed by `--classify` as covering its path only when a `narrowing` record names that row; otherwise `close` refuses on the uncovered changed path. Give the tally a separate count for classified rows. Let `accept --classify TEXT` take an empty stdin, because the classification text is the whole record of a sampled-out row, and keep both recipe lines as written.
2. Make `cmd_dispatch`'s writer cap count written rows that lack an accepted check from another row, in addition to writers in flight, so a writer waits while the previous wave is unchecked.
3. Make the `count` gate require a registered counter whose own positive control passed, and refuse otherwise.
4. Make the probe brief name the exact marker file it must try to write, and have `accept_probe` record `enforced` only when that marker is absent and no other file the probe helper wrote, apart from its return, appeared in the run directory. Add `tool_record: true` to `checker_spawned_through_role` in `tests/agent_spinner/evals/evals.json`, and grade that a spawn call naming the checker role appears in the recorded tool calls.
5. Rewrite in place the `references/run-protocol.md` and `references/checks.md` passages that describe these verbs, so each states what the ledger now enforces.

## Acceptance

- `ledger_run.sh` scenario: a hollow checker return accepted with `--classify` and no narrowing leaves `close` refusing on its path, the same row named by a narrowing lets `close` pass, and the tally carries the classified count.
- `ledger_run.sh` scenario: the recipes' sampled-out command, run with nothing on stdin, exits 0 and records the classification.
- `ledger_run.sh` scenario: under `--wave 1`, after one writer is accepted on a changed path with no accepted check, the next writer dispatch is refused.
- `ledger_run.sh` scenario: a count gate with a counter whose control fails, run on a script that prints zero for a known positive, records `ok: false` and exits non-zero.
- `ledger_run.sh` scenario: a probe helper that writes a file other than the marker is recorded as not enforced.
- `checker_spawned_through_role` carries `tool_record: true` and a grader check on the recorded spawn call, with a `grade_cases.sh` case where a run that types the route without spawning fails.
