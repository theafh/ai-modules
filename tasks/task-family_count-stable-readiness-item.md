---
description: "Give the count-stable rule its own readiness-checklist item so every readiness surface tests it explicitly, and prove the adjacent-enumeration form the current eval misses."
scope: plugins/ai_dev/skills/task
created: 2026-11-17T15:56:41Z
updated: 2026-11-17T15:56:41Z
status: open
reported-by: Andreas Hoffmann
---

# Give the count-stable rule its own readiness-checklist item

## Goal

Every readiness surface that walks the base `task` skill's `<readiness_checklist>` tests a body's references to mutable sets as its own named item, so a frozen count or an enumeration snapshot is flagged with a citation instead of hiding inside a broader lens. The adjacent-enumeration form — a body that names a set's members and freezes their number beside an open set, as in "the three checks — a, b, c" — is caught too, and the eval family proves it. The rule keeps its single canonical statement in `<markdown_policy>`; this task changes how the checklist enforces it, not where the rule lives.

## Context

The base `task` skill holds the count-stable rule in `<markdown_policy>`, led by "Reference a mutable set by its defining property: the count-stable rule", and its `<readiness_checklist>` **Blocking bar** classes a frozen mutable-set count as blocking by definition. Enforcement, though, is a sub-clause of the checklist's **Ambiguity / under-specification** bullet: the bullet names the rule but gives the assessor no line of its own to clear. `auto_gate_task` walks "every named content-lens item" and records one cited line per item, so a gate can clear `Ambiguity / under-specification` on an unrelated reading and never test the count-stable condition.

That gap surfaced in practice. The task `ai-dev_agent-spinner-ledger-terminal-states` was refreshed and stamped `ready` by `task_auto_check`, and its body froze a count over a mutable set ("the three `tests/agent_spinner/evals/grade.sh` checks that require the literal word `unknown`") beside a full enumeration of that set. The gate did not flag it; `task_implement` and `task_audit` carried the task to `audited`, and the stale reference was found only afterwards in review. The eval `check_count_stable` did not protect the case because its fixture stages only the bare form ("all 3 plugin manifests under `plugins/*/plugin.json`"), whose count has no enumeration beside it.

The intended owner is already the checklist: the `check_count_stable` fixture's own comment says the **Ambiguity / under-specification** lens "must flag it against the count-stable rule". The fix is to give that condition a named item the gate must clear, not to make other skills name `<markdown_policy>`.

## Approach

1. Add a named content-lens item to the base `task` skill's `<readiness_checklist>` for count-stable references. State the operational test in the item: a set whose membership can change between writing and implementation is referred to by its selector, never by a frozen count or an enumeration snapshot, and the adjacent-enumeration form is a violation even when the count is accurate today. Keep the full rule, its rationale, and its legal subject-matter exceptions in the `<markdown_policy>` bullet, and have the item cite that bullet rather than restating the rationale. Remove the count-stable sub-clause from the **Ambiguity / under-specification** bullet so one statement of the rule remains and the checklist carries the test.
2. Keep `auto_gate_task` unchanged: it already walks every named content-lens item and requires a citation, so a new named item appears in its `## Checklist` automatically. Confirm the item's name reads the same in the checklist and in the gate's template line, which names each item as the base checklist names it.
3. Extend the `check_count_stable` eval family with the adjacent-enumeration form. Add a fixture body that names a mutable set's current members and freezes their number beside an open set, and stage it so a fourth member could join. The gate must raise a numbered issue against the count-stable rule, propose the selector rewrite as the minimum fix, and leave the measurement-protocol quantity unflagged exactly as the existing fixture requires. Register the new eval id in `tests/task/evals/evals.json`, `stage.sh`, `grade.sh`, and the `tests/task/evals/README.md` table.
4. Add a static pin in `tests/task_auto_check/script_tests/run.sh` beside the existing count-stable pin, asserting that the base `<readiness_checklist>` carries the named item and that the **Ambiguity / under-specification** bullet no longer carries the only reference. The pin fails on a checklist that drops the item, so the rule's enforcement does not depend on a behavioural run.
5. Leave every front end untouched: `task_check`, `task_auto_check`, `auto_gate_task`, and `auto_dryrun_task` inherit the checklist item through the base skill. Do not add `<markdown_policy>` to any front end's authority list, and do not add a second copy of the rule to a sibling skill.

**Out of scope:** a repo-wide pointer in `AGENTS.md` for non-task prose; a mechanical linter for frozen counts; rewriting archived task bodies that carry the old form; and any change to the rule's legal subject-matter exceptions.

## Acceptance

- The base `task` skill's `<readiness_checklist>` carries a named content-lens item for count-stable references, and the **Ambiguity / under-specification** bullet no longer holds the only reference. A grep for the item's name finds it inside `<readiness_checklist>`.
- The item states the adjacent-enumeration form as a violation and points at the `<markdown_policy>` count-stable rule for the full statement, so the rule text is not duplicated.
- The new eval fixture is registered and its graded checks pass: a numbered issue flags the frozen count beside an enumeration, names the selector rewrite as the minimum fix, and leaves the measurement-protocol quantity unflagged; the report records both verdicts.
- The static pin in `tests/task_auto_check/script_tests/run.sh` passes on the shipped skill and fails on a scratch copy whose checklist drops the item.
- `bash tests/task/run_all.sh` and `bash tests/task_auto_check/script_tests/run.sh` pass, and `make lint` is clean.
- No front-end skill or agent file gains a `<markdown_policy>` reference; `git diff` over the change shows the base `task` skill and the eval harness only.
