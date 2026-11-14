---
description: "Repoint task_auto_check scenario s15's gate isolation pin from the retired `grep -r --exclude-dir` recipe to the ignore-aware search rule auto_gate_task now carries."
scope: tests/task_auto_check
created: 2026-11-14T12:42:55Z
updated: 2026-11-14T12:45:55Z
status: implemented
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Pin the hardened gate search isolation in task_auto_check scenario s15

## Goal

Scenario s15 of the `task_auto_check` script tests asserts the search-isolation wording that `auto_gate_task` actually carries, so the harness passes again and s15 still fails when that hardening is reverted. The repair lives in the test, because the gate's current contract is the intended one.

## Context

Scenario s15 ("blocking bar, scoped rounds, stall and compaction stops, and robust returns are pinned") in `tests/task_auto_check/script_tests/run.sh` checks `plugins/ai_dev/agents/auto_gate_task.md` with the assertion labelled `gate excludes the relay from recursive searches`, whose needle is `grep -r --exclude-dir=.task_auto_check`. That needle comes from the **Isolation counts reads.** item of [the robust-helper-returns task](archive/task-family_auto-check-robust-helper-returns.md), which asked both the gate and the dry-run agent to name that recipe.

Commit 39e771e ("Harden auto_gate_task's search isolation") later rewrote the gate's isolation rule, the `<rule>` that opens "Judge the task file as it stands", on purpose. The rule now admits only what git would commit, requires an ignore-aware search such as `rg --hidden` or `git grep` plus `git ls-files --others --exclude-standard`, and names `grep -r`, `find`, and a plain recursive listing as contract violations. The old needle is gone from the gate, so s15 fails today and keeps the deterministic test gate red. No commit after 39e771e touched the gate file, so `git show 39e771e^:plugins/ai_dev/agents/auto_gate_task.md` yields the pre-hardening text exactly.

`plugins/ai_dev/agents/auto_dryrun_task.md` was not hardened and still names `grep -r --exclude-dir=.task_auto_check`, so its own s15 assertion, `dry run excludes the relay from recursive searches`, passes as it stands.

## Approach

Rewrite the gate assertion in s15 in place. Replace the `gate excludes the relay from recursive searches` line with two `assert_contains` pins on `$gate` that carry the hardening's two halves:

- **The requirement**, labelled `gate requires an ignore-aware search`, with the needle `Reach it with an ignore-aware search that also covers hidden paths`.
- **The prohibition**, labelled `gate names a VCS-blind walker as a violation`, with the needle ``A filesystem walker that ignores VCS ignore files, such as `grep -r`, `find`, or a plain recursive listing, is a contract violation``. Escape each backtick inside the double-quoted bash string the way the neighbouring s15 assertions do.

Rewrite the comment above that block, `# Isolation counts reads only, and recursive searches skip the relay.`, so it names both behaviours it now pins: the gate searches with an ignore-aware mechanism, and the dry run's recursive searches skip the relay. The dry-run assertion and the `an empty traversal is not an out-of-bounds read` assertion on the skill stay as they are.

**Out of scope:**

- Editing `auto_gate_task.md` or `auto_dryrun_task.md`, since the gate's hardened contract is the intended one and the hardening covered the gate alone.

## Acceptance

1. `bash tests/task_auto_check/script_tests/run.sh` reports s15 as `PASS`, and the run's summary lists no failed scenario.
2. `grep -nF '"$gate" "grep -r --exclude-dir=.task_auto_check"' tests/task_auto_check/script_tests/run.sh` returns nothing, so the retired gate pin is superseded rather than kept beside the new ones.
3. With the pre-hardening gate written over the file by `git show 39e771e^:plugins/ai_dev/agents/auto_gate_task.md > plugins/ai_dev/agents/auto_gate_task.md`, the harness reports s15 as `FAIL` with a `missing text` line for each of the two new gate pins. `git checkout -- plugins/ai_dev/agents/auto_gate_task.md` then restores the file, and s15 passes again.
