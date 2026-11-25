---
description: Filter foreign configs out of the vscode hook route and ship a Copilot-schema hook config, leaving the Claude hook sources readable because no documented setting closes them for the Copilot harness.
scope: deployment
created: 2026-08-09T18:07:35Z
updated: 2026-11-25T16:26:13Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
---

# Deliver hooks to VS Code Copilot natively and close the foreign-config paths

## Goal

The `vscode` deploy target delivers the CHARTER.md guardrail hook to GitHub
Copilot in a configuration file Copilot can actually load, and it stops copying
the other harnesses' hook configurations into Copilot's hook root. The native
`vscode-hooks.json` is the route that works regardless of the editor's
Local-harness settings. Copilot also reads the repository's `.claude/settings.json`
and `.claude/settings.local.json` directly, and no documented setting closes that
read, so the guard can run from more than one source; that duplication is
harmless because the guard denies idempotently.

Today every hook artefact reaches Copilot, because the `vscode` branch of the
deploy script's hook case is the only per-target branch with no filename filter.
The user-visible outcome is twofold: a Copilot session stops logging a validation
error per foreign file at every start, and the guardrail that already blocks a
CHARTER.md mutation on Claude, Codex, and Antigravity blocks it on Copilot too.

## Context

### What the branch does now

In `deployment/deployment.sh`, the hook artefact case first gates on file
extension (locate by the message `not an executable hook or hook config`), then
dispatches per target. Four branches filter by filename before writing: Cursor
answers a non-matching file with `not a Cursor hook config`, Claude with
`not a Claude hook config`, Codex with `not a Codex custom deploy hook config`,
and Antigravity with `not an Antigravity hook config`. The OpenCode branch
instead falls through to `Hook deployment not implemented for`, so it writes
nothing. The `vscode)` branch has no such test. It copies every `.sh` and
`.json` the hook discovery yields into the Copilot hook directory under the
target's configuration root.

A type-scoped dry run confirms the result: alongside the shared
`charter_guardrail.sh`, Copilot receives `hooks.json`, `codex-plugin-hooks.json`,
`codex-custom-deploy-hooks.json`, and `antigravity-hooks.json`. Every other target
skips the configs not written for it.

### Why this matters, and why it is currently inert

`~/.copilot/hooks` is the documented user-scope hook root for both Copilot in VS
Code and GitHub Copilot CLI, and the CLI reference states that every `*.json`
there loads at start. The deposit therefore lands where two products parse it,
which is the contamination
[foreign directory adoption](../../wiki/concepts/foreign-directory-adoption.md)
argues against, produced here by this repository's own installer. That page
carries the general form of this position and the per-harness switch inventory.

Nothing executes today, and only because two failures both hold. The three files
shaped `{"hooks": {"PreToolUse": [...]}}` are structurally valid and then lose
every item to validation, because a Claude or Codex matcher group carries no
`command` field; the Antigravity file has no top-level `hooks` key at all.
Independently, every `command` value is unusable in this position: two name
`${CLAUDE_PLUGIN_ROOT}` or `${PLUGIN_ROOT}`, which no Copilot product sets, and
two are relative `./hooks/` paths that only the merge routes rewrite.

### The contract to write against

[GitHub Copilot in VS Code](../../wiki/entities/github-copilot-vs-code.md) carries
the researched hook contract, and
[hook surface portability](../../wiki/concepts/hook-surface-portability.md) carries
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

1. **Filter the `vscode)` hook branch** the way the other four already filter.
   Keep the `.sh` copy unchanged, and accept a `.json` only when its basename
   matches `vscode-hooks*`, mirroring the Cursor branch's `cursor-hooks` test and
   its skip message wording. With no matching file present the branch then writes
   only the shared script, which is the correct outcome even before step 2 ships.

2. **Add `plugins/ai_dev/hooks/vscode-hooks.json`** in Copilot's schema: a
   top-level `hooks` key, `PreToolUse` mapping directly to an array of hook
   objects, each `{"type": "command", "command": ..., "timeout": ...}` with no
   matcher-group wrapper. A single `PreToolUse` command hook covers every tool
   call, and the guardrail script's own `tool_input` inspection narrows it to the
   mutation surface the sibling configs match, so the file needs no per-tool
   narrowing.

