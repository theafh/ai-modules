---
description: "Make the agent_spinner ledger accept valid gate argv and an absolute brief target, and stop the brief verb crashing when its source and destination are one file."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-27T09:00:44Z
updated: 2026-11-27T12:29:05Z
status: open
reported-by: Andreas Hoffmann
---

# Make the agent_spinner ledger accept a valid gate argv and an absolute brief target

## Goal

The ledger accepts a valid gate command and a brief whose target is an absolute path instead of rejecting them on form. `brief` records an absolute target without a `SameFileError`, and `init` refuses a gate argv that cannot take the `{controls}` placeholder.

## Context

- Two input contracts reject valid input in `plugins/ai_dev/skills/agent_spinner/scripts/run_ledger.py`:
  - `brief` raised `shutil.SameFileError` when `--target` is an absolute path: `os.path.join(root, target)` and `os.path.join(dest_dir, target)` both return the absolute target, so the source and destination are one file. Reproduced on a row with no recorded path: `brief check:r --body B --target "$PWD/a.txt"` exits 1 at `shutil.copyfile`.
  - `run_gate_argv` appends the controls directory when the argv carries no `{controls}` placeholder. A lint gate whose argv already names its own path therefore failed from `init` onward with `unrecognized arguments`, and the run's baseline gate was a usage error.
- A prose-only return is not one of these. `references/run-protocol.md`'s return contract requires optional prose plus exactly one fenced JSON block, so `accept`'s `block count is 0` rejection is the documented behaviour. The orchestrator recovers through `<helper_failure>`'s one re-invocation on a corrected brief, and this task leaves that contract unchanged.
- These two are one class: the ledger's input contracts are narrower than the documented contract, and a run that follows the skill loses its verification to a form mismatch.

## Approach

1. In `brief`, compare the resolved source and destination paths before copying. When they are the same file, skip the copy and record the brief from the existing path, so the hash and the accept audit still work.
2. In `init`, validate each gate argv: when it carries no `{controls}` placeholder, either require the placeholder or pass the controls path as a documented environment variable, and refuse the gate with a named error when the argv cannot accept it. Never append a positional path to an argv that did not ask for one.
3. Rewrite the `brief` and gate entries in `references/run-protocol.md` in place to match the implemented contract. State the return contract's prose rejection as it stands, so the documented and implemented contracts agree.
4. Add one `ledger_run.sh` scenario per contract: a brief whose target is absolute succeeds and its accept audit resolves the hash; an argv without `{controls}` is refused at `init` with a named error.

**Out of scope:** relaxing the severity ladder or the classification rules; those are substantive checks and stay strict. Also out of scope: changing the return contract to accept a prose-only return; it requires one fenced JSON block by design.

## Acceptance

- A new `ledger_run.sh` scenario stages a brief whose target is an absolute path; `brief` exits 0, writes the brief, and the accept audit still resolves its hash.
- A new scenario calls `init` with a gate argv that lacks `{controls}`; `init` exits non-zero with a named error, and no gate run appends the controls directory as a stray positional argument.
- `rg -n "absolute|\\{controls\\}" plugins/ai_dev/skills/agent_spinner/references/run-protocol.md` finds the implemented contract for each, with the prior passage superseded rather than duplicated.
- `bash tests/agent_spinner/script_tests/ledger_run.sh` passes, including every pre-existing scenario.
