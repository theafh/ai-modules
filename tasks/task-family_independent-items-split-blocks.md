---
description: "Make task_check block ready on a task that bundles independent items, so every vendor judges such a bundle alike and scope_split_stuck reliably reaches task_auto_check's split boundary."
scope: plugins/ai_dev/skills/task
created: 2026-11-15T15:07:43Z
updated: 2026-11-17T10:06:07Z
status: open
reported-by: Andreas Hoffmann
---

# Block ready on a bundle of independent items

## Goal

The base `task` skill's **Blocking bar** names a **Scope sizing** or **Focus** finding about independent items bundled in one task among the classes that block `ready` by definition. `task_check` then never stamps `ready` on a bundle the sizing rule says to split, it judges such a bundle the same way on every vendor, and the `scope_split_stuck` eval of `tests/task_auto_check` reaches `task_auto_check`'s `<structural_split_boundary>` on every run.

## Context

- **What happened.** In Claude's 2026-11-15 run of `scope_split_stuck`, the dry run's finding dr5 said the auth work and the billing work "share no rationale, no edit surface, and no acceptance story". The gate still recorded `scope sizing: clean` and `focus: clean`. Its reasons were that bundling the two causes no wrong result and that the frozen Goal's "in one pass" makes a split the user's call. The loop repaired three other blocking issues, stamped `ready`, and raised the split only as a question in its report. Cursor's run of the same fixture recorded both lenses as issues and passed.
- **Two base passages pull apart.** The sizing paragraph of the base skill's `<body>` ends "Split independent items, expandable tangents, and tasks that grow past **300 lines** into siblings before continuing". The `<readiness_checklist>` **Blocking bar** makes every finding outside its by-definition classes a note unless the literal implementer would produce a nameable wrong result. Neither passage names the other, so a gate can follow either one.
- **The fixture predates the bar.** `scope_split_stuck` has been tracked since commit 58f3bd1 (2026-08-30), and the **Blocking bar** arrived in commit af74b47 (2026-10-27). The fixture's task bundles two small edits, so a gate that follows the bar finds no wrong result to name.
- **What the split boundary needs.** `<structural_split_boundary>` in `task_auto_check`'s SKILL.md acts only on a scope-sizing, focus, or complexity defect the gate raises, so a bundle cleared as a note never reaches it.
- **The pinned sentence.** Scenario s15 of `tests/task_auto_check/script_tests/run.sh` pins the bar's by-definition sentence word for word, in the assertion labelled "charter, structure, invalidated premise, and frozen counts block by definition".

**Decision (user, 2026-11-15).** An independent-items finding blocks `ready`, because the sizing rule already says to split such items before continuing, and a `ready` stamp would hand `task_implement` a bundle that rule forbids. The rejected alternative kept the finding a note and redesigned the fixture so its bundle gives the literal implementer a nameable wrong result or passes the 300-line ceiling. The change moves which findings block `ready` in `task_check`, `task_auto_check`, and `task_fix` alike.

## Approach

1. In the base `task` SKILL.md, rewrite the **Blocking bar**'s by-definition sentence in place so it adds a **Scope sizing** or **Focus** finding that names independent items under the sizing rule. A too-small finding and a size finding below the 300-line ceiling stay under the ordinary bar.
2. In scenario s15, update the pinned sentence and its assertion label to the new text.
3. In the `scope_split_stuck` fixture's `setup.sh`, rewrite the comment above the staged files so it names the rule its bundle meets.

## Acceptance

1. The **Blocking bar**'s by-definition sentence names a **Scope sizing** or **Focus** finding about independent items, and it agrees with the sizing paragraph's rule to split such items.
2. `bash tests/task_auto_check/run_all.sh` and `make test` pass, including the updated pin.
3. `scope_split_stuck` runs on the default vendor and passes, its first gate return records the scope-sizing or focus item as an issue, and the verdict is recorded in `tests/task_auto_check/evals/README.md`.
