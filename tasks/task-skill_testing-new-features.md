---
description: Running collection task for test coverage deferred from tasks-skill feature commits — behavioral evals (and any other test growth) that the one-bump-per-commit rule keeps out of the shipping commit.
scope: plugins/ai_dev
created: 2026-05-28T20:17:49
updated: 2026-05-28T22:07:10
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
   [task_check](task-skill_check-sibling-skill.md),
   [task_health](task-skill_health-sibling-skill.md),
   [task_audit](task-skill_audit-sibling-skill.md),
   [task_implement](task-skill_implement-sibling-skill.md),
   [task_finish](task-skill_finish-sibling-skill.md). Add a scenario
   per skill (e.g. `task_check` flags an under-specified fixture task;
   `task_audit` emits `Gaps:` against a task with a missing test;
   `task_finish` closes a task and re-points the links the move breaks).
   **`task_create` has shipped (1.0.0), so its behavioral eval is the
   first concretely due:** a focused single-create prompt yields one
   lint-clean task file with `created`/`updated` stamped from `date`, and
   no second task or broader workflow is run.
3. **Trigger-eval split for the `task` family** (a distinct axis from the
   behavioral evals above — see `tests/trigger_evals/` and `tests/CLAUDE.md`).
   `task_create` overlaps the base `task` skill's create triggers, so the
   split needs validation that mirrors the wiki/wiki_import precedent: a
   focused single-create phrasing ("make a task for X") routes to
   `task_create`, while list/query/update/finish/archive/lint and
   multi-task phrasings route to `task`, with no family regression. Add a
   `tests/trigger_evals/task.json` eval set (queries with `expected_skill`
   of `task` / `task_create` / `null`) and tune whichever sibling
   description is bleeding. This carries forward acceptance item 3 of
   [task_create](archive/task-skill_create-sibling-skill.md), deferred from the
   commit that shipped the skill.

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
- A `tests/trigger_evals/task.json` set exists and passes: focused
  single-create phrasings route to `task_create`, broader backlog
  phrasings route to `task`, with no precise regression elsewhere in the
  family.
- Each item's eval lands in its own commit, separate from the feature it
  covers.
