---
description: Reference content in task bodies and task_check reports by stable labels and descriptions — soft pointers that survive edits — instead of bare line numbers that drift.
scope: "task_* family skills"
created: 2026-06-09T10:45:16
updated: 2026-06-10T20:50:09
status: implemented
---

# Soft pointers: labels and descriptions instead of line numbers

## Goal

References in task files and in `task_check` issue reports locate content by
durable anchors — a heading, a pseudo-XML tag, a symbol or rule name, a short
quoted phrase, together with the file path — so every pointer stays valid
while the referenced file evolves. A line number may accompany the label, and
the label carries the reference, keeping it independent of drifting line
numbers.

## Context

Evidence from recent check runs:

- `task_check` flagged an approximate line pointer as a drift risk in
  consecutive runs on the open `task-skill_positive-task-body-rule.md` task;
  the resolution kept the section anchor and dropped the line estimate.
- A check→fix round on the since-archived wiki-discovery task inserted a
  line-range reference to a code path that did not exist; deleting the
  reference (rather than explaining it) resolved the ambiguity.
- The convention already appears organically in the backlog:
  `tasks/wiki_meta-prose-in-page-bodies.md` locates an edit with "around line
  944-946 at the time of writing; locate by phrase, not by line number" — the
  rule makes that phrasing the norm and the parenthetical line range
  unnecessary.

Consumers: `task_create` writes `## Context` / `## Approach` pointers;
`task_check` locates each `## Issues` entry inside the checked task;
`task_fix` repairs stale references during tree maintenance. All live under
`plugins/ai_dev/skills/`; the rule text belongs in `task/SKILL.md`, which the
front ends already consume by reference.

Ordering: builds on
[task-skill_shared-readiness-checklist.md](task-skill_shared-readiness-checklist.md)
— implement that task first; the drift-prone-pointer flag then lands as part
of the relocated checklist's ambiguity item.

## Approach

- State the rule once in `task/SKILL.md` `<markdown_policy>`, which already
  owns the cross-reference rules the siblings consume: locate referenced
  content by a stable label — heading, tag, symbol, rule name, or short quoted
  snippet — plus the file path; a line number may accompany the label but
  never carries the reference on its own.
- `task_create` applies the rule when writing body pointers, by reference to
  the base section.
- `task_check` writes each `## Issues` entry locating the problem by label or
  unambiguous description, and treats a task-body reference that leans on a
  bare line number as an ambiguity finding.
- `task_fix` repairs such pointers when sweeping, deferring to the same base
  rule.

## Acceptance

- `task/SKILL.md` states the soft-pointer rule in exactly one place; a
  distinctive phrase of it matches only the base file across the family's
  SKILL.mds.
- `task_check`'s `<output_contract>` locates issues by label or unambiguous
  description.
- `task_create` and `task_fix` name the base rule where they write or repair
  references.
