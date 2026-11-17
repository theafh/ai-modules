---
description: "Make task_implement write the labeled Open decision into the task body, not only into its report, when it holds before crossing a declared Out of scope boundary."
scope: plugins/ai_dev/skills/task_implement
created: 2026-11-15T15:11:27Z
updated: 2026-11-17T10:06:07Z
status: open
reported-by: Andreas Hoffmann
---

# Write the boundary-crossing decision into the task body before holding

## Goal

When `task_implement` holds because delivering the Goal or an `## Acceptance` item would cross a declared `**Out of scope:**` boundary, it writes the labeled "Open decision:" into the task body and also surfaces it in its report, on every vendor. The `implement_boundary_cross` eval of `tests/task` then passes on Cursor as it does on Claude.

## Context

- **What happened.** Cursor's runs of `implement_boundary_cross` on 2026-11-15 quoted the conflicting passages, gave an "Open decision" section with options and a suggested path in the response, and held. Both left the task file unchanged, so the second run fails the grader check "the task body carries exactly one Open decision: lead-in", which the first run predates. Claude's run wrote the label into the body and passes.
- **The base rule asks for both halves.** The base `task` skill's **Decide or label** rule says a qualifying decision "is handled twice over, and both halves are mandatory": the labeled "Open decision:" goes into the body with its options, a suggested default, and the why-open clause, and the decision is surfaced to the user.
- **task_implement names only the disposition.** Its workflow step that opens "**Implement in order.**" says to "quote the conflicting passages, apply the base skill's **Decide or label** reconcile-or-surface disposition, and hold". It never says to write the label, so a model that acts on this sentence alone surfaces and holds without writing.
- **The eval contract.** `implement_boundary_cross` in `tests/task/evals/evals.json` expects the label and the `updated` bump as the only file change, with the task staying `ready` and no code edit.

## Approach

1. In `plugins/ai_dev/skills/task_implement/SKILL.md`, rewrite that sentence of the **Implement in order.** step in place so the hold covers both halves: write the labeled "Open decision:" into the task body with its options, a suggested default, and the why-open clause, bump `updated` without changing `status`, and surface the same decision in the report.
2. In `tests/task/script_tests/contract_run.sh`, beside the existing **Decide or label** pins for `task_implement`, add an `assert_contains` pin for the write half of the rewritten sentence and an `assert_not_contains` pin for the old sentence, the pattern those pins already follow.

## Acceptance

1. The **Implement in order.** step names both the written label and the surfaced decision for a boundary-crossing hold.
2. `bash tests/task/run_all.sh` passes, including the two new pins.
3. `implement_boundary_cross` runs on the default vendor and passes, and the verdict is recorded in `tests/task/evals/README.md`.
