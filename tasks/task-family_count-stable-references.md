---
description: Extend the durable-reference discipline from position claims to volatile counts: task bodies reference mutable sets by defining property, flagged at readiness and surfaced by task_fix.
scope: plugins/ai_dev
created: 2026-08-05T19:26:42
updated: 2026-08-05T19:26:42
status: open
reported-by: Andreas Hoffmann
---

# Count-stable references: extend the durable-reference discipline from positions to volatile counts

## Goal

A task body refers to any set whose membership can change while the backlog ships — live tasks in a scope, checks in a linter, skills in a plugin, scenarios in a suite — by the property that selects the set, so the reference stays true when membership changes between writing and implementation. A task names such a set by selector (a filename glob, a greppable label, a phrase like "every live `wiki_*` task") and names a load-bearing quantity by its derivation at implementation time, in place of point-in-time cardinality ("all 14 live `wiki_*` tasks") or a frozen enumeration snapshot. The count-stable rule is authored once in the base `task` skill beside the soft-pointer rule, the readiness checklist flags violations at check time, and `task_fix` surfaces them during tree repair. The user-visible outcome is a backlog whose tasks need no refresh merely because a sibling shipped and changed a number the body froze.

## Context

- The base `task` skill's `<markdown_policy>` rule led by "Locate referenced content by a verbatim label — the soft-pointer rule" already applies this principle to positions: line-number and ordinal references locate by a position that "rots silently as the target evolves". Quantities sit outside it — no rule governs referring to a mutable set by its current count.
- Counts are today deliberately left alone by the machinery that exists: the base `<lint>` soft-pointer triage instructs readers to "leave a false positive such as a size, version, count, or quoted claim-shape untouched", and `task_fix`'s `<remediate>` step repeats that instruction for its auto-fix pass. The carve-out protects the position-claim check's precision; it leaves count-shaped references ungoverned rather than endorsed. [The lint-hardening task](archive/task-family_soft-pointer-lint-hardening.md) defined that triage contract, and its recall-versus-precision reasoning — "The linter cannot enumerate every non-position number" — is the rubric that keeps mechanical detection out of scope here.
- The readiness checklist's **Premise check** meets a stale count only after the fact, classifying it a drifted detail during a later check. Authoring time has no rule against the shape, so a fresh "update all 14 live `wiki_*` tasks" passes today's check while accurate and rots when the first sibling ships.
- [The soft-pointer discipline task](archive/task-family_label-only-soft-pointers.md) shipped the position-claim rule this task extends; the new rule sits beside it so `<markdown_policy>` keeps one reference discipline with two classes — positions locate by label, quantities select by property.
- Edit surfaces: [the base task skill](../plugins/ai_dev/skills/task/SKILL.md) (`<markdown_policy>` and the `<readiness_checklist>` ambiguity clause) and [task_fix](../plugins/ai_dev/skills/task_fix/SKILL.md) (`<surface_for_review>`). The charter invariant "Skill-family rules live in the family base skill" governs the shape: front ends inherit the rule through the base skill rather than carrying copies.

## Approach

1. **Author the count-stable rule once, beside the soft-pointer rule.** Add to the base skill's `<markdown_policy>` a rule with its own bold lead-in (for example "**Reference a mutable set by its defining property — the count-stable rule.**"): refer to a set whose membership can change by the selector that picks it out — a filename glob, a greppable label, a phrase like "every live `wiki_*` task" or "each check registered in the lint runner" — and name a load-bearing quantity by its derivation at implementation time (the command or source that yields the number) rather than freezing the number in prose. State the settling test: the reference stays true when set membership changes between writing and implementation. Keep the legal cases explicit — a quantity that is subject matter rather than a set reference stays: a measurement protocol's run count and fixed denominator under the Acceptance contract's "Measured, with a fail branch" clause, a size extent the soft-pointer rule already endorses ("Give extent, when useful, as size"), and a number that is itself the artifact under edit.
2. **Flag violations at readiness.** Extend the `<readiness_checklist>` **Ambiguity / under-specification** clause — the passage today ending "is flagged against the `<markdown_policy>` soft-pointer rule" — so a mutable-set reference carried by a frozen count or enumeration snapshot is flagged against the count-stable rule in the same clause. `task_check` and `task_auto_check` inherit the flag through the checklist; no sibling carries a copy.
3. **Surface in task_fix, propose rather than auto-fix.** Add a count-stable entry to `task_fix`'s `<surface_for_review>` pointing at the base rule, with the selector rewrite as the proposed fix: rewriting "all 14 live `wiki_*` tasks" into "every live `wiki_*` task" widens a frozen scope when membership grew since writing, so the repair is a judgement the user confirms. The mechanical `<remediate>` path stays unchanged for counts.
4. **Hold the linter boundary.** `lint.py` gains no count detector, and the existing triage sentence stays as it is: it governs how a reader treats the position-claim check's hits, while the new rule governs how an author writes quantity references — two different acts, in agreement without cross-edits.

**Out of scope:**

- A `lint.py` detector for count shapes, since prose quantities are not mechanically separable from legal subject-matter counts; detection lives in the readiness lens and the task_fix surfacing this task adds.
- A wiki-family equivalent for wiki page bodies; this task governs task bodies, and the wiki family already handles its known count instance through its own linted index header.
- A sweep rewriting counts across the existing backlog; existing tasks converge opportunistically as they pass through update, check, and repair.

## Acceptance

- The base skill's `<markdown_policy>` carries the count-stable rule beside the soft-pointer rule: grepping the SKILL.md for the rule's bold lead-in finds one statement naming the defining-property form, the derivation form for load-bearing quantities, the stays-true settling test, and the subject-matter legal cases (false today — no such rule exists).
- The `<readiness_checklist>` ambiguity clause flags frozen-count and enumeration-snapshot references against the count-stable rule, extended in place so one clause carries both reference classes (today it ends at position claims).
- `task_fix`'s `<surface_for_review>` names count-stable violations as a surfaced judgement with the selector rewrite as the proposed fix, pointing at the base rule, and its `<remediate>` treatment of soft-pointer false positives stays byte-identical.
- The base `<lint>` soft-pointer triage sentence — "leave a false positive such as a size, version, count, or quoted claim-shape untouched" — stays byte-identical, the boundary between lint-hit treatment and authoring discipline holding per the Approach.
- A behavior eval scenario under the task-family harness (`tests/task/evals/` per the repo's standing harness pattern; the harness tree is local-only) stages a fixture task carrying a frozen mutable-set count and a legal measurement-protocol count: the check run flags the former against the count-stable rule, leaves the latter unflagged, and the scenario records both verdicts.
