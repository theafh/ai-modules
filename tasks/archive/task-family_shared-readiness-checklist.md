---
description: Move the readiness checklist into the base task skill as the single source, have task_create self-check drafts against it pre-write, and task_check assess by reference.
scope: "task_* family skills"
created: 2026-06-09T10:45:16
updated: 2026-06-10T20:50:09
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Shared readiness checklist: create writes what check judges

## Goal

`task_create` produces files that already pass `task_check` on the first run.
The readiness checklist — today spelled out only inside `task_check` — lives
once in the base `task` skill; `task_create` judges its draft against it before
writing the file, and `task_check` assesses against the same single source
instead of carrying its own copy.

## Context

Files in play, all under `plugins/ai_dev/skills/`:

- `task_check/SKILL.md` — its `<assessment>` holds the full readiness lens
  today: the structural check (single H1 plus Goal / Context / Approach /
  Acceptance, valid frontmatter, run first) and the content items (scope
  sizing, focus, complexity, contradictions, ambiguity / under-specification,
  over-specification, negation-framed behaviour).
- `task/SKILL.md` — the family's source of truth for shared rules; receives
  the checklist as a named section.
- `task_create/SKILL.md` — its `<workflow>` gathers, writes, and lints, with
  no step that judges the draft against that lens; its `<authority>` section
  already consumes base-skill rules by reference (`<lossless_conversion>` is
  the pattern to copy).

Motivation, from transcript analysis of ~24 `task_check` runs (2026-05/06):
checked tasks averaged ~2.7 check→fix rounds before "No issues found", and
first-round findings were dominated by defects visible in the draft alone —
the same rule stated in two sections with paraphrase drift, unresolved
either/or forks in the Approach, a Goal promising more than the Approach
delivers, soft acceptance wording. A pre-write self-check against the same
lens collapses those rounds into the create pass.

Ordering — implement this task after these prerequisites have landed:

- [task-family_implementer-input-bar.md](task-family_implementer-input-bar.md)
  rewrites the bar sentence that opens `task_check`'s `<assessment>`; with it
  landed, this relocation moves the settled sentence unchanged.
- [task-family_positive-task-body-rule.md](task-family_positive-task-body-rule.md)
  lands the positive-framing authoring rule in the base `<body>`; the
  relocated negation-framed-behaviour item then points at that rule instead
  of restating it.
- [task-family_single-statement-open-decision.md](task-family_single-statement-open-decision.md)
  lands the state-once, decide-or-label, and illustrate authoring rules in
  the base `<body>`; the relocated contradiction, ambiguity, and
  over-specification items then point at those rules instead of restating
  them.

## Approach

- Add the checklist to `task/SKILL.md` as a dedicated, referenceable section
  (a name like `<readiness_checklist>` works), placed with the `<file_format>`
  / `<body>` material it governs. Move `task_check`'s structural-check-first
  ordering and content items there verbatim — a lossless relocation; new
  checklist items are separate follow-up work.
- Rewrite `task_check`'s `<assessment>` to assess against that base section by
  reference, keeping everything else intact: the one-shot bar, the read-only
  stance, and the ranked `# General assessment` / `## Issues` output contract.
- Insert a self-check step into `task_create`'s `<workflow>` between gathering
  and writing: judge the draft against the base checklist and resolve every
  finding, so the file written already passes the lens `task_check` will
  apply. Reference the checklist; restate none of its items.
- Name the checklist in both siblings' `<authority>` lists alongside the
  base-skill rules they already consume.

## Acceptance

- `task/SKILL.md` carries the checklist as a named section, and a distinctive
  phrase from an item's definition (e.g. "most compact scope") resolves to
  exactly one file among the family's SKILL.mds — the base one.
- `task_check`'s `<assessment>` defers to the base checklist and spells out
  none of the relocated items itself.
- `task_create`'s `<workflow>` contains the pre-write self-check step pointing
  at the same base section.
