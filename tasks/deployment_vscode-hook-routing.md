---
description: Filter foreign configs out of the vscode hook route, ship a Copilot-schema hook config, and switch VS Code's Claude hook sources off so native delivery is the only route.
scope: deployment
created: 2026-08-09T20:07:35
updated: 2026-08-09T20:31:12
status: open
reported-by: Andreas Hoffmann
---

# Deliver hooks to VS Code Copilot natively and close the foreign-config paths

## Goal

The `vscode` deploy target delivers the CHARTER.md guardrail hook to GitHub
Copilot in a configuration file Copilot can actually load, it stops copying the
other harnesses' hook configurations into Copilot's hook root, and it switches off
the Claude hook sources VS Code would otherwise read, so the native file is the
one route the guard arrives by.

Today every hook artefact reaches Copilot, because the `vscode` branch of the
deploy script's hook case is the only per-target branch with no filename filter.
The user-visible outcome is twofold: a Copilot session stops logging a validation
error per foreign file at every start, and the guardrail that already blocks a
CHARTER.md mutation on Claude, Codex, and Antigravity blocks it on Copilot too.

## Context

### What the branch does now

In `deployment/deployment.sh`, the hook artefact case first gates on file
extension (locate by the message `not an executable hook or hook config`), then
dispatches per target. Five branches filter by filename before writing: Cursor
answers a non-matching file with `not a Cursor hook config`, Claude with
`not a Claude hook config`, Codex with `not a Codex custom deploy hook config`,
Antigravity with `not an Antigravity hook config`, and OpenCode with
`Hook deployment not implemented for`. The `vscode)` branch has no such test. It
copies every `.sh` and `.json` the hook discovery yields into the Copilot hook
directory under the target's configuration root.

A type-scoped dry run confirms the result: alongside the shared
`charter_guardrail.sh`, Copilot receives `hooks.json`, `codex-plugin-hooks.json`,
`codex-custom-deploy-hooks.json`, and `antigravity-hooks.json`. Every other target
skips all four of the files not written for it.

### Why this matters, and why it is currently inert

`~/.copilot/hooks` is the documented user-scope hook root for both Copilot in VS
Code and GitHub Copilot CLI, and the CLI reference states that every `*.json`
there loads at start. The deposit therefore lands where two products parse it,
which is the contamination
[foreign directory adoption](../wiki/concepts/foreign-directory-adoption.md)
argues against, produced here by this repository's own installer.

Nothing executes today, and only because two failures both hold. The three files
shaped `{"hooks": {"PreToolUse": [...]}}` are structurally valid and then lose
every item to validation, because a Claude or Codex matcher group carries no
`command` field; the Antigravity file has no top-level `hooks` key at all.
Independently, every `command` value is unusable in this position: two name
`${CLAUDE_PLUGIN_ROOT}` or `${PLUGIN_ROOT}`, which no Copilot product sets, and
two are relative `./hooks/` paths that only the merge routes rewrite.

### The contract to write against

[GitHub Copilot in VS Code](../wiki/entities/github-copilot-vs-code.md) carries
the researched hook contract, and
[hook surface portability](../wiki/concepts/hook-surface-portability.md) carries
its place beside the other four. The three facts this task builds on:

- Copilot puts hook objects **directly** under the event name, with no matcher
  groups and no documented `matcher` field, which is the single structural
  difference from the Claude and Codex files.
- Its stdin envelope is snake_case like Claude's, and exit 2 is a blocking error,
  so `plugins/ai_dev/hooks/charter_guardrail.sh` already implements the signalling
  Copilot expects and needs no change.
- The surface is documented as Preview, and the drop-the-malformed-item rule is
  stated in GitHub's CLI hooks reference rather than on the VS Code page, so the
  VS Code loader's behaviour on a malformed item is inferred rather than verified.
  That verification gap is recorded on the entity page and stays recorded.

### Related work

[deployment_opencode-hook-bridge.md](deployment_opencode-hook-bridge.md) extends
the same per-target hook dispatch for OpenCode, so the two tasks edit one region
of `deployment.sh` and whichever lands second rebases onto the other's branch
structure.

## Approach

1. **Filter the `vscode)` hook branch** the way the other five already filter.
   Keep the `.sh` copy unchanged, and accept a `.json` only when its basename
   matches `vscode-hooks*`, mirroring the Cursor branch's `cursor-hooks` test and
   its skip message wording. With no matching file present the branch then writes
   only the shared script, which is the correct outcome even before step 2 ships.

2. **Add `plugins/ai_dev/hooks/vscode-hooks.json`** in Copilot's schema: a
   top-level `hooks` key, `PreToolUse` mapping directly to an array of hook
   objects, each `{"type": "command", "command": ..., "timeout": ...}` with no
   matcher-group wrapper. Cover the same mutation surface the sibling configs
   cover, expressed through Copilot's own tool vocabulary rather than Claude's
   matcher strings.

3. **Rewrite the command path on the copy route.** The merge routes already
   rewrite a relative `./hooks/` command to an absolute path under the target's
   hook directory for global scope and to a project-relative path under
   `--project-dir`. The Copilot file is written by a copy rather than a merge, so
   extend that rewrite to the `vscode` copy path, keeping the committed file's
   command relative so no machine-specific path is ever committed.

