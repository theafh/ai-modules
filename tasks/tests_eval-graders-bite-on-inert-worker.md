---
description: "Make every behavioral eval grader fail an inert worker: assert at least one positive artifact so absence-only checks stop scoring a no-op run as a pass."
scope: "local test harnesses"
created: 2026-10-30T23:33:51
updated: 2026-10-30T23:33:51
status: open
reported-by: Andreas Hoffmann
---

# Make every behavioral eval grader fail an inert worker

## Goal

A behavioral eval's grader fails when the worker did nothing, so a green eval
means the behaviour was observed rather than merely not contradicted. Today a
large minority of evals pass on an empty response against an untouched
sandbox: the checks assert only that some forbidden state is absent, and a
worker that never ran leaves exactly that state in place.

The user-visible outcome: an eval whose checks are all absence-shaped cannot
report PASS for a run that produced nothing. The suite stops certifying
silence, and a genuinely broken worker shows up as a red eval instead of a
green one.

## Context

`TESTING.md` `## Test Design Principles` states the rule this task enforces in
the bullet beginning `**State the fail branch.**`: "A check proves the failure
case fails, not only that the hoped-for direction passes. A fixture that cannot
fail measures nothing." The graders satisfy the rule in places — `git_commit`
stages every eval against a staged baseline so a no-op run fails the universal
checks — and miss it in others.

Measured on 2026-10-30 by staging each eval's sandbox and grading it against an
empty response file, i.e. the exact state an inert worker leaves. The count is
evals that graded PASS with the worker contributing nothing:

| Harness | Inert-PASS | Total |
| --- | --- | --- |
| `git_checkout` | 4 | 7 |
| `git_review` | 2 | 48 |
| `git_refresh` | 1 | 4 |
| `git_auto_review` | 1 | 35 |
| `task` | 8 | 46 |
| `task_auto_check` | 11 | 33 |
| `git_commit` | 0 | 9 |
| `agent_spinner`, `guardrail_audit`, `skill_doctor`, `task_create`, `task_fix` | 0 | 72 |

Two shapes produce the passes.

**Absence-only state checks.** `git_checkout` evals 3, 5, 6, and 7 grade
"still on main", "no local branch was created", "worktree left as found",
"no stash entry" — all of which hold on an untouched sandbox. Their positive
counterpart, that the helper actually ran and reported the miss, lives in
`note_response` lines that print but never decide the exit code.
`git_refresh` eval 4 and `git_auto_review`'s `declines_on_detached_head` have
the same shape. `git_review` eval 36 grades two stub-`gh` "no call" checks and
nothing else, so a worker that never touched the stub passes; eval 7 grades
"no stash", "one worktree", and "no new commit" over a sandbox that already
satisfies all three.

**Response-only evals with no enforced check.** The eight `task` evals
`explain`, `select`, `query`, `audit_gaps`, `implement_dep_gate`,
`select_inbound_dep`, `select_dep_regression`, and `implement_boundary_cross`
carry only `agent-attest` lines, which print for the operator and never count.
Their observable half — a read-only run leaves the sandbox git tree unchanged —
is satisfied by doing nothing, so an empty response scores full marks. The same
holds for the eleven `task_auto_check` evals listed in the run:
`mechanical_lint_oversized_surface`, `already_ready`,
`intent_drift_human_route`, `drift_gate_narrowing_clean`,
`drift_gate_refinement_clean`, `drift_gate_broadening_drift`,
`drift_gate_committed_broadening_clean`, `scope_split_stuck`,
`gate_failure_user_stop`, `drift_failure_user_stop`, and
`interaction_scan_no_false_alarm`.

The overall unenforced surface is large: across the twelve graders there are
1019 declared `expectations` and roughly 300 checks that print as
`agent-attest` / `note_response` without deciding the exit code. Most are
legitimately operator-confirmed prose judgements, which this task leaves
alone. The gap is the narrower one above, where a whole eval has no enforced
check or only absence-shaped ones.

The harness-specific pieces an implementer needs are already in the tree: the
`note_response` helper in `tests/git_checkout/evals/grade.sh` and
`tests/git_refresh/evals/grade.sh`, the `attest` helper in
`tests/git_review/evals/grade.sh`, the `script_calls.log` shim that
`tests/git_review/evals/stage.sh` truncates per run, and the `report` helper in
`tests/git_auto_review/evals/grade.sh`.

