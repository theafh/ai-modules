---
description: Make the deploy script add or update only ai-modules' own hook entries in Codex, Claude Code and Cursor hook files, keep every foreign entry in place, and uninstall only its own.
scope: deployment
created: 2026-10-17T00:45:44
updated: 2026-10-17T00:45:44
status: open
reported-by: Andreas Hoffmann
---

# Merge ai-modules' hook entries into shared hook files instead of replacing them

## Goal

A deploy writes ai-modules' hooks into each harness's hook file entry by entry.
It adds an ai-modules entry that is missing, updates one that exists at the
position it already holds, and removes one the shipped config no longer
carries, while every entry the user or another tool put into the same file
stays exactly where it was. An uninstall removes only the entries ai-modules
added. The user-visible outcome is that `make deploy` and `make uninstall`
never delete a hook the user or another tool installed in Codex's
`hooks.json`, Claude Code's `settings.json` or Cursor's `hooks.json`, at global
and project scope alike.

## Context

The arms of the `hook)` case in `install_for_app()` in
`deployment/deployment.sh` that write a harness's shared hook file do so at a
coarser grain than the entries they own:

- **Codex.** The `codex)` arm passes `codex-custom-deploy-hooks.json` to
  `merge_json_key` with the key `hooks`, and `merge_json_key` sets the whole key
  through `.${key} = $patch`. Every deploy therefore resets the `hooks` object
  of `~/.codex/hooks.json` to ai-modules' entries and drops any other hook under
  it. This route is live, since the guard hook ships through it.
- **Claude Code.** The `claude)` arm sends a `claude-code-hooks*.json` through
  the same call into the `hooks` key of `settings.json`. No such file ships,
  because Claude Code's hooks arrive by plugin install, so the route is dormant
  and would replace the user's whole `hooks` key the day a file appears.
- **Cursor.** The `cursor)` arm deploys a `cursor-hooks*.json` through
  `copy_file` or `copy_path_with_replacements`, and `copy_file` removes the
  existing `~/.cursor/hooks.json` before copying. No such file ships, so this
  route is dormant as well.

Uninstall reverses a merged key through the prior value `merge_json_key`
records in the deploy log's fifth field. `lookup_logged_prior` makes the first
deploy's sample the prior for every later deploy, so an uninstall restores the
hook object as it stood before ai-modules' first deploy and discards every hook
added since. A global run's timestamped backup of the whole config directory is
then the only copy of such hooks.

Two existing behaviours set the target. The `antigravity)` arm already merges
under its own named key, `charter_guardrail`, and touches nothing else in
Antigravity's hook file, which is the behaviour this task gives the other arms.
Codex keeps each hook's trust state in `~/.codex/config.toml` under `hooks.state`
tables whose names end in the hook's event and its position in the file, so an
entry that moves leaves the trust state of whatever now sits at its old position
stale and prompts the user again.

Related tasks:

- [The output-style groundwork](archive/deployment_output-style-claude-groundwork.md)
  built the first-write prior capture inside `merge_json_key` and the deploy
  log's fifth field. This task keeps that contract for scalar keys and gives
  hook keys an entry manifest instead.
- [Uninstall respects scope](deployment_uninstall-respects-scope.md) derives each
  log entry's scope from its deployed path, the `path[key]` form included, and
  edits `uninstall_logged_artifacts`, which this task edits too. Keeping hook
  entries in the `path[key]` form keeps that derivation valid, and whichever
  task lands second rebases onto the other's edit of that function.
- [Update from the deploy log](deployment_update-from-deploy-log.md) replays
  logged entries through the deploy path, so the entry merge gives the same
  result on a replay as on a first deploy.
- [VS Code hook routing](deployment_vscode-hook-routing.md) edits the `vscode)`
  arm of the same `hook)` case, records the decision that Claude Code's hooks
  stay out of `settings.json`, and owns Copilot's hook delivery.

## Approach

1. **Add one entry-merge function** beside `merge_json_key` in
   `deployment/deployment.sh`. It reads the shipped config's `hooks` object,
   applies the target's `replace:` substitutions and the existing `./hooks/`
   command-path rewrite, and merges event by event:
   - An entry's identity is the set of commands it runs after the rewrite: a
     matcher group's commands for Codex and Claude Code, and an entry's
     `command` for Cursor.
   - A shipped entry whose identity matches an existing entry replaces it at
     the same position, and a shipped entry with no match is appended to the
     end of its event's list.
   - An entry that the target's existing `@entries:` manifest lists, and whose
     identity the shipped config no longer carries, is removed.
   - Every other entry, event and top-level key of the target file stays as it
     was, including Cursor's `version` and every other key of `settings.json`.
   - In dry-run mode it reports each entry it would add, update or remove, and
     writes nothing.