4. **Retract the four already-deployed strays** through the existing mechanism
   rather than new cleanup code. The deployed-artefacts log records each of them,
   so `make uninstall` followed by a fresh deploy removes them. State that
   sequence in `deployment/README.md` beside the hook rows, since a plain redeploy
   leaves the strays in place and a hardcoded filename-removal list in the script
   would be exactly the machine-local assumption the standing repo rules keep out
   of published artefacts.

5. **Update the routing rows in `deployment/README.md`.** The per-target hook
   table currently gives VS Code Copilot an unqualified `~/.copilot/hooks/<file>`
   copy. Rewrite that cell to name the `vscode-hooks*.json` filter alongside the
   shell-script copy, matching the qualified rows the other targets already carry,
   and add the design-table row that names the new file's target the way the
   Cursor, Codex, and Antigravity rows name theirs.

6. **Switch the Claude hook sources off for VS Code**, so the native file is the
   only route the guard arrives by. VS Code's `chat.hookFilesLocations` maps a path
   to a boolean and a `false` disables it even when it is a documented default, so
   merge `{".claude/settings.json": false, "~/.claude/settings.json": false}` into
   the user's VS Code settings through the script's existing key-merge function.
   That path already captures the prior value on first write and restores it on
   uninstall, so the switch is reversible by the mechanism the repository
   established for the `outputStyle` key. Narrow the merge to exactly the Claude
   hook paths, leaving every other entry the user set untouched.

**Out of scope:**

- A Cursor hook configuration. Cursor's branch matches on `cursor-hooks*` and the
  repository ships no such file, but its hook contract is unresearched, so writing
  one would be guessing at a schema.
- A Claude `claude-code-hooks*.json` merged into `~/.claude/settings.json`. The
  decision below rules it out, so its absence is now intended rather than pending.
- The instructions half of the same adoption. Switching `~/.claude/rules` off
  through `chat.instructionsFilesLocations` belongs with the instructions delivery
  in [deployment_output-style-vscode.md](deployment_output-style-vscode.md), which
  owns that configuration root.
- Replacing the five per-branch filename tests with one declarative per-target
  allowlist. It is the better structure and it prevents this class of defect
  recurring, but it refactors a working dispatch for a defect that has occurred
  once.

### The delivery route, decided

Copilot reads hooks from both its own `~/.copilot/hooks` and from
`~/.claude/settings.json`, and its documented loading rule runs every matching
hook from every source, so a Claude settings merge plus a Copilot-native file
would fire the guard twice in one VS Code session. The route is **Copilot's own
file only**: ship `vscode-hooks.json` per steps 1 to 3, close the adoption path
per step 6, and leave Claude's hook configuration to plugin install rather than
merging it into `~/.claude/settings.json`.

Two reasons carry it. Native delivery keeps the deploy in control of what each
harness receives, in the schema that harness actually implements. And a harness
reading another's artefacts never implements them fully: it takes the file,
ignores the keys it has no concept for, maps what it recognises onto its own
model, and drops the rest without an error, which is a degraded integration in
the target harness rather than a free one. Relying on the Claude sources would
have taken that trade in exchange for skipping one file.
[foreign directory adoption](../wiki/concepts/foreign-directory-adoption.md)
carries the general form of this position and the per-harness switch inventory.

## Acceptance

1. A hook-scoped dry run of the deploy script at global scope reports a skip for
   `hooks.json`, `codex-plugin-hooks.json`, `codex-custom-deploy-hooks.json`, and
   `antigravity-hooks.json` on the `vscode` target, where it previously reported a
   copy for each.
2. The same dry run still reports the `charter_guardrail.sh` copy into the Copilot
   hook directory, so the filter narrowed the JSON route without dropping the
   script.
3. `plugins/ai_dev/hooks/vscode-hooks.json` exists, is valid JSON, and its
   `PreToolUse` array holds hook objects carrying `command` directly, with no
   entry containing a nested `hooks` array or a `matcher` key.
4. The committed `vscode-hooks.json` carries a relative `./hooks/` command, and a
   global dry run reports the path rewrite to the Copilot hook directory for that
   file, matching the rewrite the Codex and Antigravity merge rows already report.
5. A `--project-dir` dry run against a scratch directory reports the
   project-scoped rewrite for the same file rather than the global absolute path.
6. `deployment/README.md`'s VS Code Copilot hook cell names the `vscode-hooks*`
   filter, its design table carries a row for the new file, and the stray-retraction
   sequence is stated once beside those rows; the previous unqualified copy wording
   is gone rather than sitting beside the new text.
7. A global dry run reports a `chat.hookFilesLocations` merge into the VS Code
   user settings file carrying `.claude/settings.json` and `~/.claude/settings.json`
   set to `false`, and reports capturing the key's prior value, where it previously
   reported no settings write for the `vscode` target at all.
8. Running the uninstall path against a deploy log holding that merge restores the
   captured prior value, and removes the key outright when the recorded prior was
   the absent marker.
9. An unrelated entry placed in `chat.hookFilesLocations` before the deploy
   survives it, proving the merge narrowed to the two Claude paths rather than
   replacing the key.
