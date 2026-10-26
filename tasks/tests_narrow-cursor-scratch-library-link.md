---
description: "Narrow the Cursor micro-deploy scratch home's link from the whole real ~/Library to Library/Keychains only, so worker searches stop reaching other apps' data."
scope: tests/lib
created: 2026-10-26T12:37:52
updated: 2026-10-26T12:37:52
status: open
reported-by: Andreas Hoffmann
---

# Narrow the Cursor scratch home's Library link to Library/Keychains

## Goal

Every Cursor eval worker that `tests/lib/micro_deploy.py` prepares gets a scratch home whose `Library` is a real directory holding exactly one entry, `Keychains`, a symlink to the real `~/Library/Keychains`. The Cursor login keeps working, and nothing else of the real `~/Library` is reachable from the scratch home. Worker file searches over the scratch home then stop walking into other apps' private data (`Library/Containers`, `Library/Group Containers`), which ends the macOS "would like to access data from other apps" dialogs those searches trigger, under whichever app launched the eval.

## Context

- **Current mechanism.** `_link_library` in `tests/lib/micro_deploy.py` symlinks the scratch home's `Library` to the whole real `~/Library`, and `micro_deploy()` calls it for the Cursor vendor so the worker can reuse the stored login. The mechanism shipped with [the micro-deploy task](archive/tests_micro-deployed-eval-workers.md), whose verified finding was that an empty scratch `HOME` leaves the Cursor CLI logged out while a linked `Library` restores the login.
- **Why the whole link causes harm.** A worker that globs its own home (observed: a Glob for `**/auto_drift_task*` rooted at the scratch home in the `mechanical_lint_ready` and `mechanical_lint_markdown` scenarios of `tests/task_auto_check/evals/run.py`) follows the link into the real `Library`. The Cursor CLI's bundled `rg` then touches every app container, and macOS raises one privacy check per container and process, attributed to the app at the top of the process chain. The link also exposes the user's Cursor app state (`Library/Application Support/Cursor/User/globalStorage/state.vscdb`, workspace storage) to workers, which weakens the isolation the micro-deploy exists for.
- **What the login actually needs (verified 2026-10-26).** The Cursor CLI stores its credentials in the macOS login keychain (account `cursor-user`, services such as `cursor-access-token`) and reads them through `/usr/bin/security`. With `HOME` set to an empty directory, `security find-generic-password -a cursor-user -s cursor-access-token` exits 44 and `agent status` reports "Not logged in". With `HOME` set to a directory whose `Library/Keychains` links to the real one, both succeed (`agent status` reports logged in).
- **Other Library reads in the CLI.** The CLI also looks for `Library/Application Support/Cursor/AgentStores`, falling back to a temporary store when it is absent, and for IDE workspace storage under `Library/Application Support/Cursor/User`, which is optional state. Neither is needed for login, per the CLI bundle's code; the live preflight in Acceptance confirms the fallback works.
- **Cleanup paths that name the link.** `MicroDeployHandle.close` and the `except BaseException:` block in `micro_deploy()` (commented "the scratch home (with its Library link) must not outlive it") remove the `Library` link before deleting the scratch tree, and `preflight_auth`'s Cursor remedy text says the scratch home "borrows the Cursor login through its `Library` link".
- **Tests that pin the old shape.** `tests/lib/test_micro_deploy.py` asserts the whole-`Library` symlink in the checks labelled "cursor Library linked when present", "Library linked before close", and "Library unlinked before the scratch tree is removed".
- **Wiki record.** `wiki/entities/cursor.md` states that "A scratch `HOME` authenticated once its `Library` linked back to the real one", citing the 2026-10-08 micro-home probe note. Wiki edits run through the `wiki` skill per the repo's standing instructions.

## Approach

1. Rewrite `_link_library` into a keychain-only link: create `scratch_home/Library` as a real directory and symlink `scratch_home/Library/Keychains` to the real `~/Library/Keychains`, skipping the link when the real `Keychains` directory is absent (the same "when present" behaviour the current function has). Rename the function to match what it now links, and update its call site in `micro_deploy()`.
2. Rewrite both cleanup passages (`MicroDeployHandle.close` and the `except BaseException:` block) to unlink `scratch_home/Library/Keychains` first and then remove the scratch tree, so removal never traverses into the real keychain directory. Update the block's comment to name the `Keychains` link.
3. Rewrite the Cursor remedy string in `preflight_auth` so it says the scratch home borrows the login through its `Library/Keychains` link; keep the `agent login` and `CURSOR_API_KEY` guidance.
4. Rewrite the three link checks in `tests/lib/test_micro_deploy.py` to the new shape: `Library` is a directory whose only entry is `Keychains`, `Keychains` is a symlink resolving to the real `~/Library/Keychains`, the `Keychains` link is gone before the scratch tree is removed, and the real `~/Library/Keychains` is still a directory after `close()`.
5. Through the `wiki` skill, rewrite the `wiki/entities/cursor.md` passage on the scratch `HOME` so it states that linking `Library/Keychains` alone authenticates, and record the 2026-10-26 keychain probe results from Context as the evidence the passage cites.

**Out of scope:**

- Changing the worker permission flags in `tests/lib/vendor.py` (`--force --sandbox disabled`), since this task removes the reachable data rather than sandboxing the worker.
- Changing how the harness handles a worker that globs its own home, since the narrowed link makes that search harmless.

## Acceptance

1. `python3 tests/lib/test_micro_deploy.py` passes, and its Cursor checks assert that the scratch home's `Library` is a directory listing only `Keychains`, and that `Keychains` is a symlink to the real `~/Library/Keychains`.
2. The same test run asserts that `close()` removes the `Keychains` link before deleting the scratch tree, that the scratch tree is gone afterwards, and that the real `~/Library/Keychains` is still a directory.
3. `rg -n 'symlink_to\(real_library' tests/lib/micro_deploy.py` returns nothing, and `rg -n 'linked when present|Library linked before close' tests/lib/test_micro_deploy.py` returns nothing, so the whole-`Library` link and its checks are superseded.
4. `rg -n 'through its .Library. link' tests/lib/micro_deploy.py` returns nothing, and the Cursor remedy string names `Library/Keychains`.
5. On a machine with a stored Cursor login, `micro_deploy.preflight_auth("cursor", "agent")` returns without exiting, and `agent status` run with `HOME` set to a scratch home built by `micro_deploy()` reports a logged-in user. If either fails, the implementer reads the CLI error, adds only the `Library` sub-path it names as a second link beside `Keychains`, records that sub-path and the error in the wiki evidence from Approach step 5, and re-runs both checks.
6. `wiki/entities/cursor.md` states that a scratch `HOME` authenticates with only `Library/Keychains` linked, and the sentence saying it authenticated "once its `Library` linked back to the real one" no longer appears.
