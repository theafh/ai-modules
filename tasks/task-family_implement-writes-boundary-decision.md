---
description: "Make task_implement write the labeled Open decision into the task body, not only into its report, when it holds before crossing a declared Out of scope boundary."
scope: plugins/ai_dev/skills/task_implement
created: 2026-11-15T15:11:27Z
updated: 2026-11-19T17:56:05Z
status: ready
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

1. In `plugins/ai_dev/skills/task_implement/SKILL.md`, state the boundary-crossing dual obligation once, in the **Implement in order.** step's boundary sentence ("When delivering the Goal or an `## Acceptance` item would require crossing a declared Out of scope boundary …"), rewritten in place so the hold cites both halves of the base skill's **Decide or label** disposition — the labeled "Open decision:" written into the task body and the same decision surfaced in the report — rather than restating that rule's mechanics, which that skill's `<authority>` keeps in the base skill; the step bumps `updated` without changing `status`. The step's later open-decision sentence keeps governing every other open decision and gains one pointer clause that sends a boundary-crossing hold to the boundary sentence for both halves, so the dual obligation is stated once and its existing wording stays intact. While rewriting, keep the two substrings other artifacts anchor on byte-identical: "surface the decision to the user with its options and at least one suggested path and hold", quoted by the base `task` skill's **Decide or label** rule (`plugins/ai_dev/skills/task/SKILL.md`) and by `tasks/tests_task-family-lifecycle-evals.md`, and "apply the base skill's **Decide or label** reconciliation rule against its evidence base", pinned against `task_implement` by `tests/task/script_tests/contract_run.sh` beside its existing **Decide or label** pins.
2. In `tests/task/script_tests/contract_run.sh`, beside the existing **Decide or label** pins for `task_implement`, add an `assert_contains` pin for the write half of the rewritten sentence and an `assert_not_contains` pin whose needle is the exact fragment the rewrite removes: `quote the conflicting passages, apply the base skill's **Decide or label** reconcile-or-surface disposition, and hold`. Both pins use the script's fixed-string `assert_contains` / `assert_not_contains` helpers, single-quoted, the pattern those pins already follow.

## Acceptance

1. The **Implement in order.** step names both the written label and the surfaced decision for a boundary-crossing hold.
2. `bash tests/task/run_all.sh` passes, and `tests/task/script_tests/contract_run.sh` carries both new pins against `plugins/ai_dev/skills/task_implement/SKILL.md`: the `assert_contains` pin for the write-half wording matches that file, the `assert_not_contains` needle `quote the conflicting passages, apply the base skill's **Decide or label** reconcile-or-surface disposition, and hold` matches no line of it, and both anchored substrings — "surface the decision to the user with its options and at least one suggested path and hold" and "apply the base skill's **Decide or label** reconciliation rule against its evidence base" — still appear verbatim in the rewritten **Implement in order.** step.
3. `implement_boundary_cross` runs once on the default vendor, and `tests/task/workspace/run-<ts>/implement_boundary_cross/grading.txt` shows its `one_open_decision_label` check passing against the baseline recorded in `run-20261115-073331`, where the task body stayed unchanged; the verdict lands in `tests/task/evals/README.md` by rewriting both passages there that state the opposite in place, so one canonical current-state statement remains: the `## Recorded results` headline "every eval passes on both vendors except two … `implement_boundary_cross` fails on Cursor" reads "except one" with `audit_clean` as the only failure, and the bullet "`implement_boundary_cross` fails in `run-20261115-073331`" carries the passing run's timestamp and verdict in place. A failing run takes one repair of the skill prose and one re-run; a second failure records that `grading.txt` and surfaces the failing run as the outcome instead of stamping the task done.

4. `implement_boundary_cross` runs once under `--vendor claude` on the edited tree and passes, with the verdict recorded in `tests/task/evals/README.md` `## Recorded results` in place of the `run-20261115-101941` re-grade row, and its `grading.txt` kept under `tests/task/workspace/run-<ts>/implement_boundary_cross/`. On a failure, the prose is repaired and the run repeated once; a second failure surfaces that `grading.txt` in place of a done stamp.
