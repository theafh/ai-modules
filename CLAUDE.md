# CLAUDE.md

**ai-modules is a meta-repository.** It defines AI components (skills, agents, commands, hooks) and packages them as plugins. Here **command** means the legacy standalone command artefact the deployer can still install (for example a Claude slash-command file under `commands/`), not a shell command and not a skill that is merely slash-invocable. Treat every `SKILL.md`, `plugin.json`, and `marketplace.json` as a published artefact: edits propagate to every machine that re-runs `make deploy`.

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
styles/                           # tracked output styles (repo-root; not a plugin component)
deployment/                       # deploy script + per-tool config
tests/                            # regression harnesses (authored files tracked; run output gitignored)
Makefile                          # task entry point
.markdownlint.jsonc               # markdown lint config (MD033 off, pseudo-XML is intentional)
```

## Authoring conventions

- **Use pseudo-XML inside skill prompts** (`<role>`, `<objective>`, `<policy>`, `<output_contract>`). Reference: `plugins/ai_dev/skills/ai_instruction_formatting/SKILL.md`.
- **Use positive, action-oriented language** in skill prose and instructions. Reference: `plugins/ai_dev/skills/ai_instruction_writing/SKILL.md`.
- **Write skill descriptions for both audiences.** The `description:` frontmatter is read before the body is loaded by an LLM router and by users browsing skills. Serve both needs deliberately: give the user a precise compact summary of what the skill is about and how it differs from neighbors, then give the router keyword-rich `Use when` trigger contexts, prompt phrases, artefacts, file types, and invocation boundaries. Keep implementation workflow details in the body.
- **Keep the toolchain to Make + shell + Markdown**, with jq, git, and Python 3 as accepted standing dependencies. Add further languages, package managers, or build steps only when the user explicitly asks for them.
- **Match snake_case naming** for skill and plugin directories.
- **Name skills and agents by invocation mode and collision risk.** A skill that is the only entry point for its capability keeps the ordinary family-first name, even when it delegates to agents (`wiki_fix`). Use `<family>_auto_<rest>` for an agent-delegating automation skill when it needs to sit beside a classical/manual skill with the same capability or subset (`task_auto_implement` beside `task_implement`). A spawned agent leads with `auto_` and ends with the family token (`auto_<role>_<family>`, e.g. `auto_implementer_task` or `auto_shaper_wiki`) and is not intended to be invoked by the user.
- **Write deployment-agnostic cross-references.** Reference sibling artefacts by name (`auto_shaper_wiki`, `format_markdown`) rather than by plugin name, marketplace, or installed path.
- **Bundle a skill's helper scripts inside the skill.** A script that supports a skill lives at `plugins/<plugin>/skills/<skill>/scripts/<name>` and is referenced from its `SKILL.md` by the skill-relative path `scripts/<name>`. The plugin is the unit of distribution, so a script placed at the repo root or wired into the root `Makefile` is invisible to every deployment path except an in-place checkout. Add a repo-root `scripts/` directory only for repo-wide tooling that belongs to no single skill, and only when explicitly asked.
- **Author a skill-family rule once in the family's base skill.** When a rule should govern a whole skill family (for example the `task_*` family), write it once in the base/hub skill so the front-end siblings inherit it through their `<authority>` reference instead of each carrying a copy. Pair enforcement with the canonical rule rather than restating it: a maintenance sibling such as `task_fix` carries a surface-and-propose advisory that points back at the base rule.

## Versioning

- **Ship a new skill, agent, or plugin at 1.0.0.** In the commit that first introduces it, leave the version at 1.0.0 and add no bump.
- **Bump once per commit, with the change, and only at commit time.** When a commit edits an existing skill, agent, or plugin, raise its `version` in that commit. Do not bump while iterating, and do not add version-bump steps to task files, plans, or pre-commit notes.
- **Use patch increments for minor maintenance changes.** For a small follow-up, wording fix, or environment-specific hint, advance only the patch component.
- **Advance the plugin minor when adding a skill or agent.** Adding a skill or agent to an existing plugin advances the plugin's minor component (`x.Y.0`); the new skill or agent itself still ships at 1.0.0. Patch stays for maintenance-only edits of already-shipped surfaces.
- **Plugin meta stays lockstep.** When a skill or agent `version:` rises, or a skill or agent is added to an existing plugin, raise the matching plugin's `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, and both marketplace registrations (`.claude-plugin/marketplace.json`, `.agents/plugins/marketplace.json`) to the same new plugin version in the same commit.