3. **Rewrite the command path on the copy route.** The merge routes already
   rewrite a relative `./hooks/` command to an absolute path under the target's
   hook directory for global scope, and to a project-relative path under
   `--project-dir` for Claude, Cursor, and Antigravity; Codex uses an absolute
   path in both scopes. The Copilot file is written by a copy rather than a merge,
   so extend that rewrite to the `vscode` copy path, keeping the committed file's
   command relative so no machine-specific path is ever committed.

4. **Retract the already-deployed foreign hook configs** through the existing
   mechanism rather than new cleanup code. The deployed-artefacts log records each
   of them, so `./deployment/deployment.sh --uninstall --global` followed by a
   fresh global deploy removes them. State that
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

6. **Write no Claude hook-source switch.** An earlier version of this step merged
   `{".claude/settings.json": false, "~/.claude/settings.json": false}` into
   `chat.hookFilesLocations`. The live page
   (`code.visualstudio.com/docs/agent-customization/hooks`, read 25 November 2026)
   shows that switch cannot do the job: `chat.hookFilesLocations` is documented
   under "Existing Local hooks" and "Local editor settings such as
   `chat.hookFilesLocations` do not configure Copilot discovery". The Copilot
   harness reads inline hook settings in `.github/copilot/settings.json`,
   `.github/copilot/settings.local.json`, and `~/.copilot/settings.json`, and it
   reads repository `.claude/settings.json` and `.claude/settings.local.json`
   directly; "Local settings such as `chat.useHooks` do not prevent the Copilot
   harness from loading a configuration", and no documented setting disables that
   read. The route is therefore the native file alone, with no settings write, and
   the record of the verified contract lives on the wiki entity page. The
   settings-map merge helper stays in the script for the instructions sibling,
   which merges `chat.instructionsFilesLocations` through it.

**Out of scope:**

- A Cursor hook configuration. Cursor's branch matches on `cursor-hooks*` and the
  repository ships no such file, but its hook contract is unresearched, so writing
  one would be guessing at a schema.
- A Claude `claude-code-hooks*.json` merged into `~/.claude/settings.json`. The
  decision below rules it out, so its absence is now intended rather than pending.
- The instructions half of the same adoption. Switching `~/.claude/rules` off
  through `chat.instructionsFilesLocations` belongs with the instructions delivery
  in [deployment_output-style-vscode.md](../deployment_output-style-vscode.md), which
  owns that configuration root.
- Replacing the four per-branch filename tests with one declarative per-target
  allowlist. It is the better structure and it prevents this class of defect
  recurring, but it refactors a working dispatch for a defect that has occurred
  once.

### The delivery route, decided

Copilot reads hooks from both its own `~/.copilot/hooks` and the repository
`.claude/settings.json` files, and its documented loading rule runs every matching
hook from every source, so a Claude settings merge plus a Copilot-native file would
fire the guard twice in one VS Code session. The route is **Copilot's own file
only**: ship `vscode-hooks.json` per steps 1 to 3, write no settings switch per
step 6, and leave Claude's hook configuration to plugin install rather than
merging it into `~/.claude/settings.json`. The Claude sources stay readable by the
Copilot harness, and the duplicate guard run is harmless because the guard denies
idempotently.

Two reasons carry it. Native delivery keeps the deploy in control of what each
harness receives, in the schema that harness actually implements. And a harness
reading another's artefacts never implements them fully: it takes the file,
ignores the keys it has no concept for, maps what it recognises onto its own
model, and drops the rest without an error, which is a degraded integration in
the target harness rather than a free one. Relying on the Claude sources would
have taken that trade in exchange for skipping one file.

## Acceptance

1. A hook-scoped dry run of the deploy script at global scope reports a skip on
   the `vscode` target for every `.json` hook config the discovery yields whose
   basename does not match `vscode-hooks*`, where it previously reported a copy
   for each.
2. The same dry run still reports the `charter_guardrail.sh` copy into the Copilot
   hook directory, so the filter narrowed the JSON route without dropping the
   script.
3. `plugins/ai_dev/hooks/vscode-hooks.json` exists, is valid JSON, carries the
   documented top-level `"version": 1`, and its `PreToolUse` array holds hook
   objects carrying `command` directly, with no entry containing a nested `hooks`
   array or a `matcher` key.
4. The committed `vscode-hooks.json` carries a relative `./hooks/` command, and a
   global dry run reports the path rewrite to the Copilot hook directory for that
   file, matching the rewrite the Codex and Antigravity merge rows already report.
