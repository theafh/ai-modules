---
description: Retire the Gemini CLI deploy target in deployment.sh and correct the Antigravity target so it deploys skills and (sub)agents into ~/.gemini/config and .agents, ideally with hooks.
scope: deployment
created: 2026-07-24T12:54:02
updated: 2026-07-24T12:54:02
status: open
reported-by: Andreas Hoffmann
---

# Retire the Gemini CLI deploy target and correct the Antigravity target

## Goal

Update `deployment/deployment.sh` (and its `deployment.conf` and `deployment/README.md`) to (a) **retire the `gemini` deploy target** because consumer Gemini CLI is retired, and (b) **correct and expand the `antigravity` target** so it deploys into Antigravity's real shared config tree and supports **skills** and **(sub)agents**, and — ideally — **hooks**.

The user-visible outcome is that `./deployment/deployment.sh --target antigravity` (global or `--project-dir`) lands each skill as a real `SKILL.md` directory tree and each agent as a file whose frontmatter is transformed into Antigravity's schema, in the directories Antigravity actually reads (`~/.gemini/config/…` globally, `.agents/…` per project) so one deploy reaches Antigravity's IDE, CLI, and 2.0 app at once; and that `gemini` is no longer an accepted target, its dead generators and config are gone, and the docs reflect both changes.

## Context

The verified Antigravity facts, their sources, and the frontmatter-tolerance finding this task's agent transform depends on are owned by [ai-dev_harness-portability-antigravity-gemini-retire.md](ai-dev_harness-portability-antigravity-gemini-retire.md); this task consumes them and should follow it, or re-verify the paths against official `antigravity.google` docs if built first. The deploy-relevant facts are restated here so this file stands alone.

**Why retire Gemini.** Consumer Gemini CLI was retired on 18 June 2026 (`410 Gone`; only paid/enterprise API-key access survives), and Google's live surface is Antigravity, which shares the `~/.gemini` tree. Deploying to live consumer Gemini CLI no longer reaches a working tool, so the `gemini` target is removed rather than maintained.