## Common tasks

- `make help`: list every target.
- `make lint` / `make fix`: runs `markdownlint`, `jq` syntax check, `shellcheck`. `fix` auto-fixes markdown only.
- `make deploy`: copy components into vendor config dirs. Aliases: `global`, `install`. **Run only when the user asks for it.**
- `make uninstall`: remove deployed artefacts via the deployment log.

`CHANGELOG.md` is git-history-derived. Update it only through the `update_changelog` skill, run on demand. Don't hand-edit CHANGELOG entries as part of other work. Committing the skill's output is fine.

This repo manages upcoming work and todos with the `task` skill (`/task`). Live items (`open`, `checked`, `ready`, `implemented`, `audited`) live in `tasks/`; terminal items (`finished`, `deferred`) move to `tasks/archive/`. Task files record `reported-by`, and implemented work records `implemented-by`.

This repo keeps its durable knowledge in `wiki/`, managed through the `wiki` skill family. It holds two things the shipped artefacts are the wrong container for: how this repository works and why, and the dated, sourced research on how each target harness discovers artefacts, parses frontmatter, names tools, runs hooks, and carries standing instructions. Read `wiki/index.md` before starting harness work, and write a newly verified fact back there with its date and source. A rule that changes what an agent does at authoring time stays in the skill; anything an agent needs in another repository stays in the skill or its `references/`, because the wiki travels nowhere else.

Task files stay agent-harness agnostic. When a task needs standing repo instructions, cite them as the **repo rules** or **standing repo rules** rather than naming `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, or another harness-specific file. Name a harness file in a task only when that file itself is the implementation target.

## Committing

**Lint clean before every commit.** Run `make lint` before creating any commit. When it flags something, run `make fix` for the auto-fixable markdown and correct the rest by hand, then re-run `make lint`, repeating until it passes with no issues. Create the commit only after that clean pass.

## Editing a skill

1. Edit `plugins/<plugin>/skills/<name>/SKILL.md`. Keep the directory name, the frontmatter `name:`, and the H1 heading aligned.
2. When the skill list changes, also update the plugin's `README.md`, both `plugin.json` files, the root `README.md`, and marketplace registrations.
3. Lint clean before committing (see **Committing**).

## Adding a plugin

1. Create `plugins/<new_plugin>/` with `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` (set `"skills": "./skills/"`), `README.md`, and a `skills/` directory.
2. Register the plugin in the marketplace files under `plugins[]`.
3. Update the root `README.md` layout tree and **Plugins** bullet list.

## Regression test harnesses

- **When the user says "tests" (or similar), run both skill surfaces unless the user narrows scope.** Run bundled-script tests under `tests/<skill>/script_tests/run.sh` and skill-behavior evals under `tests/<skill>/evals/evals.json`. Report both surfaces before claiming a skill is in good shape.
- **One harness per skill under `tests/<skill_name>/`.** The authored harness is committed and linted; `tests/.gitignore` keeps run output (`workspace/`, `scratch/`, `.eval_cache/`, `results/` logs and run reports, and the staged `wiki/layer2` sandboxes) out of git, and the Makefile's `EXCLUDE` prunes the same subtrees so lint scope matches git scope. Change the two lists together. See `tests/README.md` for the full layout.
- **Prefer the skill-creator-aligned pattern for new harnesses.** Keep evals in `evals/evals.json` (schema: `skill-creator/references/schemas.md`), fixtures in `evals/fixtures/`, run output in `workspace/iteration-N/`, and script unit tests in `script_tests/`. Run evals out-of-band via skill-creator's `scripts.run_eval`; `run_all.sh` drives only the script tests. Reference implementation: `tests/git_commit/`.
- **`tests/wiki/` uses the legacy two-layer pattern.** Keep it as-is until its next significant iteration; create new harnesses with the skill-creator-aligned pattern.
- **Ship the tests a change needs; separate only *unbounded* harness growth.** A skill change lands together with the tight scenario(s) and fixtures that prove *its own* new behavior (the evals a task's acceptance names are part of that change, not something to defer) and with the existing suite re-run to confirm no regression. What belongs in its own session is *unbounded* harness expansion beyond the change: backfilling coverage of pre-existing untested behavior, adding scenarios well past what the change needs, or restructuring the harness. The boundary is scope, not timing: prove this change now and run it, and keep an unrelated coverage sweep from ballooning the same session.
