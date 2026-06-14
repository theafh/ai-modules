---
description: Running collection task for test coverage deferred from tasks-skill feature commits — behavioral evals (and any other test growth) that the one-bump-per-commit rule keeps out of the shipping commit.
scope: plugins/ai_dev
created: 2026-05-28T20:17:49
updated: 2026-05-31T00:20:09
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
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
  `discover_tasks.sh`, `init_tasks.sh`, and the full `lint.py` rule set
  (naming, frontmatter, status/location, scope, links, page size,
  standard-markdown). This surface is current.
- **Skill behavior** — the SKILL prose that drives the agent. This is the
  surface that needs evals under `tests/tasks/evals/` (canonical
  skill-creator schema: `id`, `prompt`, `expected_output`, `files`,
  `expectations[]`), run out-of-band via skill-creator's `run_eval`.

### Open items to cover

1. **Trustworthy timestamps** (from
   [task-skill_trustworthy-timestamps](task-skill_trustworthy-timestamps.md),
   implemented): the SKILL now tells the model to stamp `created`/`updated`
   from `date +%Y-%m-%dT%H:%M:%S` rather than fabricating. **Covered** — the
   `create` eval in `tests/tasks/evals/evals.json` grades this on filesystem
   state: `grade.sh` asserts `created == updated` and `created_is_recent`
   against the run-start epoch in `.eval_started_at`, proving the agent
   stamped a real wall-clock value instead of inventing a time.
2. **The `task` family build-out** — each shipped sibling skill carries its
   own behavioral eval here:
   [the rename](task-skill_rename-tasks-to-task.md),
   [task_create](task-skill_create-sibling-skill.md),
   [task_check](task-skill_check-sibling-skill.md),
   [task_fix](task-skill_health-sibling-skill.md) (shipped as
   `task_health`, since
   [renamed to `task_fix`](task-skill_rename-health-to-fix.md)),
   [task_audit](task-skill_audit-sibling-skill.md),
   [task_implement](task-skill_implement-sibling-skill.md),
   [task_finish](task-skill_finish-sibling-skill.md).
   **Covered** — all six focused siblings have shipped (each 1.0.0) and a
   scenario for each now lives in `tests/tasks/evals/evals.json`: `create`
   (one lint-clean task file, no second task or broader workflow), `check`
   (flags an under-specified fixture task), `implement`, `audit_gaps`
   (emits `Gaps:` against a task with a missing test), `audit_clean`,
   `finish` (closes a task and re-points the links the move breaks), and
   `health` (the backlog-wide repair eval, named for the skill's former
   `task_health` identity — now `task_fix`).
3. **Trigger-eval split across the `task` family** (a distinct axis from the
   behavioral evals above — see `tests/trigger_evals/` and `tests/CLAUDE.md`).
   **Authored and handed off.** The `tests/trigger_evals/task.json` set now
   exists (queries with `expected_skill` of `task` / `task_create` /
   `task_check` / `task_implement` / `task_finish` / `task_audit` /
   `task_fix` / `null`) and has a measured baseline of **precise 14/25,
   family 20/25** (run `tests/trigger_evals/results/task/2026-05-29_233532/`).
   The ongoing work of *improving* that routing — and the settled finding
   that description-sharpening regresses while naming (the `task_health` →
   `task_fix` rename) is the working lever — now lives in its own task,
   [task-skill_sibling-trigger-routing](task-skill_sibling-trigger-routing.md).
   This carried forward the deferred trigger-eval acceptance of every shipped
   sibling, none validated in the commit that shipped it.

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
  `14:30:00`. `grade.sh` does this directly, comparing `created` against
  the run-start epoch in `.eval_started_at` (the birth-time lint check
  that once served as the oracle has been removed — see
  [task-skill_drop-birthtime-drift-check](task-skill_drop-birthtime-drift-check.md)).
- Keep the sandbox-isolation fail-safes (no writes outside the sandbox)
  per `tests/CLAUDE.md`.

The trigger-eval axis has been split out: `tests/trigger_evals/task.json`
is authored and baselined, and the work of raising its routing rate lives
in [task-skill_sibling-trigger-routing](task-skill_sibling-trigger-routing.md).
Note its settled finding before touching descriptions — sharpening a
*sibling* description to cede verbs regressed both precise and family
rates; the working lever is naming (the `task_fix` rename), not more
description text.

Append further scenarios here as later tasks-skill features ship without
their eval.

## Acceptance

- `tests/tasks/evals/evals.json` exists with at least the
  trustworthy-timestamps scenario, following the canonical schema.
- The eval passes: across N samples the agent stamps `created`/`updated`
  from the real wall clock (within tolerance), and the staged tasks tree
  lints clean.
- `tests/tasks/script_tests/run.sh` continues to pass with no regression.
- A `tests/trigger_evals/task.json` set exists (it does, with a measured
  baseline). Raising its routing rate is tracked separately in
  [task-skill_sibling-trigger-routing](task-skill_sibling-trigger-routing.md);
  acceptance for *that* axis lives there, not here.
- Each item's eval lands in its own commit, separate from the feature it
  covers.
