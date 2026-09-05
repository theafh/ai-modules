---
description: Deploy the charter_guardrail hook to OpenCode via a bridge plugin, since OpenCode has no declarative hook config. A TS plugin maps tool.execute.before to the shared bash script.
scope: deployment
created: 2026-07-23T19:48:14
updated: 2026-09-05T21:26:04
status: open
reported-by: Andreas Hoffmann
---

# Deploy OpenCode hooks via a bridge plugin

## Goal

Give the `opencode` deploy target a working hook path so the repo's one hook, the CHARTER.md guardrail in `plugins/ai_dev/hooks/charter_guardrail.sh`, activates under OpenCode, reusing the existing bash script rather than reimplementing its policy. Because OpenCode has no declarative hook configuration, this ships a small TypeScript **bridge plugin** that maps OpenCode's `tool.execute.before` event onto the shared script, and extends `deployment/deployment.sh` to deploy both the bridge and the script into OpenCode's directories.

The user-visible outcome is that on OpenCode, an attempt to mutate CHARTER.md through an edit, a write, or a shell command is blocked by the same guard that already runs on Claude and Codex, with the block decision produced by the one shared `charter_guardrail.sh` so the policy has a single source of truth. This carries a known, documented limitation particular to OpenCode (subagent bypass, below) that makes the guarantee weaker than on the other harnesses.

## Context

This task builds on the `opencode` deploy target created by [deployment_opencode-target.md](archive/deployment_opencode-target.md): it consumes that target's `OPENCODE_DIR`, its `opencode` entry in `VALID_TARGETS`/`ALL_APP_TARGETS`, and the `opencode` arms already added to `install_for_app()`. It must follow that task.

**Why OpenCode needs a different mechanism.** The script deploys hooks to the other harnesses declaratively: the `claude` arm of the `hook)` case in `install_for_app()` merges the `hooks` key from a `claude-code-hooks*.json` config into `~/.claude/settings.json` (rewriting relative `./hooks/` command paths to absolute), the `codex` arm merges into `~/.codex/hooks.json`, and the `cursor` arm copies a `cursor-hooks*.json`; all three then copy the `.sh` into the tool's `hooks/` dir. OpenCode has **no equivalent**: no `settings.json` hooks key and no `hooks.json`. Its hooks are code: a plugin, loaded from `~/.config/opencode/plugins/` (or project `.opencode/plugins/`) at startup and executed by OpenCode's embedded Bun runtime, so a local `.ts` file needs no npm publish and no build step. This is confirmed by OpenCode's official plugin and permissions docs (opencode.ai/docs/plugins, /permissions); the `harness_portability` skill carries the general knowledge as background.

**The shared script's contract.** `charter_guardrail.sh` reads a JSON envelope on stdin holding `tool_name`, `tool_input` (carrying `file_path` for edits or `command` for shell), and `cwd`, inspects the three mutation surfaces (a direct file edit, a Codex `apply_patch` envelope, and a shell command that redirects/moves/removes CHARTER.md), and **blocks by `exit 2`** with a message on stderr, allowing read-only references through. It is already harness-aware for Claude and Codex. The bridge reuses it unchanged.

**The bridge.** A plugin exports an async function that returns a hooks object; `tool.execute.before` fires before a tool runs, receiving the tool name and the tool arguments, and **throwing from it aborts the call**, which is OpenCode's block mechanism (verified against issue tracker discussion; re-confirm on the installed version). The bridge, on a tool in `{edit, write, bash}`, builds the same stdin envelope from the OpenCode tool arguments and pipes it to the deployed `charter_guardrail.sh` through Bun's `$` shell, throwing the script's stderr on a non-zero exit. The bridge source is added to the repo beside the script it wires, for example `plugins/ai_dev/hooks/opencode-charter-guardrail.ts`, the same way `codex-custom-deploy-hooks.json` sits beside the `.sh` today.

**OpenCode-specific caveats to encode and document** (not defects to fix here):

