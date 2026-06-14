---
description: Add a `task_create` sibling skill — a focused, low-ceremony entry point that creates exactly one well-formed task file, delegating naming/frontmatter/lint rules to the base `task` skill.
scope: plugins/ai_dev
created: 2026-05-28T20:25:06
updated: 2026-05-31T00:20:09
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Add the `task_create` sibling skill

## Goal

A narrow skill whose only job is to create a single task file fast and
correctly. It is the easy on-ramp: the user says "make a task for X" and
gets one conformant file with no broader workflow. The base `task` skill
already covers create-as-part-of-everything; `task_create` exists so a
one-shot creation triggers a focused skill rather than loading the whole
backlog-management surface.

## Context

Depends on [the rename](task-skill_rename-tasks-to-task.md) (sibling skills
are named `task_*`). The base skill's `<create>` workflow
(`plugins/ai_dev/skills/task/SKILL.md`, the `<gather>`/`<scope>`/`<name>`/
`<write>`/`<lint_after_create>` steps) is the authority for naming,
frontmatter, the `date`-stamped `created`/`updated`, the body sections, and
the post-write lint. `task_create` should **reuse** those rules by pointing
at the base skill, not restate them — avoid drift between the two
descriptions.

The trigger tension is real: the base `task` description already claims
"create, write, capture … a task". `task_create` must carve out only the
*single-file, no-other-workflow* creation intent without stealing the base
skill's broader triggers. Run `tests/trigger_evals/` to tune the split
(model the wiki/wiki_import precedent — siblings sharpened away from each
other's territory).

## Approach

1. New skill dir `plugins/ai_dev/skills/task_create/` with `SKILL.md`
   (pseudo-XML, positive language per the repo conventions).
2. Body: one-question gather if context is thin → pick scope + collision-safe
   name → run `date` once → write the file with the standard frontmatter and
   body sections → `python3 scripts/lint.py --quiet`. Reference the base
   skill for the actual rules rather than duplicating them.
3. No new bundled scripts — reuse `discover_tasks.sh`/`init_tasks.sh`/
   `lint.py` from the base skill (same plugin, installed together).
4. Register in `plugins/ai_dev/README.md`, root `README.md`, both
   `plugin.json` files, and `marketplace.json`. New skill ships at 1.0.0;
   the plugin meta bumps lockstep (adding a skill counts as a plugin edit).

## Acceptance

- `task_create` triggers on a focused single-task creation request and
  produces one lint-clean task file with `created`/`updated` stamped from
  `date`.
- It does not restate the base skill's naming/frontmatter rules — it defers
  to them.
- Trigger evals show `task_create` and the base `task` skill split cleanly
  on single-create vs broader-workflow phrasings, no regression in the
  family.
- `make lint` and the deploy dry-run pass; plugin meta bumped lockstep.

## Related

- Base: [the rename](task-skill_rename-tasks-to-task.md).
- Peers: [task_check](task-skill_check-sibling-skill.md),
  [task_health](task-skill_health-sibling-skill.md),
  [task_audit](task-skill_audit-sibling-skill.md),
  [task_implement](task-skill_implement-sibling-skill.md).
- Tests tracked in
  [task-skill_testing-new-features](task-skill_testing-new-features.md).
