# CLAUDE.md

**ai-modules is a meta-repository.** It defines and maintains AI components — skills, agents, commands, hooks — and packages them as plugins. Components run in their target environments (Claude Code, Codex, Cursor, Copilot, Gemini, Antigravity) after `make deploy` symlinks them into vendor config dirs. Treat every `SKILL.md`, `plugin.json`, and `marketplace.json` as a published artefact: edits propagate to every machine that re-runs deploy.

## Layout

```text
.claude-plugin/marketplace.json   # Claude marketplace registration (lists plugins)
plugins/<plugin>/
  .claude-plugin/plugin.json      # Claude plugin metadata
  .codex-plugin/plugin.json       # Codex plugin metadata (uses "skills": "./skills/")
  README.md                       # plugin overview + skill list
  skills/<skill>/SKILL.md         # skill definition with YAML frontmatter
deployment/                       # deploy script + per-tool config
Makefile                          # task entry point
.markdownlint.jsonc               # markdown lint config (MD033 off — pseudo-XML is intentional)
```

## Common tasks

- `make help` — list every target.
- `make lint` / `make fix` — runs `markdownlint`, `jq` syntax check, `shellcheck`. `fix` auto-fixes markdown only.
- `make deploy` — symlink components into vendor config dirs. Aliases: `global`, `install`. **Run only when the user asks for it.**
- `make uninstall` — remove deployed artefacts via the deployment log.
- `./deployment/deployment.sh --global --dry-run` — preview a deploy before applying.

## Editing a skill

1. Edit `plugins/<plugin>/skills/<name>/SKILL.md`. Keep the directory name, the frontmatter `name:`, and the H1 heading aligned.
2. When the skill list changes, also update the plugin's `README.md`, both `plugin.json` files, and the root `README.md` plus `.claude-plugin/marketplace.json`.
3. Run `make lint` and `./deployment/deployment.sh --global --dry-run` before committing.

## Adding a plugin

1. Create `plugins/<new_plugin>/` with `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` (set `"skills": "./skills/"`), `README.md`, and a `skills/` directory.
2. Register the plugin in `.claude-plugin/marketplace.json` under `plugins[]`.
3. Update the root `README.md` layout tree and **Plugins** bullet list.

## Authoring conventions

- **Use pseudo-XML inside skill prompts** (`<role>`, `<objective>`, `<policy>`, `<output_contract>`). Reference: `plugins/ai_dev/skills/ai_instruction_formatting/SKILL.md`.
- **Use positive, action-oriented language** in skill prose and instructions. Reference: `plugins/ai_dev/skills/ai_instruction_writing/SKILL.md`.
- **Keep the toolchain to Make + shell + markdown.** Add new languages, package managers, or build steps only when the user explicitly asks for them.
- **Match snake_case naming** for skill and plugin directories.
- **Write deployment-agnostic cross-references.** Skills, agents, commands, and hooks ship through several equal paths — the Claude marketplace, `make deploy` symlinks into user config dirs, `--project-dir` symlinks into a single repo, or in-place use from a checkout. None is canonical, none is the fallback. When an artefact references a sibling, name it directly (`wiki_auto_shaper`, `format_markdown`) and never qualify with the plugin name, the marketplace, or a deployment path. The only safe assumption is that assets bundled in the same plugin tend to be installed together, since the plugin is the unit of distribution; even that is best-effort, since users can opt out per-asset via deployment filters.

## What this repo is not

The skills shipped here (`wiki`, `executive_summary`, `spr`, `git_commit`, `update_changelog`, `ai_instruction_writing`, `ai_instruction_formatting`, `format_*`) are the **product**, not the workflow. When a user asks you to apply one while editing this repo, confirm whether they mean to invoke it on the current task or to edit the skill's definition.
