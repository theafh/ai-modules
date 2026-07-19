# AGENTS.md

**ai-modules is a meta-repository.** It defines AI components — skills, agents, commands, hooks — and packages them as plugins. Treat every `SKILL.md`, `plugin.json`, and `marketplace.json` as a published artefact.

## What this repo is not

The shipped skills are the **product**, not the workflow. When a user asks you to apply one while editing this repo, confirm whether they mean to invoke it or edit its definition.

## Layout

```text
.agents/plugins/marketplace.json # Codex marketplace registration
.claude-plugin/marketplace.json  # Claude marketplace registration
plugins/<plugin>/
  .codex-plugin/plugin.json       # Codex plugin metadata (uses "skills": "./skills/")
  .claude-plugin/plugin.json      # Claude plugin metadata
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
- **Write skill descriptions for both audiences.** The `description:` frontmatter is read before the body is loaded by an LLM router and by users browsing skills. Serve both needs deliberately: give the user a precise compact summary of what the skill is about and how it differs from neighbors, then give the router keyword-rich `Use when` trigger contexts, prompt phrases, artefacts, file types, and invocation boundaries. Keep implementation workflow details in the body.
- **Keep the toolchain to Make + shell + markdown.** Add new languages, package managers, or build steps only when the user explicitly asks for them.
- **Match snake_case naming** for skill and plugin directories.
- **Name skills and agents by invocation mode and collision risk.** A skill that is the only entry point for its capability keeps the ordinary family-first name, even when it delegates to agents (`wiki_fix`). Use `<family>_auto_<rest>` for an agent-delegating automation skill when it needs to sit beside a classical/manual skill with the same capability or subset (`task_auto_implement` beside `task_implement`). A spawned agent leads with `auto_` and ends with the family token (`auto_<role>_<family>`, e.g. `auto_implementer_task` or `auto_shaper_wiki`) and is not intended to be invoked by the user.
- **Write deployment-agnostic cross-references.** Reference sibling artefacts by name (`auto_shaper_wiki`, `format_markdown`) rather than by plugin name, marketplace, or installed path.

## Versioning

- **Ship a new skill, agent, or plugin at 1.0.0.** In the commit that first introduces it, leave the version at 1.0.0 — no bump.
- **Bump once per commit, with the change — and only at commit time.** When a commit edits an existing skill, agent, or plugin, raise its `version` in that commit. Do not bump while iterating, and do not add version-bump steps to task files, plans, or pre-commit notes.
- **Use patch increments for minor maintenance changes.** For a small follow-up, wording fix, or environment-specific hint, advance only the patch component.
- **Plugin meta stays lockstep.** When a skill or agent `version:` rises, raise the matching plugin's `.codex-plugin/plugin.json`, `.claude-plugin/plugin.json`, and marketplace entries to the same new plugin version in the same commit. Adding a skill to an existing plugin counts as a plugin edit; the new skill itself ships at 1.0.0.
- **Local marketplaces stay current for `ai_dev` and `knowledge_management`.** When a commit publishes a new version of either plugin, update the local marketplace registrations in `.agents/plugins/marketplace.json` and `.claude-plugin/marketplace.json` in the same commit as the plugin manifests. When opening this repo for plugin maintenance or after updating either marketplace registration, compare the installed cached skill versions against the repo source and tell the user to restart Codex or open a new thread so the refreshed plugin cache is loaded.

## Common tasks

- `make help` — list every target.
- `make lint` / `make fix` — runs `markdownlint`, `jq` syntax check, `shellcheck`. `fix` auto-fixes markdown only.
- `make deploy` — symlink components into vendor config dirs. Aliases: `global`, `install`. **Run only when the user asks for it.**
- `make uninstall` — remove deployed artefacts via the deployment log.

## Protected file edits

- **Treat `.agents/plugins/marketplace.json` as protected when Codex runs with managed filesystem permissions.** Read it for context, then attempt at most one exact-context `apply_patch` for the intended JSON field.
- **Escalate through the user when the approval state blocks the edit.** If the patch is rejected, times out, or cannot ask for usable escalation, stop and ask the user to change the approval/sandbox state and then tell you to retry. Do not spend turns on shell write workarounds while the harness blocks writes.
- **Use a tightly scoped write after the user changes permissions.** Once the user switches to a state that allows the edit, retry the exact file update and verify with `make lint`.

`CHANGELOG.md` is git-history-derived. Update it only through the `update_changelog` skill, run on demand. Don't hand-edit CHANGELOG entries as part of other work. Committing the skill's output is fine.

This repo manages upcoming work and todos with the `task` skill (`/task`). Live items (`open`, `checked`, `ready`, `implemented`, `audited`) live in `tasks/`; terminal items (`finished`, `deferred`) move to `tasks/archive/`. Task files record `reported-by`, and implemented work records `implemented-by`.

Task files stay agent-harness agnostic. When a task needs standing repo instructions, cite them as the **repo rules** or **standing repo rules** rather than naming `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, or another harness-specific file. Name a harness file in a task only when that file itself is the implementation target.

## Committing

**Lint clean before every commit.** Run `make lint` before creating any commit. When it flags something, run `make fix` for the auto-fixable markdown and correct the rest by hand, then re-run `make lint`, repeating until it passes with no issues. Create the commit only after that clean pass.

## Editing a skill

1. Edit `plugins/<plugin>/skills/<name>/SKILL.md`. Keep the directory name, the frontmatter `name:`, and the H1 heading aligned.
2. When the skill list changes, also update the plugin's `README.md`, both `plugin.json` files, the root `README.md`, and marketplace registrations.
3. Lint clean before committing (see **Committing**).

## Adding a plugin

1. Create `plugins/<new_plugin>/` with `.codex-plugin/plugin.json`, `.claude-plugin/plugin.json`, `README.md`, and a `skills/` directory.
2. Register the plugin in the marketplace files under `plugins[]`.
3. Update the root `README.md` layout tree and **Plugins** bullet list.

## Regression test harnesses

- **When the user says "tests" (or similar), run both skill surfaces unless the user narrows scope.** Run bundled-script tests under `tests/<skill>/script_tests/run.sh` and skill-behavior evals under `tests/<skill>/evals/evals.json`. Report both surfaces before claiming a skill is in good shape.
- **One harness per skill under `tests/<skill_name>/`.** The whole `tests/` tree is in `.gitignore` and excluded from `make lint`; nothing in it gets committed. See `tests/README.md` for the full layout.
- **Prefer the skill-creator-aligned pattern for new harnesses.** Keep evals in `evals/evals.json`, fixtures in `evals/fixtures/`, run output in `workspace/iteration-N/`, and script unit tests in `script_tests/`.
- **`tests/wiki/` uses the legacy two-layer pattern.** Keep it as-is until its next significant iteration; create new harnesses with the skill-creator-aligned pattern.
- **Test every skill change in the same session.** Add the tight scenarios and targeted harness coverage needed to validate the change, then run the relevant existing suite. Put only broader, exploratory harness expansion that exceeds the change's regression needs in its own session.
