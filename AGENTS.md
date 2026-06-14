# AGENTS.md

**ai-modules is a meta-repository.** It defines and maintains AI components — skills, agents, commands, hooks — and packages them as plugins. Components run in their target environments (Codex, Codex, Cursor, Copilot, Gemini, Antigravity) after `make deploy` symlinks them into vendor config dirs. Treat every `SKILL.md`, `plugin.json`, and `marketplace.json` as a published artefact: edits propagate to every machine that re-runs deploy.

## What this repo is not

The skills shipped here (`wiki`, `executive_summary`, `spr`, `git_commit`, `update_changelog`, `ai_instruction_writing`, `ai_instruction_formatting`, `format_*`) are the **product**, not the workflow. When a user asks you to apply one while editing this repo, confirm whether they mean to invoke it on the current task or to edit the skill's definition.

## Layout

```text
.Codex-plugin/marketplace.json   # Codex marketplace registration (lists plugins)
plugins/<plugin>/
  .Codex-plugin/plugin.json      # Codex plugin metadata
  .codex-plugin/plugin.json       # Codex plugin metadata (uses "skills": "./skills/")
  README.md                       # plugin overview + skill list
  skills/<skill>/SKILL.md         # skill definition with YAML frontmatter
deployment/                       # deploy script + per-tool config
tests/                            # local-only regression harnesses (gitignored)
Makefile                          # task entry point
.markdownlint.jsonc               # markdown lint config (MD033 off — pseudo-XML is intentional)
```

## Authoring conventions

- **Use pseudo-XML inside skill prompts** (`<role>`, `<objective>`, `<policy>`, `<output_contract>`). Reference: `plugins/ai_dev/skills/ai_instruction_formatting/SKILL.md`.
- **Use positive, action-oriented language** in skill prose and instructions. Reference: `plugins/ai_dev/skills/ai_instruction_writing/SKILL.md`.
- **Keep the toolchain to Make + shell + markdown.** Add new languages, package managers, or build steps only when the user explicitly asks for them.
- **Match snake_case naming** for skill and plugin directories.
- **Write deployment-agnostic cross-references.** Skills, agents, commands, and hooks ship through several equal paths — the Codex marketplace, `make deploy` symlinks into user config dirs, `--project-dir` symlinks into a single repo, or in-place use from a checkout. None is canonical, none is the fallback. When an artefact references a sibling, name it directly (`wiki_auto_shaper`, `format_markdown`) and never qualify with the plugin name, the marketplace, or a deployment path. The only safe assumption is that assets bundled in the same plugin tend to be installed together, since the plugin is the unit of distribution; even that is best-effort, since users can opt out per-asset via deployment filters.

## Versioning

- **Ship a new skill, agent, or plugin at 1.0.0.** In the commit that first introduces it, leave the version at 1.0.0 — no bump.
- **Bump once per commit, with the change — and only at commit time.** When a commit edits an existing skill, agent, or plugin, raise its `version` in that commit. The bump rides with the commit that publishes the change: don't bump while iterating, and treat versioning as exclusively a commit-time concern. It belongs in no other artefact — task files, plans, and pre-commit notes neither restate it nor list it as a step, and task tooling (`task_check`, `task_create`, `task_audit`, `task_fix`) neither requires it nor flags its absence.
- **Plugin meta stays lockstep.** When a skill or agent `version:` rises, raise the matching plugin's `.Codex-plugin/plugin.json`, `.codex-plugin/plugin.json`, and the plugin entry in `.Codex-plugin/marketplace.json` to the same new plugin version in the same commit. Adding a new skill to an existing plugin counts as a plugin edit and triggers the lockstep bump on the plugin meta; the new skill itself ships at 1.0.0.

## Common tasks

- `make help` — list every target.
- `make lint` / `make fix` — runs `markdownlint`, `jq` syntax check, `shellcheck`. `fix` auto-fixes markdown only.
- `make deploy` — symlink components into vendor config dirs. Aliases: `global`, `install`. **Run only when the user asks for it.**
- `make uninstall` — remove deployed artefacts via the deployment log.
- `./deployment/deployment.sh --global --dry-run` — preview a deploy before applying.

`CHANGELOG.md` is git-history-derived. Update it only through the `update_changelog` skill, run on demand. Don't hand-edit CHANGELOG entries as part of other work. Committing the skill's output is fine.

This repo manages upcoming work and todos with the `task` skill (`/task`). Open items live in `tasks/`; `implemented` and `deferred` items move to `tasks/archive/`.

## Editing a skill

1. Edit `plugins/<plugin>/skills/<name>/SKILL.md`. Keep the directory name, the frontmatter `name:`, and the H1 heading aligned.
2. When the skill list changes, also update the plugin's `README.md`, both `plugin.json` files, and the root `README.md` plus `.Codex-plugin/marketplace.json`.
3. Run `make lint` and `./deployment/deployment.sh --global --dry-run` before committing.

## Adding a plugin

1. Create `plugins/<new_plugin>/` with `.Codex-plugin/plugin.json`, `.codex-plugin/plugin.json` (set `"skills": "./skills/"`), `README.md`, and a `skills/` directory.
2. Register the plugin in `.Codex-plugin/marketplace.json` under `plugins[]`.
3. Update the root `README.md` layout tree and **Plugins** bullet list.

## Regression test harnesses

- **When the user says "tests" (or "test the skill", "run the tests", "regress X"), run both surfaces together unless the user narrows the scope.** Every plugin skill has two testable surfaces and we exercise both: (1) the **bundled scripts** that ship inside the skill (e.g. `plugins/<plugin>/skills/<skill>/scripts/*.sh`) are tested programmatically with bash unit tests under `tests/<skill>/script_tests/run.sh` — fast, deterministic, no LLM cost; (2) the **skill behavior** (the prose policy in `SKILL.md` that drives the agent) is tested with skill-creator's eval workflow against `tests/<skill>/evals/evals.json`. Script tests catch mechanical regressions in the shipped shell programs; evals catch behavioral regressions in how the agent follows the skill. Report results from both before claiming a skill is in good shape; a green script_tests run alone is not "the tests passing".
- **One harness per skill under `tests/<skill_name>/`.** The whole `tests/` tree is in `.gitignore` and excluded from `make lint`; nothing in it gets committed. See `tests/README.md` for the full layout.
- **Prefer the skill-creator-aligned pattern for new harnesses.** `tests/<skill>/evals/evals.json` follows the canonical schema from `skill-creator/references/schemas.md` (`id`, `prompt`, `expected_output`, `files`, `expectations[]`); per-eval `fixtures/<name>/setup.sh` stages a sandbox; runs go to `tests/<skill>/workspace/iteration-N/`. Bundled-script unit tests sit alongside in `script_tests/` (not a "layer" of the eval). Run via skill-creator's `scripts.run_eval` out-of-band; `run_all.sh` only drives the script unit tests. Reference implementation: `tests/git_commit/`.
- **`tests/wiki/` uses the legacy two-layer pattern.** It's the mature pre-skill-creator harness and stays as-is. Migrate it the next time it needs significant iteration; don't bring up new harnesses under that pattern.
- **Don't expand a harness in the same session that ships a skill change.** Land the skill change first with a tight new scenario for it, run the existing suite to verify no regression, commit. Test growth lives in its own session per the versioning rule above (one bump per session ends with the commit that contains it).