**What Antigravity actually reads** (one shared tree across IDE/CLI/2.0): global `~/.gemini/config/{skills,agents,plugins}/` plus `~/.gemini/config/{mcp_config.json,hooks.json}`; workspace `.agents/{skills,agents,rules,plugins}/` plus `.agents/{mcp_config.json,hooks.json}`. Skills are `skills/<name>/SKILL.md` directory trees under the Agent Skills open standard (near drop-in with this repo's skills); agents are `agents/<name>.md`; hooks are a declarative `hooks.json`. The `~/.gemini/antigravity` and `~/.gemini/antigravity-cli` directories the script currently targets are **transcript/artifact output paths, not config** — that is the core breakage to fix.

**Current state in `deployment/deployment.sh`** (reference each site by its symbol, not a line number):

- `VALID_TARGETS` lists `vscode,claude,cursor,codex,gemini,antigravity`. `rewrite_agent_frontmatter` derives its known vendor prefixes from `VALID_TARGETS`, so removing `gemini` also removes `GEMINI_`-prefix handling — safe today, since no agent source uses a `GEMINI_`-prefixed field.
- The target-directories block (the `if [[ -n "$PROJECT_DIR" ]]` … `else` split) sets `GEMINI_DIR="${HOME_DIR}/.gemini"` and `ANTIGRAVITY_DIR="${HOME_DIR}/.gemini/antigravity"` globally, and leaves both empty in project mode with a comment that Gemini and Antigravity have no project convention. Antigravity **does** have a project convention (`.agents/`), so that assumption is wrong.
- `ALL_APP_TARGETS` carries `gemini|Gemini CLI|${GEMINI_DIR}` and `antigravity|Antigravity|${ANTIGRAVITY_DIR}`.
- In `install_for_app()`, the `command` case has a `gemini` arm calling `generate_toml_command` (→ `${app_dir}/commands/<name>.toml`) and an `antigravity` arm calling `generate_antigravity_workflow` (→ `${app_dir}/workflows/<name>.md`); the `agent` case dispatches to `generate_gemini_agent` for `gemini` (and `generate_toml_agent` for `codex`) and has **no** `antigravity` arm — Antigravity agent generation is net-new.
- Gemini-only helpers `generate_toml_command`, `generate_gemini_agent`, `map_gemini_tool_name`, and `GEMINI_AGENT_ALLOWED_KEYS` become dead once the `gemini` target is gone; confirm no other caller before deleting.
- `deployment/deployment.conf` has a `#gemini` and a `#antigravity` section (each `disallow:*legacy*`) and names both in its header comment; the script header comment and `--target` help text enumerate `gemini` and `antigravity`; `deployment/README.md` carries Gemini/Antigravity rows in its Target Layout and Generated Formats tables.

**The Antigravity agent transform.** The repo's agents are Claude-style markdown; the script already generates target-specific variants (`generate_toml_agent` for Codex, `generate_gemini_agent` for Gemini) that first run `rewrite_agent_frontmatter` then emit the target's schema. A new `generate_antigravity_agent` follows that shape, mapping to Antigravity's native frontmatter: a `tools` array of Antigravity tool names (`read_file`, `edit_file`, …), `model` as a tier (`inherit`|`flash_lite`|`flash`|`pro`, with an `inherit` sentinel or omission for session inheritance), `commandExecutionPolicy` plus `subagent: true` for the repo's `auto_*` subagents, and read-only roles expressed through the `tools` allowlist and `commandExecutionPolicy`. **How aggressive this transform must be depends on the frontmatter-tolerance finding in the linked skill task**: if Antigravity's loader tolerates unknown keys, a light vendor-prefix-resolving passthrough suffices; if it rejects them like the retired Gemini CLI loader did, the transform must whitelist Antigravity's keys the way `generate_gemini_agent` does today.

**Hooks (the ideal tier).** Antigravity hooks are declarative — a `hooks.json` (events `PreToolUse`/`PostToolUse`/`PreInvocation`/`PostInvocation`/`Stop`, stdin/stdout JSON with camelCase fields, a `PreToolUse` `decision` of `allow`/`deny`/`ask`/`force_ask`) — so they resemble the Claude/Codex JSON-config arms the script already has more than OpenCode's code bridge in [deployment_opencode-hook-bridge.md](deployment_opencode-hook-bridge.md). Wiring the repo's one hook (`charter_guardrail.sh`) here means emitting/merging an Antigravity `hooks.json` and copying the script, but the shared script currently blocks via `exit 2` for Claude/Codex, whereas Antigravity expects a JSON `decision` on stdout with a camelCase input envelope — so `charter_guardrail.sh` needs Antigravity-awareness, and the size of that adaptation is the open question below.

**Shared surfaces.** [deployment_opencode-target.md](archive/deployment_opencode-target.md) co-edits `VALID_TARGETS`, `ALL_APP_TARGETS`, the target-directories block, and the `install_for_app()` cases, and its prose enumerates "Gemini" as an existing target — whichever task lands second reconciles that shared region and prose. [deployment_relocate-state-to-home.md](deployment_relocate-state-to-home.md) co-edits `deployment.sh` and `deployment.conf`. The copy-based (non-symlink) deploy model this task's skill copy follows is established by [deployment_copy-not-symlink.md](archive/deployment_copy-not-symlink.md).

## Approach

**Retire Gemini.** Remove `gemini` from `VALID_TARGETS`; drop the `gemini|Gemini CLI|…` row from `ALL_APP_TARGETS` and the `GEMINI_DIR` assignment; delete the `gemini` arms from the `command` and `agent` cases in `install_for_app()`; delete the now-dead `generate_toml_command`, `generate_gemini_agent`, `map_gemini_tool_name`, and `GEMINI_AGENT_ALLOWED_KEYS` after confirming no other caller. Remove the `#gemini` section from `deployment.conf`, and strike `gemini`/`Gemini CLI` from the script header comment, the `--target` help text, and `deployment/README.md`.

**Correct and expand Antigravity.** Set `ANTIGRAVITY_DIR` to `${HOME_DIR}/.gemini/config` in the global branch and `${PROJECT_DIR}/.agents` in the project branch (stop skipping Antigravity in project mode). In `install_for_app()`, add or fix `antigravity` arms so: the `skill` case copies the directory tree to `${app_dir}/skills/<name>/` (mirroring the copy-based `claude`/`opencode` skill branch); the `agent` case calls a new `generate_antigravity_agent` writing `${app_dir}/agents/<name>.md`; and the `command` case writes workflows to Antigravity's verified workflows location (correcting `generate_antigravity_workflow`'s current `${app_dir}/workflows/` target if verification places it elsewhere under the shared tree). Give the `~/.gemini/config` backup a self-describing managed-backup name rather than a bare `config_<timestamp>`. Refresh the Antigravity rows in `deployment.conf`, the script header/help, and the `deployment/README.md` Target Layout and Generated Formats tables.

