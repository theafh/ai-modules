# Deployment Script

`deployment/deployment.sh` deploys repo artifacts into config directories for VS Code GitHub Copilot, Cursor, Claude Code, OpenAI Codex, Gemini CLI, and Google Antigravity. It can deploy to global config dirs or into a single project directory.

It autodiscovers artifacts by plugin layout, backs up only the selected targets (global mode only), records deployed paths in `deployment/deployed_artefacts.log`, and can uninstall previously deployed artifacts from that log.

## Run It

Run with no arguments to see help. Pass `--global` to deploy globally, or `--project-dir DIR` to deploy into a single project's local config:

```bash
./deployment/deployment.sh                                        # show help
./deployment/deployment.sh --global                               # deploy all to global dirs
./deployment/deployment.sh --global --dry-run                     # preview
./deployment/deployment.sh --global --type skill --target claude  # filter
./deployment/deployment.sh --project-dir /path/to/repo --target claude
./deployment/deployment.sh --uninstall                            # remove logged artifacts
./deployment/deployment.sh --clear-backups --target cursor,claude
```

## Flags

| Flag | Meaning |
| --- | --- |
| `--global` | Deploy into global config dirs (`~/.cursor`, `~/.claude`, …). Mutually exclusive with `--project-dir`. |
| `--project-dir DIR` | Deploy into a project directory's local config (`<DIR>/.cursor/`, `<DIR>/.claude/`, …). Backups are disabled in this mode. |
| `--type TYPES` | Comma-separated artifact filter: `command`, `skill`, `agent`, `hook`. |
| `--target TARGETS` | Comma-separated target filter: `vscode`, `cursor`, `claude`, `codex`, `gemini`, `antigravity`. |
| `--uninstall` | Remove previously deployed artifacts that match the active filters. Backups still run first. |
| `--clear-backups` | Remove old managed backups for the selected targets before creating a fresh backup. No effect in `--project-dir` mode. |
| `--dry-run` | Preview backups, installs, and uninstall actions without writing changes. |
| `-h`, `--help` | Show built-in help. |

If `--target` filters out every app, the script aborts. If discovery finds no matching artifacts, it exits cleanly without deploying anything. `jq` is required (used for JSON-merge of Claude hook config) — the script exits early if it's missing.

## Artifact Discovery

Discovery is plugin- and folder-based. Artifacts live under `plugins/<plugin>/<asset-folder>/`, where the asset-folder name defines the artifact type:

| Asset folder | Type | What counts as an artifact |
| --- | --- | --- |
| `agents/` | agent | each top-level `*.md` file |
| `commands/` | command | each top-level `*.md` file |
| `skills/` | skill | each immediate subdirectory containing `SKILL.md` |
| `hooks/` | hook | each top-level `*.sh` or `*.json` file |

Hidden files and `README*` files are skipped. The deployed name is the file basename without extension, or the skill directory's basename.

The script walks up from its own location until it finds a directory containing a `plugins/` folder, so it works regardless of where it lives in the tree. Repo-relative paths (e.g. for `deployment.conf` rules and the deploy log) take the form `plugins/<plugin>/<asset-folder>/<artifact>`.

## Per-Tool Configuration (`deployment.conf`)

`deployment/deployment.conf` controls what gets deployed where, in robots.txt-style sections:

```text
#tool                     Section heading: vscode, cursor, claude, codex, gemini, antigravity
disallow:path             Skip a path (relative to repo root) for this tool. Trailing slash matches a subtree. Glob patterns supported (* and **).
replace:path VAR=value    Force a copied (not symlinked) deployment for matching paths and substitute $VAR$ in the deployed copy.
```

The current config disallows any path matching `*legacy*` for every target, so any plugin or artifact tagged as legacy is kept in the repo but never deployed.

## Target Layout

The table below shows global-mode paths. Project-dir mode replaces `~` with `<project>/` and uses each IDE's native project-level path.

| Target | Commands | Skills | Agents | Hooks |
| --- | --- | --- | --- | --- |
| VS Code Copilot | `~/Library/Application Support/Code/User/prompts/<name>.prompt.md` (macOS) or `~/.config/Code/User/prompts/<name>.prompt.md` (Linux), via symlink | `~/.copilot/skills/<name>` via symlink | `~/.copilot/agents/<name>.agent.md`, frontmatter rewritten | `~/.copilot/hooks/<file>` via copy |
| Cursor | `~/.cursor/commands/<name>.md` via symlink | `~/.cursor/skills/<name>` via symlink | `~/.cursor/agents/<name>.md`, frontmatter rewritten | `~/.cursor/hooks.json` (copy from `cursor-hooks*.json`) and `~/.cursor/hooks/<file>` for shell scripts |
| Claude Code | `~/.claude/commands/<name>.md` via symlink | `~/.claude/skills/<name>` via symlink | `~/.claude/agents/<name>.md`, frontmatter rewritten | `.hooks` key merged into `~/.claude/settings.json` (from `claude-code-hooks*.json`); shell scripts copied to `~/.claude/hooks/<file>` |
| OpenAI Codex | `~/.codex/prompts/<name>.md` via symlink | `~/.codex/skills/<name>` via symlink (project-dir uses `<project>/.agents/skills/<name>`) | `~/.codex/agents/<name>.toml` generated from agent source | not implemented |
| Gemini CLI | `~/.gemini/commands/<name>.toml` generated from command source | `~/.gemini/skills/<name>` via symlink | `~/.gemini/agents/<name>.md`, frontmatter rewritten | not implemented |
| Antigravity | `~/.gemini/antigravity/workflows/<name>.md` generated from command source | `~/.gemini/antigravity/skills/<name>` via symlink | not supported (skipped) | not implemented |