2. **Log the owned entries.** The function logs the target as `path[hooks]`, as
   today, and writes `@entries:` followed by a compact JSON list of the owned
   entries' events and identities into the fifth field, in place of a whole-key
   prior. The existing `@absent` marker is the precedent for an `@`-prefixed
   value there. A legacy hook line that still carries a whole-key prior is
   rewritten to the manifest form on the next deploy.
3. **Route the arms through it.** The `codex)` and `claude)` arms call the new
   function for their hook configs in place of `merge_json_key`, and the
   `cursor)` arm calls it for `cursor-hooks*.json` in place of the copy.
4. **Uninstall by manifest.** In `uninstall_logged_artifacts`, a `path[key]`
   line whose fifth field starts with `@entries:` removes exactly the listed
   entries, removes an event list or `hooks` object the removal left empty, and
   drops the log line. A line carrying a prior value or `@absent` keeps today's
   restore or strip, and so does a legacy hook line met before any redeploy.
5. **Rewrite the deploy documentation in place.** In `deployment/README.md`,
   the Cursor, Claude Code and OpenAI Codex hook rows of both tables, and the
   passage on the log's fifth field, describe the entry merge and the
   `@entries:` manifest where they now describe a copy and a whole-key merge.

**Out of scope:**

- Changing `merge_json_key` for scalar settings keys such as `outputStyle`,
  which the deploy owns outright and keeps restoring from the recorded prior.
- Changing Antigravity's named-key merge, which already touches only its own
  entry.
- Copilot's hook delivery, owned by the VS Code hook routing task.
- OpenCode's hook delivery, owned by
  [the OpenCode hook bridge](deployment_opencode-hook-bridge.md).
- Shipping a `cursor-hooks*.json` or `claude-code-hooks*.json`, since this task
  makes those routes safe without adding a config to either.

## Acceptance

Each scenario runs in the deployment script tests under
`tests/deployment/script_tests/`, against a sandbox home and project, under the
repo's testing rules.

1. A sandbox `~/.codex/hooks.json` seeded with a foreign `PreToolUse` group and
   a foreign `PostToolUse` group keeps both, unchanged and at their original
   positions, after a `--global --type hook --target codex` deploy, and holds
   ai-modules' guard group exactly once.
2. A second identical deploy leaves that `hooks.json` byte-identical to the
   first deploy's result.
3. A `--project-dir` deploy of the Codex hooks into a sandbox project whose
   `.codex/hooks.json` holds a foreign group keeps that group and adds
   ai-modules' group once.
4. With a fixture config that changes the guard group's matcher, a redeploy
   updates ai-modules' group at the same position and leaves the foreign groups
   unchanged.
5. With a fixture deploy log whose `@entries:` manifest lists an owned entry the
   shipped config no longer carries, a redeploy removes that entry and keeps the
   foreign groups.
6. `--uninstall` after the deploy in item 1 leaves both foreign groups in
   place, removes ai-modules' group and its log line, and in a sandbox file that
   held no other hooks leaves no empty `hooks` object behind.
7. The entry-merge function, called with a staged `cursor-hooks.json` fixture
   against a sandbox Cursor `hooks.json` holding a foreign entry and `version`,
   keeps both and adds ai-modules' entry once, and the manifest uninstall
   removes only that entry.
8. The same function, called with a staged `claude-code-hooks.json` fixture
   against a sandbox `settings.json` holding a foreign hook group and an
   unrelated key, keeps both and adds ai-modules' group once.
9. A `--dry-run` of the deploy in item 1 lists each entry it would add, update
   or remove, and leaves the sandbox files byte-identical.
10. A fixture deploy log carrying a legacy whole-key prior for a
    `hooks.json[hooks]` line holds an `@entries:` manifest on that line after
    one deploy.
11. A search of `deployment/deployment.sh` shows the `cursor)` arm's
    `cursor-hooks` route calling the entry-merge function with no `copy_file`
    call for it, and shows neither the `codex)` nor the `claude)` arm passing
    `"hooks"` to `merge_json_key`.
12. `deployment/README.md` describes the entry merge in the Cursor, Claude Code
    and OpenAI Codex hook rows and the `@entries:` manifest in the fifth-field
    passage, and no longer says the Cursor config is copied to
    `~/.cursor/hooks.json` or that the `hooks` key is merged whole.
