---
description: Add a rule to the task skills that a task links to another task file only when the link marks a dependency, changes how the work is implemented, or points at a file that will be co-edited.
scope: plugins/ai_dev/skills/task
created: 2026-06-02T21:00:35
updated: 2026-06-02T22:43:40
status: implemented
---

# Make value-only task cross-linking a rule in the task skills

## Goal

Codify, in the task skills, **when one task file should link to another**: only
when the link carries weight. A cross-link earns its place when it marks a
**dependency** (this task builds on, depends on, extends, or must follow
another), when reading the linked task would **change how this task is
implemented**, or when the **linked file will itself be edited** (coordination —
a shared region, a double-edit, competing mechanisms). After this change,
`task_create` writes only value-bearing cross-links, and `task_fix` flags
decorative ones and confirms the load-bearing ones still resolve and still read as
useful. This complements the existing link *mechanics* in `<markdown_policy>`
(standard links, must resolve on disk, no wikilinks) with a *when-to-link*
judgment.

## Context

The rule lives most naturally in the base `task` skill — the single source of
truth the front ends defer to. Files in play, all under `plugins/ai_dev/skills/`:

- `task/SKILL.md` — `<markdown_policy>` (lines ~90–98) already states the link
  *mechanics*: local cross-references are standard markdown links that must
  resolve on disk, no wikilinks. The *when-to-link* judgment belongs right here,
  beside those mechanics.
- `task_create/SKILL.md` — `<authority>` already defers to `task`'s file format;
  its `<workflow>` "Write" step is where the rule applies when filling
  `## Context` and any cross-references.
- `task_fix/SKILL.md` — the whole-tree repair pass; this is where the rule is
  enforced over the existing tree. It defers to the canonical rule in `task`'s
  `<markdown_policy>` for *what* counts and adds only the repair mechanics.

The keep/drop test to encode (a rule of thumb): **would reading the linked task,
or knowing it exists, change how I implement this task or edit this file? If not,
drop the link.**

- **Keep — links that add value:**
  - *Dependency / sequence* — "build X first", "depends on", "extends", "must
    follow X".
  - *Changes implementation* — reading the linked task would change this task's
    approach (e.g. it defines a rubric, format, or interface this task consumes).
  - *Co-edited files* — the linked task will edit an overlapping file or line:
    coordinate a double-edit ("remove this wording in exactly one task"),
    reconcile competing mechanisms, or sequence edits to a shared region.
- **Drop — relatedness-only links:** "see also", "distinct from", "pairs with"
  as bare FYI, and reverse-duplicate pointers where the relationship is already
  stated on the other side — anything where reading the target changes nothing
  about implementing or editing this task.

This rule is the generalisation of a backlog cleanup done this session: the open
task tree's cross-links were assessed one by one; dependency and coordination
links were kept, relatedness-only links dropped. Encoding it stops the judgment
from being re-litigated per cleanup, and keeps both failure modes in check — dead
decorative links *and* over-pruning that strips genuine organisational value.

Coordinate with [task-skill_positive-task-body-rule.md](../task-skill_positive-task-body-rule.md):
it adds a different authoring rule to the **same** base `task` `<body>` guidance
and likewise edits `task_create` and `task_fix`, so the two touch overlapping
regions and should land in a deliberate order. This link is itself an instance of
the "co-edited files" criterion the rule defines.

## Approach

Apply the rule at the source of truth, then reference it from the front ends:

- In `task/SKILL.md`, add a short **cross-link discipline** rule adjacent to
  `<markdown_policy>`'s link mechanics: a task links to another task file only
  when the link marks a dependency, would change how the work is implemented, or
  points at a file that will be co-edited; relatedness-only references are left
  out. Phrase it positively (lead with *when to link*), consistent with the repo's
  `ai_instruction_writing` convention and the positive-task-body rule.
- In `task_create/SKILL.md`, make the "Write" step apply this rule when adding
  `## Context` and cross-references, deferring to `task`'s `<markdown_policy>` as
  authority rather than restating it in full.
- In `task_fix/SKILL.md`, add a cross-link check to the repair pass that **defers
  to the cross-link rule in `task`'s `<markdown_policy>` for the keep/drop test**
  rather than restating it — `task_fix` adds only the repair *mechanics*, following
  its existing surface-vs-autofix split: **surface** any link whose value is a
  judgment call for the user to decide, and auto-remove only the unambiguous case
  (a reverse-duplicate whose relationship is already stated on the linked side).
  Never auto-delete on a value judgment — that is the over-pruning failure mode the
  rule guards against. Confirm dependency/coordination links still resolve and read
  as value-bearing.

Keep the rule a prose authoring convention. A mechanical `lint.py` rule for
link-value stays out of scope — judging whether a link adds value needs judgement
the linter cannot apply, the same boundary the positive-task-body and prose-sweep
tasks draw. The existing link-resolution lint (broken `.md` targets block) stays
as-is, and the wikilink/standard-link mechanics are unchanged.

## Acceptance

- `task/SKILL.md` states the cross-link discipline rule next to the link
  mechanics: link only for dependency, changes-implementation, or co-edited
  files; relatedness-only links are left out. It is phrased positively and passes
  the `ai_instruction_writing` `<self_check>`.
- `task_create/SKILL.md` applies the rule on write by deferring to `task`'s
  `<markdown_policy>`; `task_fix/SKILL.md`, deferring to that same canonical rule,
  surfaces judgment-call cross-links for review and auto-removes only unambiguous
  reverse-duplicates. Neither front end restates the keep/drop criteria.
- The rule passes the test it states — its own one cross-link (to the
  positive-task-body rule) is a coordination link, not decoration.
- `make lint` and `./deployment/deployment.sh --global --dry-run` come back clean.
