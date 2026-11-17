---
description: "Make task_auto_check's report print the repeated-link disposition line beside the edit group that regrouped the finding, so the line survives when an ordinary repair round lands the regroup."
scope: plugins/ai_dev/skills/task_auto_check
created: 2026-11-15T18:18:40Z
updated: 2026-11-17T10:06:07Z
status: open
reported-by: Andreas Hoffmann
---

# Print the repeated-link disposition line on the ordinary repair path

## Goal

When an ordinary repair round of `task_auto_check` regroups a `repeated-link` finding, the run's report prints that finding's disposition line in the base `<lint>` **Repeated-link disposition line** shape, as it already does when the `<gate>` repeated-link repair round regroups it on a `ready` verdict. The `regroup_immediate_ready` eval of `tests/task_auto_check` then passes its two disposition checks on either path.

## Context

- **What happened.** Two Claude runs of `regroup_immediate_ready` on 2026-11-15 went through citation refutation, so the regroup landed in an ordinary repair round. Both regrouped correctly: the sibling account moved into `## Approach` and the repeated-link warning cleared. Both reports described the change in prose and printed no `repeated-link:` line, so the checks "the ready path reports a regrouped or surfaced disposition" and "the reported disposition matches the file state it claims" failed. Claude's earlier run that day, where the regroup landed through the `<gate>` repair round, printed the line and passed.
- **The contract already asks for it.** The `<output_contract>` of `task_auto_check`'s SKILL.md says the disposition line "is mandatory on every dispositioning path, whether the regroup landed through `<plan_repairs>` / `<verify_repairs>` / `<apply_repairs>` in an ordinary round or through the `<gate>` repeated-link repair round". That rule sits in its own bullet near the end of the list, apart from the bullet that opens "For each applied edit group", which is where a report describes the regroup on the ordinary path.

## Approach

1. In the `<output_contract>` of `plugins/ai_dev/skills/task_auto_check/SKILL.md`, rewrite the bullet that opens "For each applied edit group" in place, so an edit group that answers a lint-originated `repeated-link` finding closes with that finding's disposition line, printed verbatim in the base shape on a line of its own even when the report also describes the change in prose.
2. In scenario s15 of `tests/task_auto_check/script_tests/run.sh`, add an `assert_contains` pin for the rewritten sentence.

## Acceptance

1. The edit-group bullet of the `<output_contract>` requires the disposition line for an edit group that answers a `repeated-link` finding, and the existing every-path bullet still stands.
2. `bash tests/task_auto_check/run_all.sh` passes, including the new pin.
3. `regroup_immediate_ready` runs on the default vendor and passes, and its verdict is recorded in `tests/task_auto_check/evals/README.md`. The miss showed on Claude, so a Claude run that confirms the fix is the operator's call.
