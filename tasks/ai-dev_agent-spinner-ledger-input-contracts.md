---
description: "Make the agent_spinner ledger accept valid prose returns and valid gate argv, and stop the brief verb crashing when its source sits inside the run root."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-27T09:00:44Z
updated: 2026-11-27T09:00:44Z
status: open
reported-by: Andreas Hoffmann
---

# Make the agent_spinner ledger accept valid input

## Goal

The ledger accepts a valid return and a valid gate command instead of rejecting them on form. A documented prose return passes `accept`, `brief` copies a source that sits inside the run root without a `SameFileError`, and `init` refuses a gate argv that cannot take the `{controls}` placeholder.

## Context

- Three input contracts reject valid input in `plugins/ai_dev/skills/agent_spinner/scripts/run_ledger.py`:
  - `cmd_accept` rejected a real helper return with `block count is 0` and `finding severity 'note' is outside the ladder`, forcing the orchestrator to aggregate by hand and close the run stopped with rows still dispatched.
  - `brief` raised `shutil.SameFileError` when its source path resolved inside the run root, so briefs were hand-rendered and the brief-hash and accept audits were unenforced.
  - `run_gate_argv` appends the controls directory when the argv carries no `{controls}` placeholder. A lint gate whose argv already names its own path therefore failed from `init` onward with `unrecognized arguments`, and the run's baseline gate was a usage error.
- These are one class: the ledger's input contracts are narrower than the documented contract, and a run that follows the skill loses its verification to a form mismatch.

## Approach

1. Give `accept` a documented prose form. Either accept the prose return the role prompts already describe, or ship the exact return schema in `references/role-prompts.md` and make the parser accept that schema. Keep the strict form for a return that claims a classification or a check it did not make; the fix is to stop rejecting a well-formed prose return for shape alone.
2. In `brief`, compare the resolved source and destination paths before copying. When they are the same file, skip the copy and record the brief from the existing path, so the hash and the accept audit still work.
3. In `init`, validate each gate argv: when it carries no `{controls}` placeholder, either require the placeholder or pass the controls path as a documented environment variable, and refuse the gate with a named error when the argv cannot accept it. Never append a positional path to an argv that did not ask for one.
4. Rewrite the `accept`, `brief`, and gate entries in `references/run-protocol.md` in place to match the implemented contract.
5. Add one `ledger_run.sh` scenario per contract: a prose return accepts; a brief whose source is inside the run root succeeds; an argv without `{controls}` is refused at `init` with a named error.

**Out of scope:** relaxing the severity ladder or the classification rules; those are substantive checks and stay strict.

## Acceptance

- A new `ledger_run.sh` scenario submits a well-formed prose return and gets `accept` with a recorded source, not a `block count is 0` rejection.
- A new scenario stages a brief source inside the run root; `brief` exits 0, writes the brief, and the accept audit still resolves its hash.
- A new scenario calls `init` with a gate argv that lacks `{controls}`; `init` exits non-zero with a named error, and no gate run appends the controls directory as a stray positional argument.
- `rg -n "block count|SameFileError|\\{controls\\}" plugins/ai_dev/skills/agent_spinner/references/run-protocol.md` finds the implemented contract for each.
- `bash tests/agent_spinner/script_tests/ledger_run.sh` passes, including every pre-existing scenario.