## Approach

Add one enforced positive check per eval that currently passes on an inert
worker, preferring a filesystem or invocation fact over a response claim, as
`TESTING.md`'s `**Prefer a filesystem fact over a claim.**` bullet directs.

1. **Give each harness an invocation record where it has none.** `git_review`
   already writes `script_calls.log` from a shim; extend the same treatment to
   the `git_checkout` and `git_refresh` fixtures by having `stage.sh` place a
   logging wrapper for the bundled script on the worker's `PATH`, then assert
   in each absence-only eval that the wrapper recorded a call. Where a wrapper
   is impractical, promote the load-bearing `note_response` line into a real
   check and give it a fail branch.
2. **Add the positive half to each absence-only state check.** An eval that
   asserts "no branch was created" also asserts the evidence that the run
   reached the decision: the helper log line, the reported cause token, or the
   response passage naming the blocking path. Keep the absence check beside it.
3. **Give each response-only eval at least one enforced check.** For the
   read-only `task` evals, grade the substance the eval exists for — the
   response names the specific task file, scope, or verdict the fixture plants
   — rather than the sandbox's unchanged git tree, which an inert worker also
   leaves unchanged. Reuse the wrap-collapsing and subject-anchoring helpers
   those graders already carry.
4. **Prove the fail branch in the harness's own script tests.** Each harness's
   `script_tests/` gains one scenario that stages an eval, grades it against an
   empty response, and asserts a non-zero exit. That scenario is the regression
   pin: a later edit that removes the positive check turns it red.

Keep the added checks to one or two per eval. The aim is a floor that an inert
worker cannot clear, not full enforcement of every prose expectation.

**Out of scope:** Enforcing the operator-confirmed `agent-attest` prose
judgements generally, which stays the documented division of labour between
`grade.sh` and the operator. Adding new evals or new fixtures. Converting the
`task_create` / `task_fix` graders, which already fail an inert worker.

**Co-edits.** No other live task edits these graders, so this one runs
independently. Two sibling tasks rewrite the runners around them and must be
rebased, not re-merged: [the git-review parallel-evals
task](tests_git-review-parallel-evals.md) rewrites
`tests/git_review/evals/run.py`, and [the task-hub parallel-evals
task](tests_task-hub-parallel-evals.md) rewrites `tests/task/evals/run.py` and
its `evals/test_run.py`. Neither changes a `grade.sh` check, so the added
positive checks survive either landing order. This task's own
`script_tests/` scenarios in `git_checkout`, `git_review`, `git_refresh`,
`git_auto_review`, `task`, and `task_auto_check` are separate from the
stage-guard scenario [the stage-guard task](tests_eval-stage-guard.md) adds to
`agent_spinner`, `git_auto_review`, and `guardrail_audit`; the two overlap only
on `git_auto_review/script_tests/run.sh`, so whichever lands second appends.

## Acceptance

- Running the inert-worker probe over every eval in `git_checkout`,
  `git_review`, `git_refresh`, `git_auto_review`, `task`, and
  `task_auto_check` — stage each eval, write an empty response file, grade —
  returns a non-zero exit for every eval in those harnesses. The probe's
  before-count is the table in Context; after the change the inert-PASS column
  is zero for every listed harness.
- Each harness named above gains a `script_tests/` scenario that performs that
  probe over its own eval set and fails when any eval grades PASS, and the
  scenario is red before the grader edits and green after them.
- The evals named in Context — `git_checkout` 3, 5, 6, 7, `git_review` 7 and
  36, `git_refresh` 4, `git_auto_review` `declines_on_detached_head`, the eight
  `task` response-only evals, and the eleven `task_auto_check` evals — each
  carry at least one check whose predicate is false on an untouched sandbox
  and true only after the behaviour under test occurs.
- The probe is recorded for commit as a script or a note under
  `tests/lib/`, naming the command that runs it and the harness set it covers,
  so a later change can re-measure the same property rather than re-derive it.
- `make lint` passes, and `tests/AGENTS.md` and `tests/CLAUDE.md` name the new
  `script_tests/` scenario in their parallel-workers and coverage prose where
  those files already enumerate harness scenarios.
