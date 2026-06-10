---
description: "Add three authoring rules to the base skill's body: rules stated once with sections pointing, one labeled open decision at most, and examples that illustrate rather than carry."
scope: plugins/ai_dev/skills/task
created: 2026-06-09T12:34:16
updated: 2026-06-10T20:50:09
status: implemented
---

# State once, decide or label, illustrate: body authoring rules

## Goal

Three authoring rules land in the base `task` skill's `<body>`, so create
paths write them and checks judge against them: **state once** — each rule or
decision in a task body is stated exactly once, with other sections pointing
at the statement rather than paraphrasing it; **decide or label** — a body
carries zero unresolved either/or forks, with at most one explicitly labeled
open decision carrying its options and a default; **illustrate** — examples
support the general statement that carries the rule, with specific cases and
incident histories staying brief illustrations rather than load-bearing
content.

## Context

- Evidence from mined `task_check` runs (2026-05/06): paraphrase drift between
  Goal / Approach / Acceptance drove two full three-round check→fix loops —
  the same rule worded differently in two sections, flagged round after round
  until one canonical statement ended the loop. Unresolved forks recurred
  across sessions: "Alternatively / additionally …" approaches left as
  either/or, "Options …. Choose one" with no choice recorded, and dangling
  design forks flagged by the tree fixer as single-shot-readiness gaps.
- The illustrate rule is the same lesson the family fixed at skill level,
  applied to task bodies: a specific case codified as the rule had to be
  re-generalized later; the general statement carries, the case illustrates.
- The backlog already practices the open-decision label organically:
  `tasks/wiki_non-english-languages-ascii-slugs.md` marks its tag-folding
  choice as "the one genuine open decision". The rule makes that labeling the
  norm.
- Base-only edit: the rules land in `task/SKILL.md` `<body>` beside the
  section definitions; create paths apply `<body>` through existing
  authority, and `task_check` judges against it. No sibling SKILL.md changes.
- Ordering:
  [task-skill_shared-readiness-checklist.md](task-skill_shared-readiness-checklist.md)
  follows this task — its relocated contradiction, ambiguity, and
  over-specification items then point at these rules instead of restating
  them. Implement this task first.

## Approach

- Add the three rules to `task/SKILL.md` `<body>` as a short authoring block:
  - **State once:** a rule, constraint, or decision appears in exactly one
    place in the body; Goal, Approach, and Acceptance reference that one
    statement instead of re-wording it.
  - **Decide or label:** resolve every either/or before the file is written;
    when one decision genuinely stays open, label it explicitly (e.g. "Open
    decision:"), list the options, and name the default an implementer takes
    without further input. One labeled open decision is the ceiling.
  - **Illustrate:** the general statement carries each rule or requirement;
    specific cases, incident histories, and dated references appear as brief
    illustrations supporting it. A body whose meaning lives only in an
    example has the altitude inverted.
- Keep all three rules at authoring-rule altitude: general formulations, with
  specific cases as illustrations.
- Siblings stay diff-free; inheritance through existing authority is the
  delivery mechanism.

## Acceptance

- `task/SKILL.md` `<body>` carries all three rules: single statement with
  sections pointing, the labeled-open-decision ceiling with options and a
  default, and examples as illustrations of the general statement.
- The rules read as general authoring guidance with specific cases as
  illustrations.
