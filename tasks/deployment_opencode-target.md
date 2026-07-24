---
description: Add an `opencode` deploy target to deployment.sh so skills, agents, and commands copy into OpenCode's own config dirs, with an agent-frontmatter transform for OpenCode's schema.
scope: deployment
created: 2026-07-23T19:48:14
updated: 2026-07-23T19:48:14
status: open
reported-by: Andreas Hoffmann
---

# Add an OpenCode deploy target for skills, agents, and commands

## Goal

Extend `deployment/deployment.sh` with a new `opencode` deploy target so the repo's file artefacts — skills, agents, and commands — copy into OpenCode's own configuration directories, the same way the script already serves Claude, Cursor, Codex, Gemini, and Antigravity. After the change, `./deployment/deployment.sh --target opencode` (global or `--project-dir`) lands each skill as a real directory, each command as a markdown file, and each agent as a file whose frontmatter is transformed into OpenCode's agent schema.

The user-visible outcome is that OpenCode gains the repo's curated agents and commands as first-class OpenCode artefacts. This matters because of how OpenCode discovers artefacts: it reads **skills** from foreign directories (`~/.claude/skills/`, `~/.agents/skills/`) as well as its own, but it reads **agents** and **commands** only from its own directories — never from `.claude/agents` or `.claude/commands`. So the repo's skills already surface in OpenCode today through the existing Claude deploy, whereas its agents and commands are the genuinely new capability this target unlocks. A dedicated OpenCode **skills** copy becomes load-bearing only once an operator isolates OpenCode from the Claude directories (the `OPENCODE_DISABLE_CLAUDE_CODE=1` environment variable, operator-set, stops OpenCode reading `~/.claude` and `~/.agents`), at which point OpenCode shows only the curated set deployed here.

## Context

OpenCode's config lives in a global directory `~/.config/opencode/` and a per-project directory `.opencode/`, each holding plural subdirectories `skills/`, `agents/`, `commands/`, and `plugins/` (singular names are accepted for back-compat; deploy to the plural, canonical form). Skills are `skills/<name>/SKILL.md` directory trees, commands are `commands/<name>.md`, and agents are `agents/<name>.md`. This is confirmed by OpenCode's official docs (opencode.ai/docs/config, /skills, /agents, /commands); the `harness_portability` skill also carries the general OpenCode-compatibility knowledge as background.

The deploy mechanism to extend is `install_for_app()` in `deployment/deployment.sh`, which switches on `app_id` inside each artifact-type case (`command`, `skill`, `agent`, `hook`). Deployment is copy-based today — the symlink mode was removed and audited in [deployment_copy-not-symlink.md](deployment_copy-not-symlink.md) — so a new target copies like the existing `claude`/`cursor` branches rather than linking.

Concrete wiring points, all in `deployment/deployment.sh`:

- **`VALID_TARGETS`** — the comma-separated allowlist that gates `--target`. Adding `opencode` here also enables a `#opencode` section in `deployment.conf` and lights up `OPENCODE_`-prefixed agent frontmatter for free, because `rewrite_agent_frontmatter` derives its known vendor prefixes from `VALID_TARGETS`.
- **The target-directories block** — the `if [[ -n "$PROJECT_DIR" ]]` … `else` block that assigns `CLAUDE_DIR="${HOME_DIR}/.claude"` and its siblings. OpenCode breaks the `~/.<tool>` pattern every other target follows: its global dir is `${HOME_DIR}/.config/opencode`, and its project dir is `${PROJECT_DIR}/.opencode`. Set `OPENCODE_DIR` in **both** branches (unlike Gemini/Antigravity, OpenCode has a real project convention, so project-dir mode must not skip it).
- **`ALL_APP_TARGETS`** — the `id|label|base_dir` list; add `opencode|OpenCode|${OPENCODE_DIR}`.
- **`install_for_app()` cases** — add an `opencode` arm to the `command`, `skill`, and `agent` cases. `command` copies the `.md` and `skill` copies the directory, both mirroring the default (`claude`) branch via `copy_path_with_replacements`. `agent` needs a transform (below), so it calls a new generator rather than a straight copy.
- **Backup handling** — `backup_app_dir` names a backup from `basename(app_dir)`, and `is_managed_backup_path` requires the backup to sit directly in `$HOME`. For `~/.config/opencode` the basename is `opencode`, producing `~/opencode_<timestamp>`, which reads as unrelated to OpenCode. Apply a backup-name override (the same mechanism the VS Code prompts dir uses via the `path|name` `backup_roots` entries in the main backup loop and in `clear_backups_for_active_targets`) so the backup lands at a self-describing name such as `~/.opencode-config_<timestamp>`.

The agent transform is the one non-mechanical piece. The repo's agents are Claude-style markdown with frontmatter (`name`, `description`, `model`, sometimes `tools`, and a `readonly`/vendor-prefixed convention), and the script already generates target-specific agent variants twice — `generate_toml_agent` for Codex and `generate_gemini_agent` for Gemini — each of which first runs `rewrite_agent_frontmatter` to resolve vendor prefixes, then emits the target's schema. A new `generate_opencode_agent` follows that same shape. OpenCode's agent frontmatter differs from Claude's in three ways that the transform must bridge:

- **`mode`** — OpenCode registers a subagent only when frontmatter carries `mode: subagent`. The repo's `auto_*` agents are subagents, so the transform emits `mode: subagent`.
- **`model`** — OpenCode expects `provider/model-id` and inherits the session model when the key is absent. Map a `model: inherit` sentinel to key omission (as the Codex generator already does for its own inheritance), and carry a concrete pin through, prefixing the provider when the source id lacks one.
- **read-only / tools** — OpenCode gates tools through a `permission` object (`permission: { edit: "deny", write: "deny", bash: "deny" }`) or a boolean `tools` map (`tools: { write: false, edit: false }`). Translate a read-only source agent (the `readonly: true` convention the Codex path maps to `sandbox_mode = "read-only"`) into `permission` denies, and map an explicit Claude `tools:` comma-string to OpenCode's lowercase tool names as a `tools` object, mirroring the name-mapping approach in `generate_gemini_agent` (`Read`→`read`, `Grep`→`grep`, `Glob`→`glob`, `Bash`→`bash`, `Edit`→`edit`, `Write`→`write`, `WebFetch`→`webfetch`), dropping an unmappable name rather than emitting an invalid one.

Documentation to refresh in the same change: the **Target Layout** and **Generated Formats** tables in `deployment/README.md` gain OpenCode rows (its `~/.config/opencode` global path, `.opencode/` project path, and the agent-generation entry). Check whether root `README.md` enumerates deploy targets and add OpenCode there if it does.

Companion, not a prerequisite: [deployment_relocate-state-to-home.md](deployment_relocate-state-to-home.md) co-edits `deployment.sh` and `deployment.conf`/its template; whichever lands second reconciles the shared surface, and neither blocks the other. The OpenCode hook surface is a separate follow-on, [deployment_opencode-hook-bridge.md](deployment_opencode-hook-bridge.md), which builds on the `opencode` target this task creates.

## Approach

Add `opencode` to `VALID_TARGETS`, define `OPENCODE_DIR` in both branches of the target-directories block (`${HOME_DIR}/.config/opencode` global, `${PROJECT_DIR}/.opencode` project), and append `opencode|OpenCode|${OPENCODE_DIR}` to `ALL_APP_TARGETS`. Give the backup path a self-describing name override so activating `opencode` backs up `~/.config/opencode` to `~/.opencode-config_<timestamp>` rather than `~/opencode_<timestamp>`.

In `install_for_app()`, add an `opencode` arm to the `command` and `skill` cases that copies into `${app_dir}/commands/<name>.md` and `${app_dir}/skills/<name>/` respectively via `copy_path_with_replacements`, matching the default branch. For the `agent` case, add an `opencode` arm that calls a new `generate_opencode_agent` — built on the `generate_toml_agent`/`generate_gemini_agent` template: run `rewrite_agent_frontmatter` first to resolve `OPENCODE_`/other vendor prefixes, then emit OpenCode frontmatter with `mode: subagent`, `model` mapped (inherit→omit, concrete→`provider/id`), and read-only/`tools` mapped to OpenCode's `permission`/`tools` vocabulary as described in Context, writing the agent body through unchanged.

Add an `#opencode` section with `disallow:*legacy*` to `deployment.conf` for parity with the other tool sections. Rewrite the `deployment/README.md` Target Layout and Generated Formats tables in place to add the OpenCode rows.

**Out of scope:**

- Hook deployment for OpenCode is owned by [deployment_opencode-hook-bridge.md](deployment_opencode-hook-bridge.md); OpenCode has no declarative hook config to merge into, so it needs a different mechanism than the JSON-merge used for Claude/Codex/Cursor.
- This task sets no environment variables and does not configure OpenCode's Claude-directory isolation; `OPENCODE_DISABLE_CLAUDE_CODE=1` is operator guidance noted in the docs, not a deploy action.
- Relocating the deploy conf and log into `$HOME` stays owned by [deployment_relocate-state-to-home.md](deployment_relocate-state-to-home.md).

## Acceptance

- `./deployment/deployment.sh --target opencode --global --dry-run` is accepted (no "Unknown deploy target" abort) and its banner/target list shows the OpenCode base dir resolving to `~/.config/opencode`, not `~/.opencode`.
- A deploy into a throwaway `--project-dir` scratch directory with `--target opencode` produces `<scratch>/.opencode/skills/<skill>/SKILL.md` as a real directory tree (`test -d` true, `test -L` false), `<scratch>/.opencode/commands/<command>.md` as a real file, and `<scratch>/.opencode/agents/<agent>.md` as a real file.
- The generated `<scratch>/.opencode/agents/<agent>.md` carries `mode: subagent`; an agent whose source expresses `model: inherit` has no `model` key in the output; and a read-only source agent emits OpenCode `permission` denies (or a `tools` map disabling write/edit/bash) rather than a Claude `tools:` comma-string — verified by reading the generated file.
- Running the same scratch deploy through an agent that declares an explicit Claude `tools:` allowlist produces an OpenCode `tools` object with lowercase names (e.g. `Read, Grep`→`read`, `grep`), with any unmappable name dropped rather than emitted verbatim.
- `--uninstall --target opencode` scoped to the scratch deployment removes the copied skill directory, command file, and agent file recorded in the log, leaving those paths absent.
- Activating `opencode` in global mode backs up an existing `~/.config/opencode` to a managed backup named for OpenCode (e.g. `~/.opencode-config_<timestamp>`), not `~/opencode_<timestamp>` — confirm via `--dry-run` backup output naming.
- `deployment.conf` contains an `#opencode` section with `disallow:*legacy*`, and a `*legacy*`-tagged artefact is excluded for `opencode` in a `--dry-run`.
- `deployment/README.md` Target Layout and Generated Formats tables include OpenCode rows naming its `~/.config/opencode` global and `.opencode/` project paths and the agent-generation transform; a grep of the README for `opencode` finds them, and if root `README.md` enumerates deploy targets it lists OpenCode too.
