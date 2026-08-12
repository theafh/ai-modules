# Deployment Script

`deployment/deployment.sh` deploys repo artifacts into config directories for VS Code GitHub Copilot, Cursor, Claude Code, OpenAI Codex, Google Antigravity, and OpenCode. It can deploy to global config dirs or into a single project directory.

It autodiscovers artifacts by plugin layout, backs up only the selected targets (global mode only), records deployed paths in `deployment/deployed_artefacts.log`, and can uninstall previously deployed artifacts from that log.

## Run It

Run with no arguments to see help. Pass `--global` to deploy globally, or `--project-dir DIR` to deploy into a single project's local config. `--uninstall` and standalone `--clear-backups` are maintenance modes that can run without a deployment scope:

```bash
./deployment/deployment.sh                                        # show help
./deployment/deployment.sh --global                               # deploy all to global dirs
./deployment/deployment.sh --global --dry-run                     # preview
./deployment/deployment.sh --global --type skill --target claude  # filter
./deployment/deployment.sh --project-dir /path/to/repo --target claude
./deployment/deployment.sh --uninstall                            # remove logged artifacts
./deployment/deployment.sh --clear-backups --target cursor,claude # clear managed backups only
```

## Flags

| Flag | Meaning |
| --- | --- |
| `--global` | Deploy into global config dirs (`~/.cursor`, `~/.claude`, …). Mutually exclusive with `--project-dir`. |
| `--project-dir DIR` | Deploy into a project directory's local config (`<DIR>/.cursor/`, `<DIR>/.claude/`, …). Backups are disabled in this mode. |
| `--type TYPES` | Comma-separated artifact filter: `command`, `skill`, `agent`, `hook`, `style`. Requires `--global` or `--project-dir` unless used with `--uninstall`. |
| `--target TARGETS` | Comma-separated target filter: `vscode`, `cursor`, `claude`, `codex`, `antigravity`, `opencode`. |
| `--uninstall` | Remove previously deployed artifacts that match the active filters. Can run without `--global` or `--project-dir`; backups still run first unless combined with no-scope `--clear-backups`. |
| `--clear-backups` | Remove old managed backups for the selected targets before creating a fresh backup. Without `--global` or `--project-dir`, this clears matching global backups and exits before deploy. No effect in `--project-dir` mode. |
| `--dry-run` | Preview backups, installs, and uninstall actions without writing changes. |
| `-h`, `--help` | Show built-in help. |

Deploy operations require an explicit scope: pass `--global` or `--project-dir DIR`. `--dry-run`, `--type`, or `--target` alone are deploy/filter requests and abort with a missing-scope error. If `--target` filters out every app, the script aborts. If discovery finds no matching artifacts, it exits cleanly without deploying anything. `jq` is required (used for JSON-merge of Claude hook config) — the script exits early if it's missing.

## Artifact Discovery

Discovery uses two roots.

### Plugin asset folders

Artifacts live under `plugins/<plugin>/<asset-folder>/`, where the asset-folder name defines the artifact type:

| Asset folder | Type | What counts as an artifact |
| --- | --- | --- |
| `agents/` | agent | each top-level `*.md` file |
| `commands/` | command | each top-level `*.md` file |
| `skills/` | skill | each immediate subdirectory containing `SKILL.md` |
| `hooks/` | hook | each top-level `*.sh` or `*.json` file |

Hidden files and `README*` files are skipped. The deployed name is the file basename without extension, or the skill directory's basename.

Those rules select *which* artifacts get deployed. A separate rule governs what travels *inside* one: a directory artifact is copied wholesale, and the deploy then strips Python bytecode from the destination, so a deployed skill carries the artifact's own files with no `__pycache__` directory and no `.pyc` file whatever bytecode the working tree holds at deploy time. A deploy from a tree that has run bundled skill scripts therefore produces the same destination as one from a clean checkout.

Repo-relative paths for plugin artifacts (e.g. for `deployment.conf` rules and the deploy log) take the form `plugins/<plugin>/<asset-folder>/<artifact>`.

### Repo-root styles

The `style` type is discovered from repo-root `styles/`: each top-level `*.md` file is one style artifact, with repo-relative path `styles/<file>.md`. Styles are not plugin components and are not registered under any plugin's `output-styles/` folder.

The script walks up from its own location until it finds a directory containing a `plugins/` folder, so it works regardless of where it lives in the tree.

## Per-Tool Configuration (`deployment.conf`)

`deployment/deployment.conf` controls what gets deployed where, in robots.txt-style sections:

```text
#tool                     Section heading: vscode, cursor, claude, codex, antigravity, opencode
disallow:path             Skip a path (relative to repo root) for this tool. Trailing slash matches a subtree. Glob patterns supported (* and **).
replace:path VAR=value    Substitute $VAR$ in matching deployed copies.
style:<name>              Active output-style name for this tool. Claude merges it as settings `outputStyle`.
```