5. A `--project-dir` dry run against a scratch directory reports the
   project-scoped rewrite for the same file rather than the global absolute path.
6. `deployment/README.md`'s VS Code Copilot hook cell names the `vscode-hooks*`
   filter, its design table carries a row for the new file, and the stray-retraction
   sequence is stated once beside those rows; the previous unqualified copy wording
   is gone rather than sitting beside the new text.
7. A global dry run reports no `chat.hookFilesLocations` merge and no write to the
   VS Code user settings file for the `vscode` target, and a real hook deploy
   leaves a settings file planted beforehand byte-identical, because that key
   configures only the Local harness and leaves the Copilot harness reading the
   repository `.claude/settings.json` files.
8. The settings-map merge helper kept for the sibling instructions route tolerates
   a settings file carrying `//` comments and trailing commas, preserves a `//`
   inside a string value, reports the normalization, and warns a skip instead of
   failing the run when the file still does not parse.
9. The same helper merges at entry grain: an unrelated entry placed in the key
   beforehand survives, every other settings key is untouched, the map's prior
   value is recorded in the deploy log, and uninstall restores it or removes the
   key when the recorded prior was the absent marker.
10. The command the deployed `vscode-hooks.json` carries blocks a CHARTER.md
    mutation: piping a Copilot-shaped `PreToolUse` envelope, a stdin object with
    `tool_name`, `tool_input.file_path` naming `CHARTER.md`, and a `cwd` inside a
    repository whose root carries `CHARTER.md`, through that command exits 2,
    while the same envelope naming an ordinary file exits 0.

## Implementation notes

Implemented 2026-11-25. Corrected the same day after audit: the settings switch
this task first shipped does not close the Copilot harness's Claude hook route.

- `deployment/deployment.sh`: the `vscode` hook arm skips every `.json` hook
  config whose basename does not match `vscode-hooks*` and keeps the shell-script
  copy. `rewrite_hook_command_paths` is the copy-route counterpart of the merge
  routes' rewrite: it points the copied config's `./hooks/` commands at
  `${app_dir}/hooks` at global scope and at `.github/hooks` under
  `--project-dir`. The arm writes no VS Code settings key. `chat.hookFilesLocations`
  is a Local-harness setting that does not configure Copilot discovery, and no
  documented setting stops the Copilot harness reading the repository
  `.claude/settings.json` files, so the native config is the route that works and
  the possible second guard run is harmless because the guard denies idempotently.
- `merge_settings_map_entries` stays for the sibling
  [deployment_output-style-vscode.md](../deployment_output-style-vscode.md), which
  merges `chat.instructionsFilesLocations` through it. It merges at entry grain,
  records the map's whole prior value, and now normalizes a settings file that
  carries `//` comments or trailing commas through `strip_jsonc` before the jq
  pass. A file that still does not parse is reported as a skip and the run
  continues, so one editor-authored settings file cannot abort a whole deploy.
- The deploy log's `path[key]` notation accepts a dotted top-level key, and
  `restore_json_key` / `strip_json_key` address the key with `--arg k` rather
  than a jq path. `path_exists` reads key presence with `has($k)`, so a key whose
  value is `false` still counts as present.
- `plugins/ai_dev/hooks/vscode-hooks.json`: a top-level `"version": 1`, and one
  `PreToolUse` command hook with no `matcher`, running
  `./hooks/charter_guardrail.sh` with a 30-second timeout.
- `tests/deployment/script_tests/vscode_hook_run.sh` covers the Acceptance items:
  the dry-run skips and rewrites, the committed schema and version, the absence of
  any settings write, a planted settings file left byte-identical by a real
  deploy, and the guardrail envelope run. It exercises the settings-map helper
  directly through the script's `DEPLOYMENT_SH_SKIP_MAIN` sourcing path: the JSONC
  normalization, the entry merge with a foreign entry and an unrelated key
  preserved, the recorded prior, the restore and `@absent` removal, and the
  unparseable-file skip.
- Project scope leaves the user settings alone and writes no settings key; a
  project deploy ships the config and the script into `.github/hooks`.

The operator's retraction command for the already-deployed strays is unchanged.
It removes what the log records for the global scope and deploys again from this
checkout:

```bash
./deployment/deployment.sh --uninstall --global
./deployment/deployment.sh --global
```

That clears `~/.copilot/hooks` of every logged hook config whose basename is not
`vscode-hooks*`, which is the set the `vscode` filter now skips.