- **Subagent bypass.** `tool.execute.before` intercepts tool calls from the primary agent but not from subagents spawned via the task tool (OpenCode issue #5894), so an agent can route a CHARTER.md edit through a subagent and slip past the guard. For a hard-block guardrail this is a materially weaker guarantee than Claude/Codex and must be stated in the deploy docs and the skill.
- **No `apply_patch`, lowercase tool names.** OpenCode's tools are lowercase `edit`/`write`/`bash`, and it has no `apply_patch` tool (that surface is Codex-only), so the bridge matches `{edit, write, bash}` and the `apply_patch` arm of the script simply never triggers under OpenCode.
- **`permission.ask` is inert.** OpenCode's `permission.ask` plugin hook is defined but never fired (issue #7006), so interception must go through `tool.execute.before`, not the permission hook. OpenCode's native `permission` config can deny a path declaratively but cannot express the guard's "unless on a charter/guardrail branch" conditional, which is why the plugin bridge is required.

**Deploy wiring.** The `hook)` case in `install_for_app()` opens with an extension gate that proceeds only for `sh|json` and skips anything else. A `.ts` bridge is a new extension: extend that gate to also admit `ts`, then add an `opencode` arm that routes the `.ts` into `${app_dir}/plugins/` and the `.sh` into `${app_dir}/hooks/`, while the existing `claude`/`codex`/`cursor`/`vscode` arms skip a `.ts` source (they already skip files that are not their own hook config). The deployed bridge must reference the deployed script by a path it can resolve at runtime (the `~/.config/opencode/hooks/charter_guardrail.sh` location in global mode, or the project `.opencode/hooks/` location under `--project-dir`), mirroring how the `claude` arm rewrites `./hooks/` command paths to their deployed absolute location.

## Approach

Add the bridge source `plugins/ai_dev/hooks/opencode-charter-guardrail.ts` that exports an OpenCode plugin whose `tool.execute.before` handler, for a tool name in `{edit, write, bash}`, assembles the `{tool_name, tool_input, cwd}` stdin envelope from the OpenCode tool arguments, runs the deployed `charter_guardrail.sh` via Bun's `$` shell, and throws the captured stderr when the script exits non-zero so OpenCode aborts the tool call. Keep the guardrail policy entirely in the shared `.sh`; the bridge only marshals and relays.

Extend the `hook)` case extension gate in `install_for_app()` to admit `ts` alongside `sh|json`, and add an `opencode` arm that copies a `.ts` hook source into `${app_dir}/plugins/` and a `.sh` hook source into `${app_dir}/hooks/`, with the deployed bridge pointing at the deployed script's path (global vs project). Leave the other targets' arms to skip a `.ts` source.

Document the OpenCode hook mechanism in `deployment/README.md` as its own row, a bridge plugin plus the shared script distinct from the JSON-merge targets, including the subagent-bypass limitation, and record the same caveats on the wiki's [SST OpenCode](../wiki/entities/sst-opencode.md) and [hook surface portability](../wiki/concepts/hook-surface-portability.md) pages so future hook work accounts for them.

**Out of scope:**

- This task adds no new guardrail policy and does not modify `charter_guardrail.sh`'s logic; it reuses the script as-is and only bridges it.
- It does not attempt to close the subagent-bypass gap (OpenCode issue #5894) or work around the inert `permission.ask` hook (issue #7006); both are documented as accepted limitations.
- The `opencode` target infrastructure (target dirs, `VALID_TARGETS`, file-artefact arms) is owned by [deployment_opencode-target.md](archive/deployment_opencode-target.md).

## Acceptance

- `plugins/ai_dev/hooks/opencode-charter-guardrail.ts` exists and exports an OpenCode plugin whose `tool.execute.before` handler acts only on tool names in `{edit, write, bash}`, builds a `{tool_name, tool_input, cwd}` envelope, invokes the deployed `charter_guardrail.sh`, and throws on a non-zero exit, verified by reading the file.
- The shared policy still blocks through the reused script, proven harness-independently: piping a CHARTER.md-mutating envelope (e.g. a `write`/`edit` whose `tool_input.file_path` is the repo-root `CHARTER.md`) into `charter_guardrail.sh` on a non-guardrail branch exits non-zero, and a read-only envelope (e.g. a `cat CHARTER.md` command) exits zero.
- The `hook)` case extension gate in `install_for_app()` admits a `ts` source (a `.ts` hook is no longer skipped as "not an executable hook or hook config").
- A deploy into a throwaway `--project-dir` scratch directory with `--target opencode` places the bridge at `<scratch>/.opencode/plugins/opencode-charter-guardrail.ts` and the script at `<scratch>/.opencode/hooks/charter_guardrail.sh`, both real files, and the deployed bridge references the deployed script's `.opencode/hooks/` path.
- The same scratch deploy with `--target claude,codex,cursor` does **not** place `opencode-charter-guardrail.ts` anywhere under `.claude`, `.codex`, or `.cursor`; a grep for the bridge filename in those trees finds nothing, confirming non-OpenCode targets skip the `.ts` source.
- `--uninstall --target opencode` scoped to the scratch deployment removes both the deployed bridge and the deployed script recorded in the log.
- `deployment/README.md` documents the OpenCode hook path as a bridge plugin plus the shared script, distinct from the JSON-merge rows, and states the subagent-bypass limitation; the wiki's [SST OpenCode](../wiki/entities/sst-opencode.md) and [hook surface portability](../wiki/concepts/hook-surface-portability.md) pages record the OpenCode hook model and the same caveats.