The current config disallows any path matching `*legacy*` for every target, so any plugin or artifact tagged as legacy is kept in the repo but never deployed. Claude also sets `style:natural-language` so a style deploy activates that tracked style.

## Target Layout

The table below shows global-mode paths. Project-dir mode replaces `~` with `<project>/` and uses each IDE's native project-level path.

| Target | Commands | Skills | Agents | Hooks | Styles |
| --- | --- | --- | --- | --- | --- |
| VS Code Copilot | `~/Library/Application Support/Code/User/prompts/<name>.prompt.md` (macOS) or `~/.config/Code/User/prompts/<name>.prompt.md` (Linux), copied | `~/.copilot/skills/<name>` copied | `~/.copilot/agents/<name>.agent.md`, frontmatter rewritten | `~/.copilot/hooks/<file>` copied | not yet |
| Cursor | `~/.cursor/commands/<name>.md` copied | `~/.cursor/skills/<name>` copied | `~/.cursor/agents/<name>.md`, frontmatter rewritten | `~/.cursor/hooks.json` (copy from `cursor-hooks*.json`) and `~/.cursor/hooks/<file>` for shell scripts | not yet |
| Claude Code | `~/.claude/commands/<name>.md` copied | `~/.claude/skills/<name>` copied | `~/.claude/agents/<name>.md`, frontmatter rewritten | `.hooks` key merged into `~/.claude/settings.json` (from `claude-code-hooks*.json`); shell scripts copied to `~/.claude/hooks/<file>` | file copied to `~/.claude/output-styles/<name>.md`; `outputStyle` merged from `style:<name>` in `deployment.conf` |
| OpenAI Codex | `~/.codex/prompts/<name>.md` copied | `~/.codex/skills/<name>` copied (project-dir uses `<project>/.agents/skills/<name>`) | `~/.codex/agents/<name>.toml` generated from agent source | `hooks` key merged into `~/.codex/hooks.json` (from `codex-custom-deploy-hooks.json`); shell scripts copied to `~/.codex/hooks/<file>` | not yet |
| Antigravity | not deployed — the repo ships no commands | fan-out copied to `~/.gemini/config/skills/<name>`, `~/.gemini/antigravity/skills/<name>`, and `~/.gemini/antigravity-cli/skills/<name>` | `~/.gemini/config/agents/<name>.md` generated with Antigravity frontmatter and tool-name mapping | `charter_guardrail` key merged into `~/.gemini/config/hooks.json`; shell scripts copied to `~/.gemini/config/hooks/<file>` | not yet |
| OpenCode | `~/.config/opencode/commands/<name>.md` copied | `~/.config/opencode/skills/<name>` copied | `~/.config/opencode/agents/<name>.md` generated with OpenCode frontmatter and permission mapping | not implemented | not yet |

Project-dir mode uses each tool's project path, including `<project>/.agents/` for Antigravity and `<project>/.opencode/` for OpenCode.

One global Antigravity deploy reaches Antigravity 2.0, the IDE, and the CLI by writing each artifact class where Antigravity reads it. Agents and hooks use the shared `~/.gemini/config/` root. Skills fan out to the three product-specific skill roots so a user does not need to know which product owns which directory. If one Antigravity product reads more than one skill root, the same skill id may register twice; the duplicate copies are byte-identical, so this is expected diagnostic context rather than a data-loss risk.

## Generated Formats

Several targets do not consume the repo source files directly:

| Source type | Target | Generated output |
| --- | --- | --- |
| command (`commands/*.md`) | VS Code Copilot | copied as `<name>.prompt.md` |
| agent (`agents/*.md`) | VS Code, Cursor, Claude | frontmatter rewritten — vendor-prefixed fields (`CLAUDE_model:`, `CURSOR_model:`, …) are kept and stripped of prefix for the matching target; fields prefixed for other tools are dropped |
| agent (`agents/*.md`) | OpenAI Codex | `.toml` mapping frontmatter `name`, `description`, `model`, `model_reasoning_effort`, and `readonly` (`readonly: true` becomes `sandbox_mode = "read-only"`); `model: inherit` is dropped so Codex inherits the parent/default model by omission; body becomes `developer_instructions` |
| agent (`agents/*.md`) | Antigravity | generated markdown with only Antigravity schema keys: `name`, `description`, mapped `tools` arrays (`Read`→`view_file`, `Grep`→`grep_search`, `Bash`→`run_command`, unmapped entries dropped), concrete `model` tier values, `commandExecutionPolicy`, and `mainAgent: false`; `model: inherit` is dropped for session inheritance, `readonly: true` maps to `commandExecutionPolicy: off` only when the source allowlist omits `Bash`, and source-only keys such as `version`, `background`, `effort`, and `model_reasoning_effort` are omitted while unknown-field tolerance remains unverified |
| agent (`agents/*.md`) | OpenCode | generated markdown with only OpenCode schema keys: `mode: subagent`, `description`, concrete `model` values, `temperature`, and `permission`; `model: inherit` is dropped for session inheritance, `readonly: true` maps to `permission: { edit: deny }` plus `bash: deny` unless the source allowlist includes `Bash`, and source-only keys such as `name`, `version`, `background`, `effort`, and `model_reasoning_effort` are omitted so they are not passed to the provider as model options |
| hook (`hooks/claude-code-hooks*.json`) | Claude Code | `.hooks` key merged into `~/.claude/settings.json`; relative `./hooks/` command paths are rewritten to absolute (global) or `.claude/hooks/` (project-dir) so the config stays portable |
| hook (`hooks/codex-custom-deploy-hooks.json`) | OpenAI Codex | `hooks` key merged into `~/.codex/hooks.json`; relative `./hooks/` command paths are rewritten to absolute (global) or `.codex/hooks/` (project-dir) so the config stays portable |
| hook (`hooks/antigravity-hooks.json`) | Antigravity | `charter_guardrail` key merged into `~/.gemini/config/hooks.json` or `<project>/.agents/hooks.json`; relative `./hooks/` command paths are rewritten to absolute (global) or `.agents/hooks/` (project-dir) so the config stays portable |
| hook (`hooks/cursor-hooks*.json`) | Cursor | copied to `~/.cursor/hooks.json` |
| style (`styles/*.md`) | Claude Code | copied to `~/.claude/output-styles/<name>.md`; `outputStyle` set from `style:<name>` in `deployment.conf` |

`replace:path VAR=value` rules in `deployment.conf` substitute `$VAR$` in matching deployed copies.

Every deployed artifact is a copy rather than a live link to the repo. Re-run the script after editing a source artifact to refresh its deployed copy.

## Backups

Before deploy, and before uninstall outside project-dir mode, the script backs up only the activated target roots:

- `vscode` backs up `~/.copilot` and the VS Code prompts dir
- `cursor` backs up `~/.cursor`
- `claude` backs up `~/.claude`
- `codex` backs up `~/.codex`
- `antigravity` backs up the whole `~/.gemini` tree, covering `config/` plus all Antigravity skill roots
- `opencode` backs up `~/.config/opencode`

Backups land in `$HOME` as `<name>_YYYYMMDD_HHMMSS`, e.g. `~/.cursor_YYYYMMDD_HHMMSS`, `~/.claude_YYYYMMDD_HHMMSS`. `<name>` defaults to the basename of the target directory; it is overridden when the basename isn't tool-distinctive: the VS Code user-prompts dir on macOS (`~/Library/Application Support/Code/User/prompts`) backs up to `~/.vscode-prompts_YYYYMMDD_HHMMSS` rather than the misleading `~/prompts_YYYYMMDD_HHMMSS`, and OpenCode's `~/.config/opencode` backs up to `~/.opencode-config_YYYYMMDD_HHMMSS`. If a selected target dir does not exist yet, the script skips that backup. `--project-dir` mode skips backups entirely.

`--clear-backups` removes only backups that match the script's managed naming scheme before creating the fresh backup for that target. When run without a deployment scope, it is a cleanup-only operation: `--target` narrows the global target roots, `--dry-run` previews removals, and the script exits without creating backups or deploying.

## Deploy Log and Uninstall

Every real deploy appends one line per deployed artifact to `deployment/deployed_artefacts.log` (tab-separated):

1. deployed path (or `path[key]` for JSON-merge entries)
2. target id
3. artifact type
4. source path
5. optional prior value for JSON-merge entries (compact JSON, or `@absent` when the key was missing on first write)

The log is deduplicated on script exit. Dry runs do not modify it. Four-field lines from older deploys keep parsing.

On the first write of a JSON key through `merge_json_key`, the previous value is recorded in that fifth field. A later redeploy of the same key reuses the first-recorded prior and does not re-sample the live settings value, so `sort -u` still collapses identical lines.

`--uninstall` removes only log entries that match the active filters. Unmatched entries stay in the log. If a logged path is already gone, uninstall treats it as cleaned up and removes the log entry anyway. JSON-merge entries with a recorded prior restore that value (or delete the key when `@absent` was recorded). Legacy four-field `path[key]` lines still uninstall by stripping the key.

## Write Behavior

- Deployments replace an existing file, directory, or symlink at the destination with the current artifact copy.
- Base target directories such as `~/.cursor`, `~/.claude`, or `~/.gemini/config` are created on demand.

## Platform Notes

The script targets Bash on macOS and Linux and relies on standard Unix tools (`cp -a`, `sort`, `mktemp`) plus `jq` and `perl`. Windows requires a compatible Unix-like environment such as WSL.
