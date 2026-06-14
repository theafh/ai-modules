# CLAUDE.md

**ai-modules is a meta-repository.** It defines AI components — skills, agents, commands, hooks — and packages them as plugins. Treat every `SKILL.md`, `plugin.json`, and `marketplace.json` as a published artefact: edits propagate to every machine that re-runs `make deploy`.

## What this repo is not

The shipped skills are the **product**, not the workflow. When a user asks you to apply one while editing this repo, confirm whether they mean to invoke it or edit its definition.

## Layout

```text
.claude-plugin/marketplace.json   # Claude marketplace registration
.agents/plugins/marketplace.json  # Codex marketplace registration
plugins/<plugin>/
  .claude-plugin/plugin.json      # Claude plugin metadata
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
- **Write deployment-agnostic cross-references.** Reference sibling artefacts by name (`wiki_auto_shaper`, `format_markdown`) rather than by plugin name, marketplace, or installed path.

## Versioning

- **Ship a new skill, agent, or plugin at 1.0.0.** In the commit that first introduces it, leave the version at 1.0.0 — no bump.
- **Bump once per commit, with the change — and only at commit time.** When a commit edits an existing skill, agent, or plugin, raise its `version` in that commit. Do not bump while iterating, and do not add version-bump steps to task files, plans, or pre-commit notes.
- **Use patch increments for minor maintenance changes.** For a small follow-up, wording fix, or environment-specific hint, advance only the patch component.
- **Plugin meta stays lockstep.** When a skill or agent `version:` rises, raise the matching plugin's `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, and both marketplace registrations (`.claude-plugin/marketplace.json`, `.agents/plugins/marketplace.json`) to the same new plugin version in the same commit. Adding a skill to an existing plugin counts as a plugin edit; the new skill itself ships at 1.0.0.

## Common tasks

- `make help` — list every target.
- `make lint` / `make fix` — runs `markdownlint`, `jq` syntax check, `shellcheck`. `fix` auto-fixes markdown only.
- `make deploy` — symlink components into vendor config dirs. Aliases: `global`, `install`. **Run only when the user asks for it.**
- `make uninstall` — remove deployed artefacts via the deployment log.

`CHANGELOG.md` is git-history-derived. Update it only through the `update_changelog` skill, run on demand. Don't hand-edit CHANGELOG entries as part of other work. Committing the skill's output is fine.

This repo manages upcoming work and todos with the `task` skill (`/task`). Live items (`open`, `checked`, `ready`, `implemented`, `audited`) live in `tasks/`; terminal items (`finished`, `deferred`) move to `tasks/archive/`. Task files record `reported-by`, and implemented work records `implemented-by`.

Task files stay agent-harness agnostic. When a task needs standing repo instructions, cite them as the **repo rules** or **standing repo rules** rather than naming `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, or another harness-specific file. Name a harness file in a task only when that file itself is the implementation target.

## Editing a skill

1. Edit `plugins/<plugin>/skills/<name>/SKILL.md`. Keep the directory name, the frontmatter `name:`, and the H1 heading aligned.
2. When the skill list changes, also update the plugin's `README.md`, both `plugin.json` files, the root `README.md`, and marketplace registrations.
3. Run `make lint` before committing.

## Adding a plugin

1. Create `plugins/<new_plugin>/` with `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` (set `"skills": "./skills/"`), `README.md`, and a `skills/` directory.
2. Register the plugin in the marketplace files under `plugins[]`.
3. Update the root `README.md` layout tree and **Plugins** bullet list.

## Regression test harnesses

- **When the user says "tests" (or similar), run both skill surfaces unless the user narrows scope.** Run bundled-script tests under `tests/<skill>/script_tests/run.sh` and skill-behavior evals under `tests/<skill>/evals/evals.json`. Report both surfaces before claiming a skill is in good shape.
- **One harness per skill under `tests/<skill_name>/`.** The whole `tests/` tree is in `.gitignore` and excluded from `make lint`; nothing in it gets committed. See `tests/README.md` for the full layout.
- **Prefer the skill-creator-aligned pattern for new harnesses.** Keep evals in `evals/evals.json` (schema: `skill-creator/references/schemas.md`), fixtures in `evals/fixtures/`, run output in `workspace/iteration-N/`, and script unit tests in `script_tests/`. Run evals out-of-band via skill-creator's `scripts.run_eval`; `run_all.sh` drives only the script tests. Reference implementation: `tests/git_commit/`.
- **`tests/wiki/` uses the legacy two-layer pattern.** Keep it as-is until its next significant iteration; create new harnesses with the skill-creator-aligned pattern.
- **Keep skill changes and harness expansion separate.** Land the skill change first with a tight scenario and existing-suite verification. Put broader test growth in its own session.
