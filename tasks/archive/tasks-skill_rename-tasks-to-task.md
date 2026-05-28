---
description: Rename the `tasks` skill to `task` everywhere (dir, frontmatter, H1, plugin metas, READMEs, CLAUDE.md), keeping the managed `tasks/` backlog dir name — prerequisite for the task_* sibling skills.
scope: plugins/ai_dev
created: 2026-05-28T20:25:06
updated: 2026-05-28T21:07:26
status: implemented
---

# Rename the `tasks` skill to `task` everywhere

## Goal

The skill currently named `tasks` is renamed to `task` across every
artefact that names it, so the family can grow into `task`, `task_create`,
`task_check`, `task_health`, `task_audit`, `task_implement` — a clean
singular root
matching the `wiki` / `spec_*` families. This is the **prerequisite** for
the four sibling-skill tasks; land it first.

## Context

The skill lives in the `ai_dev` plugin. References found in this repo
(grep `\btasks\b` across plugin + repo meta):

- `plugins/ai_dev/skills/tasks/` — the skill directory (rename to `task/`).
- `plugins/ai_dev/skills/tasks/SKILL.md` — frontmatter `name: tasks` (line 2)
  and the `# tasks` H1 (line 9) and the `<tasks_skill>` root tag; keep the
  directory name, frontmatter `name:`, and H1 aligned per `CLAUDE.md`
  "Editing a skill".
- `plugins/ai_dev/README.md` — skill list entry.
- `README.md` (root) — layout tree + Plugins bullet list.
- `CLAUDE.md` (root) — the tasks-skill pointer ("This repo manages upcoming
  work … with the `tasks` skill (`/tasks`)") and the **product** list under
  "What this repo is not".

**Decision already taken: the managed backlog directory stays `tasks/`.**
The skill is renamed, not the data it manages — exactly as the `wiki` skill
manages a `wiki/` directory. So `discover_tasks.sh`/`init_tasks.sh`/`lint.py`
keep resolving `<root>/tasks`, and only the skill identifier changes. (If a
future decision wants the directory renamed too, that is its own task — do
not fold it in here.)

The bundled script filenames (`discover_tasks.sh`, `init_tasks.sh`) and the
`tasks_path`/`$TASKS` variables refer to the directory, not the skill, so
they stay as-is.

## Approach

1. `git mv plugins/ai_dev/skills/tasks plugins/ai_dev/skills/task` (or plain
   `mv` if untracked).
2. In `SKILL.md`: `name: task`, `# task` H1, and rename the `<tasks_skill>`
   root tag to `<task_skill>`. Leave references to the `tasks/` directory,
   `tasks/archive/`, and the bundled scripts unchanged.
3. Update `plugins/ai_dev/README.md`, the root `README.md` (layout tree +
   Plugins list), and the two `CLAUDE.md` mentions.
4. Re-point any task file whose `scope:` names the old skill dir
   `plugins/ai_dev/skills/tasks` to `plugins/ai_dev/skills/task` (currently
   `tasks-skill_link-resolution-project-root-fallback.md` and
   `tasks-skill_lossless-doc-conversion-check.md`). The linter blocks on a
   `scope:` path that no longer exists, so this must ride in the rename
   commit. Leave alone scopes that point at `tasks/` the backlog directory —
   only the skill-dir path changes.
5. This is a plugin edit: bump `ai_dev` `version` in
   `plugins/ai_dev/.claude-plugin/plugin.json`,
   `plugins/ai_dev/.codex-plugin/plugin.json`, and the `ai_dev` entry in
   `.claude-plugin/marketplace.json` (lockstep), and bump the skill
   `version` in the renamed `SKILL.md` — both in the rename commit.
6. The Skill `description:` keeps its trigger surface; only the name token
   changes. Consider whether `/tasks` invocations and the `tasks`,
   `todos`, `the task list` trigger phrases still read correctly under the
   `task` name (they do — they describe usage, not the identifier).

## Acceptance

- No artefact names the skill `tasks` any more; `name:`, H1, root tag, and
  directory are all `task` and aligned.
- The `tasks/` backlog directory, `tasks/archive/`, and bundled scripts are
  untouched; `python3 scripts/lint.py` still resolves `<root>/tasks` and
  runs clean.
- `make lint` and `./deployment/deployment.sh --global --dry-run` pass.
- `ai_dev` plugin meta (three files) and the renamed skill version bumped in
  lockstep, in the same commit.
- Trigger evals for the renamed skill still fire (run
  `tests/trigger_evals/` if the description changed materially; the name
  token alone usually does not need it).

## Related

- Prerequisite for [task_create](../tasks-skill_create-sibling-skill.md),
  [task_check](../tasks-skill_check-sibling-skill.md),
  [task_health](../tasks-skill_health-sibling-skill.md),
  [task_audit](../tasks-skill_audit-sibling-skill.md), and
  [task_implement](../tasks-skill_implement-sibling-skill.md).
- Test growth (evals) for the renamed skill is tracked in
  [tasks-skill_testing-new-features](../tasks-skill_testing-new-features.md).
