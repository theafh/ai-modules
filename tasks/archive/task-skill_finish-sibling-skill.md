---
description: Add a `task_finish` sibling skill that closes out one task — set status, bump updated, git mv to archive/, re-point links, re-lint — the action counterpart to the read-only task_audit gate.
scope: plugins/ai_dev
created: 2026-05-28T22:07:10
updated: 2026-05-29T00:13:50
status: implemented
---

# Add the `task_finish` sibling skill

## Goal

A skill that **finishes a single task**: it performs the close-out — set
`status` to `implemented` (work done and shipped) or `deferred` (parked),
bump `updated` from `date`, `git mv` the file to `archive/`, re-point every
cross-reference the move touches, and re-lint to a clean tree. It is the
*action* counterpart to [task_audit](task-skill_audit-sibling-skill.md),
which is the read-only *gate* ("is this genuinely done?"). The user says
"finish this task", "mark X done", "defer Y", or "archive this task" and gets
the task correctly closed out — the skill form of the base skill's
`<archive>` workflow, triggerable on its own.

## Context

Depends on [the rename](task-skill_rename-tasks-to-task.md) (sibling
skills are named `task_*`). The base `task` skill's `<archive>` workflow
(`plugins/ai_dev/skills/task/SKILL.md`) is the authority for the five
close-out steps and stays the single source of truth — `task_finish` defers
to it rather than restating it, exactly as
[task_create](task-skill_create-sibling-skill.md) defers to
`<create>`.

Why this is its own skill rather than part of `task_audit`:

- **Audit verifies; finish acts.** Bundling the archive move into `task_audit`
  conflated a read-only check with a state change. Splitting them keeps each
  skill single-purpose and lets a user verify without committing to a close,
  or close without re-running a full audit.
- **Finish owns both closure paths.** `task_audit`'s "archive on a clean pass"
  framing only fits the `implemented` case. **Deferring** a task — parking or
  dropping it — is also a close-out into `archive/`, and has nothing to do
  with an audit. `task_finish` is the natural home for both `implemented` and
  `deferred`.

The trigger tension mirrors `task_create`: the base `task` description already
claims "finish, complete, implement, defer, archive". `task_finish` must carve
out the *single-task close-out* intent without stealing the base skill's
broader triggers. Tune the split with `tests/trigger_evals/` (tracked in
[task-skill_testing-new-features](../task-skill_testing-new-features.md)).

Natural chain: `task_create` → `task_check` → `task_implement` → `task_audit`
(verify) → `task_finish` (close).

## Approach

1. New skill dir `plugins/ai_dev/skills/task_finish/` with `SKILL.md`
   (pseudo-XML, positive language). Keep it thin and deferential like
   `task_create`.
2. Body: identify the target task → decide `implemented` vs `deferred` (ask
   when ambiguous) → for the `implemented` path, offer/expect a `task_audit`
   pass first so a task is only closed once its claims are verified → run the
   base skill's `<archive>` five steps (status, `date`-bumped `updated`,
   `git mv`, re-point cross-references, re-lint). Point at the base skill for
   the actual rules rather than duplicating them.
3. No new bundled scripts — reuse `discover_tasks.sh` / `lint.py` from the
   base skill (same plugin, installed together).
4. Register in `plugins/ai_dev/README.md`, root `README.md`, and bump the
   `ai_dev` plugin meta (`.claude-plugin/plugin.json`,
   `.codex-plugin/plugin.json`, `marketplace.json`) lockstep. New skill ships
   at 1.0.0.

## Acceptance

- `task_finish` triggers on single-task close-out phrasings ("finish this
  task", "mark it done", "defer this", "archive this task") and performs the
  full five-step close-out, leaving the tree lint-clean.
- It handles **both** `implemented` and `deferred` closures, and re-points the
  cross-references the move touches (inbound links from open tasks, outbound
  links inside the moved file) so the linter reports no broken links.
- For the `implemented` path it expects/offers a `task_audit` verification
  first rather than closing on prose alone.
- It defers the archive rules to the base `task` skill instead of restating
  them.
- Trigger evals show `task_finish` and the base `task` skill split cleanly on
  single-close vs broader-workflow phrasings, no family regression (tracked in
  [task-skill_testing-new-features](../task-skill_testing-new-features.md)).
- `make lint` and the deploy dry-run pass; plugin meta bumped lockstep.
- Ships the shared `task_*` `<family>` map block (all six siblings, marking itself), matching the block in `task_create` / `task_implement`.

## Related

- Base: [the rename](task-skill_rename-tasks-to-task.md); the base
  skill's `<archive>` workflow is the authority.
- Verification gate before me: [task_audit](task-skill_audit-sibling-skill.md).
- The doer: [task_implement](task-skill_implement-sibling-skill.md).
- Pattern to follow: [task_create](task-skill_create-sibling-skill.md)
  (thin, deferential front end over the base skill).
- Tests tracked in
  [task-skill_testing-new-features](../task-skill_testing-new-features.md).
