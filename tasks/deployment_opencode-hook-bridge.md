---
description: Deploy the charter_guardrail hook to OpenCode via a TS bridge plugin that registers a V2 permission.evaluate or tool.execute.before hook and calls the shared bash script; OpenCode has no hook config.
scope: deployment
created: 2026-07-23T17:48:14Z
updated: 2026-11-09T10:01:28Z
status: open
reported-by: Andreas Hoffmann
---

# Deploy OpenCode hooks via a bridge plugin

## Goal

Give the `opencode` deploy target a working hook path so the repo's one hook, the CHARTER.md guardrail in `plugins/ai_dev/hooks/charter_guardrail.sh`, activates under OpenCode, reusing the existing bash script rather than reimplementing its policy. Because OpenCode has no declarative hook configuration, this ships a small TypeScript **bridge plugin** that registers an OpenCode V2 hook and calls the shared script, and extends `deployment/deployment.sh` to deploy both the bridge and the script into OpenCode's directories.

**OpenCode V2 target.** The bridge targets the V2 plugin contract, verified against 2.2.5 on 5 November 2026. V1's plugin API does not run in V2: V1 exported an async function returning a hooks object and blocked by throwing from `tool.execute.before`, while V2 registers hooks on a domain through a setup context, `await ctx.permission.hook("evaluate", ...)`, `ctx.tool.hook("execute.before", ...)`, and `ctx.shell.hook("create.before", ...)`, and disposes the returned registration. One package can serve both generations by default-exporting an object with a V1 `server()` and a V2 `setup()`.

Choose `permission.evaluate` as the primary hook. It runs after configured rules are evaluated and before the action or a permission prompt, receives `action`, `resources`, `sessionID`, and `metadata`, and can set `effect` to `allow`, `ask`, or `deny` plus a `message`. It also carries the one asymmetry that decides the design: it runs for `allow` and `ask` decisions, but **an explicit configured `deny` is final and never invokes the hook**. The guardrail is a conditional block rather than an unconditional one, so it starts from an `ask` or `allow` posture and returns `deny` for a CHARTER.md mutation on a non-guardrail branch. Keep `tool.hook("execute.before")` only as a secondary arm if `permission.evaluate` proves insufficient, since it sees the tool input but not the resolved permission decision.

The user-visible outcome is that on OpenCode, an attempt to mutate CHARTER.md through an edit, a write, or a shell command is blocked by the same guard that already runs on Claude and Codex, with the block decision produced by the one shared `charter_guardrail.sh` so the policy has a single source of truth. This carries a known, documented limitation particular to OpenCode (subagent bypass, below) that makes the guarantee weaker than on the other harnesses.

## Context

This task builds on the `opencode` deploy target created by [deployment_opencode-target.md](archive/deployment_opencode-target.md): it consumes that target's `OPENCODE_DIR`, its `opencode` entry in `VALID_TARGETS`/`ALL_APP_TARGETS`, and the `opencode` arms already added to `install_for_app()`. It must follow that task.

**Why OpenCode needs a different mechanism.** The script deploys hooks to the other harnesses through plugin delivery where the harness supports it and entry-level merges where it does not: the `claude`, `codex`, `cursor`, `antigravity`, and `vscode` arms merge or copy their own hook config through `merge_hook_entries` with an `@entries:` manifest, and each copies the `.sh` into the tool's `hooks/` dir. Project scope uses a relative `.claude/hooks` path for portability, while Codex uses an absolute path in both scopes. None of the shipped arms names a `claude-code-hooks*.json` or `cursor-hooks*.json` file. OpenCode has **no equivalent**: no `settings.json` hooks key and no `hooks.json`. Its hooks are code: a plugin, loaded from `~/.config/opencode/plugins/` (or project `.opencode/plugins/`) at startup and executed by OpenCode's embedded Bun runtime, so a local `.ts` file needs no npm publish and no build step. This is confirmed by OpenCode's official plugin and permissions docs (opencode.ai/docs/plugins, /permissions); the `harness_portability` skill carries the general knowledge as background.

**The shared script's contract.** `charter_guardrail.sh` reads a JSON envelope on stdin holding `tool_name`, `tool_input` (carrying `file_path` for edits or `command` for shell), and `cwd`, inspects the three mutation surfaces (a direct file edit, a Codex `apply_patch` envelope, and a shell command that redirects/moves/removes CHARTER.md), and **blocks by `exit 2`** with a message on stderr, allowing read-only references through. It is already harness-aware for Claude, Codex, and Antigravity; the bridge's `{tool_name, tool_input, cwd}` envelope omits Antigravity's `toolCall`, so the script takes the generic branch. The bridge reuses it unchanged.

**The bridge.** A V2 plugin is one package whose server part default-exports `Plugin.define({ id, async setup(ctx) })`; `setup` registers a hook on a domain and receives the hook event. The bridge registers `ctx.permission.hook("evaluate", ...)`, maps the event's `action` and `resources` onto the script's `{tool_name, tool_input, cwd}` stdin envelope, pipes it to the deployed `charter_guardrail.sh` through Bun's `$` shell, and sets `event.effect = "deny"` with `event.message` from the script's stderr when the script exits non-zero. Setting `effect` is the V2 block mechanism; a V1-style throw is not the contract. The bridge source is added to the repo beside the script it wires, for example `plugins/ai_dev/hooks/opencode-charter-guardrail.ts`, the same way `codex-custom-deploy-hooks.json` sits beside the `.sh` today.

**OpenCode-specific caveats to encode and document** (not defects to fix here):

