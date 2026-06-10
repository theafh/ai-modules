---
description: Sweep every task_* family SKILL.md for big ai_instruction_writing violations — negative-only and inverted instructions — and rewrite them to a positive, action-oriented carrier.
scope: "task_* family skills"
created: 2026-06-01T22:50:36
updated: 2026-06-09T15:12:08
status: open
---

# Sweep the task_* family for big ai_instruction_writing violations

## Goal

Audit all seven `task_*` family `SKILL.md` files against the
`ai_instruction_writing` rubric and fix the **big** violations — instructions
whose primary carrier is a negative or an inverted rule, not low-value style
nits. After the sweep, every load-bearing instruction in the family leads with a
positive, action-oriented statement, with negatives kept only where they name a
non-enumerable long tail as a catch-all. The family is the repo's own showcase
of its authoring conventions, so it should hold to the rubric it ships.

## Context

The `ai_instruction_writing` skill at
`plugins/ai_dev/skills/ai_instruction_writing/SKILL.md` is the rubric. Its
`<core_rule>` and `<self_check>` are the test to apply: delete the negative or
contrastive portion of a rule, then —

- positive carrier is empty or vague → the rule is **inverted**; rewrite the
  positive first (a big violation).
- positive carrier is complete → the negative is **redundant**; drop it.
- negative names a broader class than any positive could enumerate → **keep**
  it as a legitimate catch-all.

The files in scope (each its own SKILL.md under `plugins/ai_dev/skills/`):

- `task` — the hub skill; largest surface, most prose.
- `task_create`, `task_check`, `task_implement`, `task_audit`, `task_finish`,
  `task_fix` — the six focused front ends.

These are published artefacts that drive agent behaviour, so a negative-only or
inverted instruction degrades how the skill is followed, not just how it reads.
The repo's `CLAUDE.md` already mandates positive, action-oriented language and
names `ai_instruction_writing` as the reference, so this sweep enforces a
standing convention rather than introducing a new one.

This task is the **family-wide** pass. It is distinct from the targeted
negation-framing cleanup noted on
[the lossless-conversion task](archive/task-skill_lossless-conversion-check.md), which
fixes only the lines that task itself adds. It is also distinct from
[the positive-task-body rule](task-skill_positive-task-body-rule.md): that task
adds a new authoring rule about the task *files* the skill produces, whereas this
sweep reframes the SKILL.md prose itself and changes no skill behavior.

Sequencing: this sweep runs last. Implement it only when the work of every
other `task-skill_*` task has landed — archived siblings count as landed,
and an open sibling counts once its acceptance items verifiably hold (its
close-out may still be pending). Enumerate the `task-skill_*` siblings in
`tasks/` and `tasks/archive/` at implementation time; any sibling whose work
is not yet built defers the sweep. The walk then covers the family's final
prose rather than text the other tasks replace.

## Approach

Walk each of the seven `SKILL.md` files in turn and apply the `<self_check>`
procedure to every instruction-bearing line:

- Catalogue each **big** violation found: a negative-only instruction with no
  positive carrier (e.g. "Don't do X" with nothing saying what to do instead),
  or an inverted rule whose positive carrier is empty or vague once the negative
  is removed.
- Rewrite each to lead with a positive, action-oriented carrier per the
  rubric's `<transformation_patterns>` and `<good_vs_poor_transformations>`,
  **preserving the technical precision** of the original — keep identifiers,
  conditions, and rationale; do not flatten "Never import unused modules" into a
  lossy "import only what you use".
- Leave legitimate catch-all negatives in place; they pass the self-check.
- Hold to **big** violations — skip cosmetic rephrasings that add no behavioural
  clarity, so the diff stays reviewable and the meaning of each skill is
  unchanged apart from framing.

Keep the pseudo-XML structure, the `name:`/H1 alignment, and every skill's
existing meaning intact — this is a framing fix, not a behavioural redesign. If
a file turns out to need substantial restructuring rather than line-level
rewrites, stop and split that file into its own task rather than expanding this
one.

Non-goal: this task does not change what any skill does, does not touch files
outside the seven `SKILL.md` bodies, and adds no new lint rule for negation.

## Acceptance

- Each of the seven `task_*` `SKILL.md` files has been walked and its big
  `ai_instruction_writing` violations rewritten to a positive, action-oriented
  carrier, with technical precision preserved.
- Remaining negatives are only legitimate catch-alls that pass the rubric's
  `<self_check>` (they name a long tail no positive could enumerate).
- Each skill's behaviour and structure are unchanged apart from instruction
  framing; `name:`, the H1, and the pseudo-XML root tag stay aligned.
- A short report lists, per file, the big violations found and how each was
  rewritten (or "none found").
