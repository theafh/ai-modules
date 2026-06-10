---
description: Extend the archive flow's inbound-link re-pointing to scan tasks/archive/ as well as open tasks, so no link breaks when a task moves to archive.
scope: "task_* family skills"
created: 2026-06-09T12:34:16
updated: 2026-06-10T20:50:09
status: implemented
---

# Archive-aware inbound link scan at close-out

## Goal

Closing a task breaks zero links: the archive flow's cross-reference step
scans `tasks/archive/` as well as open tasks for inbound links to the file
being moved, and re-points every hit in the same close-out — links from
archived tasks get the same treatment as links from open ones.

## Context

- Evidence: the one observed mass-breakage event left ten blocking
  broken-link findings — already-archived tasks linked a then-open task via
  `../<file>.md`, the pre-move scan covered only open tasks, and every one of
  those links shattered when the target archived. A close-out with one
  inbound link took ~8 tool calls; the one that hit the stale archive inbound
  links took ~21.
- Both edit sites currently name the open-only scan (verified on disk,
  2026-06-10): the base skill's `<archive>` workflow step 4 in
  `task/SKILL.md` says "inbound links from other open tasks", and
  `task_finish/SKILL.md`'s workflow step 4 says the same.
- Three archive→open links exist in the tree today (e.g.
  `tasks/archive/task-skill_cross-link-discipline.md` links the open
  positive-task-body-rule task). They are legal and stay as they are: the
  widened scan re-points them whenever their targets archive.
- The safety net for anything that still slips is already in place: broken
  links are blocking lint findings resolved when surfaced, and `task_fix`
  repairs them tree-wide. A predictive lint warning stays out of scope —
  detection machinery adds nothing once the move itself re-points both
  directions.

## Approach

- Widen the base `<archive>` step-4 instruction in `task/SKILL.md`: the
  inbound scan covers both `tasks/` and `tasks/archive/` (e.g. `rg` the
  moving filename across the whole tasks tree), and every hit is re-pointed
  or converted per the step's existing rules.
- Align `task_finish/SKILL.md`'s workflow step 4 with the same
  both-directories wording, deferring to the base `<archive>` rules rather
  than restating them.
- `lint.py` stays unchanged.

## Acceptance

- `<archive>` step 4 in `task/SKILL.md` names the both-directories inbound
  scan; its open-only wording ("from other open tasks") is gone.
- `task_finish/SKILL.md` step 4 carries the same both-directories scan.