- **Subagent bypass.** Whether a hook fires inside a subagent spawned through the subagent tool is unverified on V2, and the V1 report (OpenCode issue #5894) recorded that `tool.execute.before` did not intercept subagent tool calls, so an agent could route a CHARTER.md edit through a subagent and slip past the guard. Confirm this on 2.2.5 before relying on the bridge for a hard block; if it still holds, state it in the deploy docs and the wiki pages named in Approach as a materially weaker guarantee than Claude/Codex.
- **No `apply_patch`, lowercase tool names.** OpenCode's tools are lowercase `edit`/`write`/`bash`, and it has no `apply_patch` tool (that surface is Codex-only), so the `apply_patch` arm of the script never triggers under OpenCode.
- **`permission.evaluate` skips configured denies.** An explicit configured `deny` is final and never invokes the hook, so the guard must be mounted behind an `ask` or `allow` posture. OpenCode's native permission rules can deny a path declaratively but cannot express the guard's "unless on a charter/guardrail branch" conditional, which is why the plugin bridge is required at all.
- **V2 tool vocabulary.** The permission action for shell is `shell`, not `bash`, and `edit` gates `edit`, `write`, and `patch` alike, so the bridge maps actions rather than matching tool names one-for-one.

**Deploy wiring.** The `hook)` case in `install_for_app()` opens with an extension gate that proceeds only for `sh|json` and skips anything else. A `.ts` bridge is a new extension: extend that gate to also admit `ts`, then add an `opencode` arm that routes the `.ts` into `${app_dir}/plugins/` and the `.sh` into `${app_dir}/hooks/`, while the existing `claude`/`codex`/`cursor` arms skip a `.ts` source. The `vscode` arm copies every admitted file, so it needs an explicit `.ts` skip or filename filter. The deployed bridge must reference the deployed script by a path it can resolve at runtime (the `~/.config/opencode/hooks/charter_guardrail.sh` location in global mode, or the project `.opencode/hooks/` location under `--project-dir`), mirroring how the `claude` arm rewrites `./hooks/` command paths to their deployed absolute location.

## Approach

Add the bridge source `plugins/ai_dev/hooks/opencode-charter-guardrail.ts` that default-exports a `Plugin.define({ id, setup })` whose `setup` registers `ctx.permission.hook("evaluate", ...)`, maps the event's `action` and `resources` onto the `{tool_name, tool_input, cwd}` stdin envelope, runs the deployed `charter_guardrail.sh` via Bun's `$` shell, and sets `event.effect = "deny"` with the captured stderr as `event.message` when the script exits non-zero. Keep the guardrail policy entirely in the shared `.sh`; the bridge only marshals and relays.

Extend the `hook)` case extension gate in `install_for_app()` to admit `ts` alongside `sh|json`, and add an `opencode` arm that copies a `.ts` hook source into `${app_dir}/plugins/` and a `.sh` hook source into `${app_dir}/hooks/`, with the deployed bridge pointing at the deployed script's path (global vs project). Leave the other targets' arms to skip a `.ts` source; add an explicit `.ts` skip to `vscode`, which otherwise copies every admitted file.

Document the OpenCode hook mechanism in `deployment/README.md` as its own row, a bridge plugin plus the shared script distinct from the entry-merge targets, including the subagent-bypass limitation, and record the same caveats on the wiki's [SST OpenCode](../wiki/entities/sst-opencode.md) and [hook surface portability](../wiki/concepts/hook-surface-portability.md) pages so future hook work accounts for them.

**Out of scope:**

- This task adds no new guardrail policy and does not modify `charter_guardrail.sh`'s logic; it reuses the script as-is and only bridges it.
- It does not attempt to close the subagent-bypass gap (OpenCode issue #5894, still unverified on V2) or to express the guard through OpenCode's native permission rules; both are documented as accepted limitations.

## Acceptance

- `plugins/ai_dev/hooks/opencode-charter-guardrail.ts` exists and default-exports a `Plugin.define({ id, setup })` whose `setup` registers `ctx.permission.hook("evaluate", ...)`, builds a `{tool_name, tool_input, cwd}` envelope from the event's `action` and `resources`, invokes the deployed `charter_guardrail.sh`, and sets `event.effect = "deny"` on a non-zero exit, verified by reading the file.
- The shared policy still blocks through the reused script, proven harness-independently: piping a CHARTER.md-mutating envelope (e.g. a `write`/`edit` whose `tool_input.file_path` is the repo-root `CHARTER.md`) into `charter_guardrail.sh` on a non-guardrail branch exits non-zero, and a read-only envelope (e.g. a `cat CHARTER.md` command) exits zero.
- The `hook)` case extension gate in `install_for_app()` admits a `ts` source (a `.ts` hook is no longer skipped as "not an executable hook or hook config").
- A deploy into a throwaway `--project-dir` scratch directory with `--target opencode` places the bridge at `<scratch>/.opencode/plugins/opencode-charter-guardrail.ts` and the script at `<scratch>/.opencode/hooks/charter_guardrail.sh`, both real files, and the deployed bridge references the deployed script's `.opencode/hooks/` path.
- The same scratch deploy with `--target claude,codex,cursor,vscode` does **not** place `opencode-charter-guardrail.ts` anywhere under `.claude`, `.codex`, `.cursor`, or the Copilot hook tree; a grep for the bridge filename in those trees finds nothing, confirming non-OpenCode targets skip the `.ts` source.
- `--uninstall --target opencode` scoped to the scratch deployment removes both the deployed bridge and the deployed script recorded in the log.
- `deployment/README.md` documents the OpenCode hook path as a bridge plugin plus the shared script, distinct from the JSON-merge rows, and states the subagent-bypass limitation; the wiki's SST OpenCode and hook surface portability pages record the OpenCode hook model and the same caveats.
