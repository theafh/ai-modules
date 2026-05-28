---
description: Running collection task for test coverage deferred from tasks-skill feature commits — behavioral evals (and any other test growth) that the one-bump-per-commit rule keeps out of the shipping commit.
scope: plugins/ai_dev
created: 2026-05-28T20:17:49
updated: 2026-05-28T23:54:24
status: open
---

# Add deferred test coverage for tasks-skill features

## Goal

A single place to collect and land the test coverage that the repo's
versioning discipline keeps out of feature commits. Per `CLAUDE.md`
("Don't expand a harness in the same session that ships a skill change"
and one-bump-per-commit), behavioral evals and other test growth ride in
their own commit rather than the commit that ships the feature. This task
accumulates those deferred items and is finalized when its open items are
covered and passing.

## Context

The tasks skill harness lives at `tests/tasks/` and follows Pattern A
(skill-creator-aligned) — see `tests/CLAUDE.md` and `tests/git_commit/`
for the reference layout. The whole `tests/` tree is gitignored, so
"commit" here means session discipline, not a tracked artefact.

Two surfaces:

- **Bundled scripts** — `tests/tasks/script_tests/run.sh` already covers
  `lint.py` (naming, frontmatter, status/location, and the birth-time
  cross-check). This surface is current.
- **Skill behavior** — the SKILL prose that drives the agent. This is the
  surface that needs evals under `tests/tasks/evals/` (canonical
  skill-creator schema: `id`, `prompt`, `expected_output`, `files`,
  `expectations[]`), run out-of-band via skill-creator's `run_eval`.

### Open items to cover

1. **Trustworthy timestamps** (from
   [task-skill_trustworthy-timestamps](archive/task-skill_trustworthy-timestamps.md),
   implemented): the SKILL now tells the model to stamp `created`/`updated`
   from `date +%Y-%m-%dT%H:%M:%S` rather than fabricating. Needs a
   behavioral eval proving the agent runs `date` (or otherwise stamps a
   value matching the real wall clock) instead of inventing a time.
2. **The `task` family build-out** — as the planned sibling skills land,
   each ships its own behavioral eval here in its own commit:
   [the rename](archive/task-skill_rename-tasks-to-task.md),
   [task_create](archive/task-skill_create-sibling-skill.md),
   [task_check](archive/task-skill_check-sibling-skill.md),
   [task_health](archive/task-skill_health-sibling-skill.md),
   [task_audit](archive/task-skill_audit-sibling-skill.md),
   [task_implement](archive/task-skill_implement-sibling-skill.md),
   [task_finish](archive/task-skill_finish-sibling-skill.md). Add a scenario
   per skill (e.g. `task_check` flags an under-specified fixture task;
   `task_audit` emits `Gaps:` against a task with a missing test;
   `task_finish` closes a task and re-points the links the move breaks).
   **All six focused siblings — `task_create`, `task_check`,
   `task_implement`, `task_audit`, `task_finish`, and `task_health` — have
   shipped (each 1.0.0), so their behavioral evals are all now concretely
   due; none remain unbuilt.** The simplest is `task_create`'s: a focused single-create prompt yields
   one lint-clean task file with `created`/`updated` stamped from `date`,
   and no second task or broader workflow is run.
3. **Trigger-eval split across the `task` family** (a distinct axis from the
   behavioral evals above — see `tests/trigger_evals/` and `tests/CLAUDE.md`).
   The focused siblings each overlap the base `task` skill's broad verbs
   (create / implement / finish / defer / archive / audit), so the split
   needs validation that mirrors the wiki/wiki_import precedent: a focused
   single-purpose phrasing routes to the right sibling — "make a task for X"
   → `task_create`, "is this task ready to build?" → `task_check`,
   "implement this task" → `task_implement`,
   "finish / defer / archive this task" → `task_finish`, "is this task
   really done?" → `task_audit`, "health-check / clean up the backlog" →
   `task_health` — while broad or ambiguous backlog phrasings route to the
   base `task` skill, with no family regression. Add a
   `tests/trigger_evals/task.json` set (queries with `expected_skill` of
   `task` / `task_create` / `task_check` / `task_implement` / `task_finish` /
   `task_audit` / `task_health` / `null`) and sharpen whichever sibling
   description is bleeding. This carries forward the deferred trigger-eval
   acceptance of every shipped sibling — `task_create` (item 3), `task_check`
   (item 4), `task_implement` (item 5), `task_finish` (item 5), `task_audit`
   (item 4), and `task_health` (item 5) — none validated in the commit that
   shipped it.

## Approach

For each open item, add a scenario to `tests/tasks/evals/evals.json` plus
a per-eval `fixtures/<name>/setup.sh` that stages a sandbox tasks tree,
following `tests/git_commit/evals/` as the template.

Trustworthy-timestamps eval specifics:

- **Prompt**: ask the agent to create a task in the staged sandbox.
- **Grade on filesystem state, not prose**: after the run, read the new
  task's `created`/`updated` and assert they sit within a tolerance (e.g.
  a few minutes) of the real wall clock captured at run time — i.e. the
  agent stamped a real value, not a fixed/fabricated one like
  `14:30:00`. The bundled birth-time check (`lint.py`) is the natural
  oracle: a fabricated time-of-day would drift past the one-hour
  threshold and warn, a real one stays clean.
- Keep the sandbox-isolation fail-safes (no writes outside the sandbox)
  per `tests/CLAUDE.md`.

For the trigger-eval axis, follow `tests/trigger_evals/` rather than
`tests/tasks/evals/`: author `tests/trigger_evals/task.json` and run it via
that harness's `run.py`, reading the precise/family split per
`tests/CLAUDE.md`. Acting on a family-only pass usually means sharpening the
*sibling* description that is encroaching, not the expected one.

Append further scenarios here as later tasks-skill features ship without
their eval.

## Acceptance

- `tests/tasks/evals/evals.json` exists with at least the
  trustworthy-timestamps scenario, following the canonical schema.
- The eval passes: across N samples the agent stamps `created`/`updated`
  from the real wall clock (within tolerance), and the staged tasks tree
  lints clean — no birth-time drift warning.
- `tests/tasks/script_tests/run.sh` continues to pass with no regression.
- A `tests/trigger_evals/task.json` set exists and passes: each shipped
  focused sibling (`task_create`, `task_check`, `task_implement`,
  `task_finish`, `task_audit`, `task_health`) wins its own single-purpose
  phrasings, broad or ambiguous backlog phrasings route to the base `task`
  skill, with no precise regression elsewhere in the family.
- Each item's eval lands in its own commit, separate from the feature it
  covers.