Project-dir mode skips Gemini and Antigravity (no documented project-level config convention) and warns if you request them via `--target`.

## Generated Formats

Several targets do not consume the repo source files directly:

| Source type | Target | Generated output |
| --- | --- | --- |
| command (`commands/*.md`) | VS Code Copilot | copied as `<name>.prompt.md` |
| command (`commands/*.md`) | Gemini CLI | `.toml` with the first `# Heading` mapped to `description` and the remaining body to `prompt` |
| command (`commands/*.md`) | Antigravity | workflow `.md` with YAML frontmatter `description` from the first `# Heading` and the remaining body preserved |
| agent (`agents/*.md`) | VS Code, Cursor, Claude, Gemini | frontmatter rewritten — vendor-prefixed fields (`CLAUDE_model:`, `CURSOR_model:`, …) are kept and stripped of prefix for the matching target; fields prefixed for other tools are dropped |
| agent (`agents/*.md`) | OpenAI Codex | `.toml` mapping frontmatter `name`, `description`, `model`, `model_reasoning_effort`, and `readonly` (`readonly: true` becomes `sandbox_mode = "read-only"`); body becomes `developer_instructions` |
| hook (`hooks/claude-code-hooks*.json`) | Claude Code | `.hooks` key merged into `~/.claude/settings.json`; relative `./hooks/` command paths are rewritten to absolute (global) or `.claude/hooks/` (project-dir) so the config stays portable |
| hook (`hooks/cursor-hooks*.json`) | Cursor | copied to `~/.cursor/hooks.json` |

`replace:path VAR=value` rules in `deployment.conf` force a copied (not symlinked) deployment for matching paths and substitute `$VAR$` in the deployed copy only.

Generated, copied, and frontmatter-rewritten outputs are not live-linked back to the repo — re-run the script after editing the source. Symlinked artifacts reflect repo changes immediately.

## Backups

Before deploy or uninstall in global mode, the script backs up only the activated target roots:

- `vscode` backs up `~/.copilot` and the VS Code prompts dir
- `cursor` backs up `~/.cursor`
- `claude` backs up `~/.claude`
- `codex` backs up `~/.codex`
- `gemini` backs up `~/.gemini`
- `antigravity` also backs up `~/.gemini` (Antigravity lives inside that tree)

Backups land in `$HOME` as `<name>_YYYYMMDD_HHMMSS`, e.g. `~/.cursor_YYYYMMDD_HHMMSS`, `~/.claude_YYYYMMDD_HHMMSS`. `<name>` defaults to the basename of the target directory; it is overridden when the basename isn't tool-distinctive — currently the VS Code user-prompts dir on macOS (`~/Library/Application Support/Code/User/prompts`) backs up to `~/.vscode-prompts_YYYYMMDD_HHMMSS` rather than the misleading `~/prompts_YYYYMMDD_HHMMSS`. If a selected target dir does not exist yet, the script skips that backup. `--project-dir` mode skips backups entirely.

`--clear-backups` removes only backups that match the script's managed naming scheme before creating the fresh backup for that target.

## Deploy Log and Uninstall

Every real deploy appends one line per deployed artifact to `deployment/deployed_artefacts.log` (tab-separated):

1. deployed path (or `path[key]` for JSON-merge entries)
2. target id
3. artifact type
4. source path

The log is deduplicated on script exit. Dry runs do not modify it.

`--uninstall` removes only log entries that match the active filters. Unmatched entries stay in the log. If a logged path is already gone, uninstall treats it as cleaned up and removes the log entry anyway. JSON-merge entries are removed by stripping the corresponding key from the target file (e.g. removing `.hooks` from `~/.claude/settings.json`) instead of deleting the file.

## Write Behavior

- Symlink installs refuse to overwrite an existing non-symlink path and skip that artifact.
- Generated, copied, and frontmatter-rewritten outputs replace an existing file or symlink at the destination.
- Base target directories such as `~/.cursor`, `~/.claude`, or `~/.gemini/antigravity` are created on demand.

## Platform Notes

The script targets Bash on macOS and Linux and relies on standard Unix tools (`cp -a`, `ln -s`, `sort`, `mktemp`) plus `jq` and `perl`. Windows requires a compatible Unix-like environment such as WSL.