**Hooks (ideal tier).** If pursued here, extend the `hook` case with an `antigravity` arm that emits/merges an Antigravity `hooks.json` (a `PreToolUse` matcher invoking the deployed `charter_guardrail.sh`) into `${app_dir}` and copies the script, and teach `charter_guardrail.sh` to detect Antigravity and speak its camelCase envelope + `decision` JSON contract while keeping one shared policy source. Resolve the open decision below before committing to scope.

**Out of scope:**

- The `harness_portability` skill's Antigravity/Gemini documentation is owned by [ai-dev_harness-portability-antigravity-gemini-retire.md](ai-dev_harness-portability-antigravity-gemini-retire.md); this task edits only the deployment surface.
- OpenCode's target and hook bridge stay owned by [deployment_opencode-target.md](archive/deployment_opencode-target.md) and [deployment_opencode-hook-bridge.md](deployment_opencode-hook-bridge.md).
- Relocating the deploy conf/log into `$HOME` stays owned by [deployment_relocate-state-to-home.md](deployment_relocate-state-to-home.md).

Open decision: whether hook deployment ships inside this task or splits to a follow-on. Default — attempt it here, since Antigravity hooks are declarative and close to the existing JSON-config arms; split to a follow-on task (mirroring the OpenCode target/hook-bridge split) only if the `charter_guardrail.sh` Antigravity-awareness proves to exceed a straightforward `hooks.json` emit plus a stdin-envelope/`decision`-output adaptation. An implementer takes the default unless the script adaptation balloons.

## Acceptance

- `./deployment/deployment.sh --target gemini --dry-run` is rejected with an "Unknown deploy target" abort, and a grep of `deployment.sh` finds no `gemini`/`Gemini CLI` in `VALID_TARGETS`, `ALL_APP_TARGETS`, the target-directories block, the header comment, or the `--target` help text.
- `generate_toml_command`, `generate_gemini_agent`, `map_gemini_tool_name`, and `GEMINI_AGENT_ALLOWED_KEYS` are absent from `deployment.sh`, and a grep confirms no remaining caller references them; `deployment.conf` has no `#gemini` section.
- `./deployment/deployment.sh --target antigravity --global --dry-run` shows the Antigravity base dir resolving to `~/.gemini/config`, not `~/.gemini/antigravity`.
- A deploy into a throwaway `--project-dir` scratch directory with `--target antigravity` produces `<scratch>/.agents/skills/<skill>/SKILL.md` as a real directory tree (`test -d` true, `test -L` false) and `<scratch>/.agents/agents/<agent>.md` as a real file — proving Antigravity is no longer skipped in project mode.
- The generated `<scratch>/.agents/agents/<agent>.md` carries Antigravity-native frontmatter: a `tools` array of Antigravity tool names, a `model` tier value (or omission for `inherit`), and — for a repo `auto_*` subagent — `subagent: true`; a read-only source agent restricts via the `tools` allowlist and `commandExecutionPolicy` rather than a Claude `tools:` comma-string — verified by reading the file.
- Activating `antigravity` in global mode backs up an existing `~/.gemini/config` to a managed backup named for Antigravity (not a bare `~/config_<timestamp>`) — confirmed via `--dry-run` backup naming.
- `--uninstall --target antigravity` scoped to the scratch deployment removes the copied skill directory and agent file recorded in the log, leaving those paths absent.
- `deployment/README.md` Target Layout and Generated Formats tables have no Gemini rows and carry corrected Antigravity rows naming its `~/.gemini/config` global and `.agents/` project paths and the agent-generation transform; a grep of the README for `gemini` returns nothing and for `antigravity` finds the corrected rows.
- Hook tier, when included per the open decision: a `--target antigravity` scratch deploy places an Antigravity `hooks.json` referencing the deployed `charter_guardrail.sh` under `<scratch>/.agents/`, and piping an Antigravity-style camelCase envelope for a CHARTER.md mutation into the script yields a `deny` decision while a read-only envelope yields `allow` — proving the shared script speaks Antigravity's contract. When the decision splits hooks to a follow-on, this item moves to that task and a one-line deferral pointer replaces it here.
