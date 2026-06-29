---
description: Extend the task-family soft-pointer rule and readiness lens from line-number claims to ordinal list-position anchors ("step 6", "item 3"), which rot when the task edits that list.
scope: plugins/ai_dev/skills/task
created: 2026-06-29T22:26:13
updated: 2026-06-29T22:30:49
status: ready
reported-by: Andreas Hoffmann
---

# Soft-pointer rule bans ordinal list-position anchors, not just line numbers

## Goal

The base `task` skill's soft-pointer rule and its readiness lens cover a second
species of position claim: an **ordinal reference into an ordered or bulleted
list** — "step 6", "item 3", "the second bullet" — that locates a list item by
its position rather than by its own label. A reference instead anchors to the
item's verbatim greppable label — the item's heading text, its bold lead-in, a
symbol or rule name, or a short quoted phrase — together with the file path, so
the pointer survives the list being reordered, extended, or trimmed. This is
especially load-bearing when the referencing task's own work edits that list
(inserts, removes, or reorders items): an ordinal fixed at authoring time
silently points at the wrong item once the edit lands, while a label fails
loudly — grep finds nothing — when the item is reworded. The user-visible
outcome is that task authors and `task_check` treat an ordinal list-position
anchor exactly as they already treat a bare line number: a position claim to
replace with a label.

## Context

The soft-pointer rule lives in the base `task` skill's `<markdown_policy>`, with
the matching review lens in its `<readiness_checklist>` **Ambiguity /
under-specification** item. Three finished predecessors built and hardened that
rule, but every one of them addresses **line-number** position claims only — a
`:N` path suffix, a bare `line N`, an `around lines N–M` range, the tilde and
capital-`Lines` variants — and none names an item's ordinal position inside a
list:

- [task-skill_soft-pointer-references.md](archive/task-skill_soft-pointer-references.md)
  established locate-by-label over bare line numbers.
- [task-skill_label-only-soft-pointers.md](archive/task-skill_label-only-soft-pointers.md)
  banned line-number position claims and added the warn-level `lint.py`
  detector.
- [task-skill_soft-pointer-lint-hardening.md](archive/task-skill_soft-pointer-lint-hardening.md)
  broadened that detector and added the recall-bias triage contract.

The motivating instance: while hardening references inside
[task-family_create-reconcile-open-questions.md](task-family_create-reconcile-open-questions.md),
several "step 6 / step 7 / step 8" anchors pointed into `task_create`'s numbered
`<workflow>` list. They resolved correctly at the time, yet were fragile for the
exact reason this rule targets — that task's whole job is to add a step to that
very list, so any ordinal fixed against it is one edit away from rotting. The
general lesson the episode argues for is that an ordinal list-position reference
is the same kind of position claim a line number is; the episode itself rides
along only as the illustration.

The rule already states the remedy for line numbers (anchor by greppable label,
give extent as size never position); this task widens the *kind of position
claim* the remedy governs. It changes the authoring discipline and the review
lens, not the automated detector — see `## Approach` non-goals for why
lint-level enforcement is a separate follow-up.

## Approach

Rewrite the two rule sites in the base `task` skill's `SKILL.md` in place,
keeping one canonical statement of the rule:

1. **`<markdown_policy>` soft-pointer rule.** Where it bans line-number position
   claims, name a second species alongside them: an ordinal list-position
   reference — locating a list item by its number or ordinal position ("step 6",
   "item 3", "the second bullet") instead of by the item's own label. State the
   remedy already used for line numbers — anchor to the item's verbatim greppable
   label (heading text, bold lead-in, symbol or rule name, or short quoted
   phrase). Call out the heightened case explicitly: when the referencing task
   edits the target list by inserting, removing, or reordering items, an ordinal
   is guaranteed to rot, so a label is mandatory there.
2. **`<readiness_checklist>` Ambiguity / under-specification item.** Extend the
   existing position-claim clause so an ordinal list-position anchor is flagged
   against the `<markdown_policy>` soft-pointer rule, the same way a line-number
   claim already is. The item cites the rule rather than restating the remedy.

Frame both as rewrites that widen the existing wording, so the line-number
coverage and the ordinal coverage read as one rule with two species rather than
two parallel rules.

Non-goals:

- Automated `lint.py` detection of ordinal references and a `task_fix`
  auto-fix stay out of scope and belong to a follow-up sibling. The predecessor
  evolution set the rule in prose first and added recall-biased detection only
  afterward, and reliable ordinal detection — separating an anchor like "step 6"
  from legitimate ordinal prose such as "the first release" — is a distinct,
  false-positive-prone effort. This task makes the rule and the review lens
  cover ordinals; lint enforcement follows separately, consistent with the
  repo's keep-skill-change-and-harness-expansion-separate rule.
- The base `<lint>` soft-pointer description and `lint.py` `check_no_position_claims`
  stay unchanged, so the detector prose keeps matching the detector code.
- The wiki family's pointer conventions are untouched, and no new severity tier
  or detector pattern is added.

This edits shipped skill content under `plugins/ai_dev/`, so the standing
plugin-version-bump and validation gates apply at commit time.

## Acceptance

- The base `task` skill's `<markdown_policy>` soft-pointer rule names an ordinal
  list-position reference (for example "step 6", "item 3", "the second bullet")
  as a position claim beside the line-number forms, and states the
  label-anchor remedy; grepping `task/SKILL.md` finds the new wording, and one
  canonical position-claim statement remains rather than a second parallel copy.
- That rule calls out the heightened-fragility case in so many words: a
  reference whose own task inserts, removes, or reorders items in the target
  list anchors by label, not by ordinal.
- The base `task` skill's `<readiness_checklist>` **Ambiguity /
  under-specification** item flags an ordinal list-position anchor against the
  `<markdown_policy>` soft-pointer rule, extending the existing line-number
  position-claim clause rather than duplicating it; reading it shows it citing
  the rule rather than restating the remedy.
- The line-number soft-pointer coverage is preserved: the existing `:N` /
  `line N` / `~N` / `around lines N–M` forms and the size-extent carve-out still
  read as before, with the ordinal coverage added beside them.
- `lint.py` and `task_fix/SKILL.md` carry no edit from this task, and the base
  `<lint>` soft-pointer description is unchanged; inspection confirms the change
  is localized to `task/SKILL.md`'s `<markdown_policy>` and
  `<readiness_checklist>`.
