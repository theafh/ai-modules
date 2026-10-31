---
description: "Make every behavioral eval grader fail an inert worker: assert at least one positive artifact so absence-only checks stop scoring a no-op run as a pass."
scope: "local test harnesses"
created: 2026-10-30T23:33:51
updated: 2026-10-31T11:09:10
status: checked
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
evals that graded PASS with the worker contributing nothing. That loop is the
derivation for both columns: `Inert-PASS` is the evals it grades PASS, and
`Total` is the id count each harness's `evals/evals.json` yields. The table and
the eval names below record the 2026-10-30 reading; the loop re-finds the
members when it runs:

| Harness | Inert-PASS | Total |
| --- | --- | --- |
| `git_checkout` | 4 | 7 |
| `git_review` | 2 | 48 |
| `git_refresh` | 1 | 4 |
| `git_auto_review` | 1 | 35 |
| `task` | 8 | 46 |
| `task_auto_check` | 11 | 33 |
| `git_commit` | 0 | 9 |
| `agent_spinner`, `guardrail_audit`, `skill_doctor`, `task_create`, `task_fix` | 0 | 43 |

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

The overall unenforced surface is large: the `expectations` arrays across the
twelve graders' `evals/evals.json` files hold 1169 entries at the 2026-10-30
reading, and roughly 300 checks print as `agent-attest` / `note_response`
without deciding the exit code. Most are
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
   already writes `script_calls.log` from a shim, and `git_refresh` already
   carries the same record: `tests/git_refresh/evals/run.py`'s
   `shim_deployed_scripts` writes `script_calls.log`, `stage.sh` truncates it
   per run, and eval 3's `default_run_called` / `prune_gone_after_default_run`
   read it. Extend that treatment only to the `git_checkout` fixture, by adding
   a `shim_deployed_scripts(deploy, target_root)` helper to
   `tests/git_checkout/evals/run.py` — the shape `tests/git_refresh/evals/run.py`
   already implements — that rewrites every deployed `scripts/*.sh` into a shim
   appending `<script> <args>` to `<sandbox root>/script_calls.log` and
   exec'ing the untouched copy, then assert in each absence-only eval that the
   run reached the decision under test: the recorded call paired with the
   argument shape or the reported cause token the behaviour produces, in the
   shape `tests/git_refresh/evals/grade.sh` already carries, where
   `default_run_called` is paired with `prune_gone_after_default_run` so the log
   proves order and arguments rather than mere contact. The edit site is
   `run_one` in `evals/run.py`, between the `micro_deploy.micro_deploy(...)`
   return and the `micro_deploy.run_worker(...)` call: `stage.sh` runs before
   the deployment exists and cannot reach the worker, because
   `tests/lib/micro_deploy.py`'s `run_worker` snapshots the launch `PATH` into
   `WORKER_PATH_VAR` and each Cursor login profile restores exactly that
   value, so only a shim written into the deployed tree is visible. In
   `git_refresh`, add the missing check to the existing log rather than a
   second record. Where a wrapper is impractical, promote the load-bearing
   `note_response` line into a real check with the same floor, asserting the
   reported cause token and giving it a fail branch. Rewrite the head comment
   that states the old rule in the same pass: in
   `tests/git_checkout/evals/grade.sh`, the passage beginning "Expectations
   that speak only about the worker's response or about which helper it
   invoked" and ending "they never decide the exit code" becomes a statement
   that the helper-invocation check in evals 3, 5, 6, and 7 decides the exit
   code and `note_response` carries only what no check can decide. In
   `tests/git_refresh/evals/grade.sh`, the passage naming "the helper
   invocation in evals 1, 2, and 4" and "response lines never decide the
   exit code" becomes a statement that eval 4's `default_run_called` check
   decides the exit code, reading the recorded no-argument `refresh_repo.sh`
   call shape a plain-refresh run logs; `prune_gone_after_default_run`
   remains eval 3's check, paired with eval 3's `default_run_called`, and
   evals 1 and 2's invocation lines stay operator-confirmed. Rewrite the two
   harness READMEs that state the same division in the same pass. In
   `tests/git_checkout/evals/README.md`, the passage beginning "The
   expectations that speak only about the response or about which helper
   ran" and ending "confirm those by reading `response.txt`" becomes a
   statement that the eval 3, 5, 6, and 7 helper-invocation check decides
   the exit code and `response` lines carry only what no check decides. In
   `tests/git_refresh/evals/README.md`, the passage beginning "The
   expectations that speak only about the response, and which helper ran in
   evals 1, 2, and 4" becomes that same post-change division, with eval 4's
   helper-invocation check deciding the exit code and evals 1 and 2's
   invocation lines staying operator-confirmed.
2. **Add the positive half to each absence-only state check.** An eval that
   asserts "no branch was created" also asserts the evidence that the run
   reached the decision: the helper log line, the reported cause token, or the
   response passage naming the blocking path. Keep the absence check beside it.
3. **Give each response-only eval at least one enforced check.** For the
   read-only `task` evals, grade the substance the eval exists for — the
   response names the specific task file, scope, or verdict the fixture plants
   — rather than the sandbox's unchanged git tree, which an inert worker also
   leaves unchanged. Read that response through the `RESPONSE_FILE` environment
   variable the `task_auto_check` runner already sets on its grader
   (`tests/task_auto_check/evals/run.py`): extend `tests/task/evals/run.py` to
   set it from each eval's captured `response.txt` and
   `tests/task/evals/grade.sh` to read it, then reuse the wrap-collapsing and
   subject-anchoring helpers those graders already carry. Rewrite every passage
   that says the grader cannot read the response, in place, to the new
   division: `tests/task/evals/grade.sh`'s head comment ("grade.sh cannot read
   the agent's response text") and its `coherence_wrote_nothing` comment,
   `tests/task/evals/stage.sh`'s and `tests/task/evals/README.md`'s "never sees
   the agent's response text" passages, and the same sentence in the four
   `tests/task/evals/fixtures/fix_coherence*/setup.sh` comments each become a
   statement that the grader reads the response through `RESPONSE_FILE` and
   that `coherence-report.md` remains the graded surface for the coherence
   evals' structured fields. Rewrite in place, in the same pass, every passage
   under `tests/task/` that the new `RESPONSE_FILE` read falsifies, locating
   them by search over that tree rather than by a fixed list: any passage
   stating that the grader cannot read the agent's response, or that a
   verdict-string expectation stays operator-confirmed for that reason,
   becomes the post-change division. The passages already located are
   `tests/task/evals/README.md`'s "the prose verdict strings are the one place
   free-form response text is load-bearing" passage and its "stay for you to
   confirm from the captured `response.txt`" passage, `tests/task/evals/grade.sh`'s
   head block beginning "Output-verdict expectations" and ending "the
   LLM-graded expectations in evals.json", `tests/task/evals/run.py`'s
   "prose-verdict confirmation the operator does by reading `response.txt`"
   and "remain operator-confirmed" passages, and `tests/task/RUNBOOK.md`'s
   "leave verdict-string checks to `expectations[]` (agent-attest)" line. Each
   becomes a statement that the grader reads the response through
   `RESPONSE_FILE` and that `agent-attest` covers only the judgements no check
   can decide. The `grade.sh` head block is a distinct passage from the
   `coherence_wrote_nothing` comment step 3 already names.
4. **Prove the fail branch in the harness's own script tests.** Each harness's
   `script_tests/` gains one scenario that stages an eval, grades it against an
   empty response, and asserts a non-zero exit. That scenario is the regression
   pin: a later edit that removes the positive check turns it red.

Keep the added checks to one or two per eval. The aim is a floor that an inert
worker cannot clear, not full enforcement of every prose expectation.

**Out of scope:** Enforcing the operator-confirmed `agent-attest` prose
judgements generally, which keeps the operator's confirmation role for the
expectations this task leaves unenforced; the rewritten head comments and
`tests/task/evals/README.md` state that division once, in its post-change form. Adding new evals or new fixtures. Converting the
`task_create` / `task_fix` graders, which already fail an inert worker.

**Co-edits.** This task edits two runners beside the graders:
`tests/git_checkout/evals/run.py` gains the invocation record Approach step 1
needs and `tests/task/evals/run.py` gains the response plumbing Approach step 3
needs. Two sibling tasks rewrite runners and must be rebased over these edits,
not re-merged: [the git-review parallel-evals
task](tests_git-review-parallel-evals.md) rewrites
`tests/git_review/evals/run.py`, and [the task-hub parallel-evals
task](tests_task-hub-parallel-evals.md) rewrites `tests/task/evals/run.py` and
its `evals/test_run.py`, so that task rebases over this task's
`tests/task/evals/run.py` edit whichever lands second. No sibling task changes
a `grade.sh` check, so the added positive checks survive either landing order.
This task's own
`script_tests/` scenarios in `git_checkout`, `git_review`, `git_refresh`,
`git_auto_review`, `task`, and `task_auto_check` are separate from the
stage-guard scenario [the stage-guard task](tests_eval-stage-guard.md) adds to
`agent_spinner`, `git_auto_review`, and `guardrail_audit`; the two overlap only
on `git_auto_review/script_tests/run.sh`, so whichever lands second appends.

## Acceptance

- Running the inert-worker probe over every eval in `git_checkout`,
  `git_review`, `git_refresh`, `git_auto_review`, `task`, and
  `task_auto_check` — stage each eval, write an empty response file, grade —
  returns a non-zero exit for every eval in those harnesses. The probe
  re-derives its before-count from Context's measurement loop, and after the
  change it grades PASS for no eval in any of those harnesses.
- Each harness named above gains a `script_tests/` scenario that performs that
  probe over its own eval set and fails when any eval grades PASS, and the
  scenario is red before the grader edits and green after them.
- The evals named in Context — `git_checkout` 3, 5, 6, 7, `git_review` 7 and
  36, `git_refresh` 4, `git_auto_review` `declines_on_detached_head`, the eight
  `task` response-only evals, and the eleven `task_auto_check` evals — each
  carry at least one check whose predicate is false on an untouched sandbox
  and true only after the behaviour under test occurs. For an eval whose
  evidence is the helper invocation, that check proves the run reached the
  decision the eval tests: the recorded call together with its argument shape
  or the reported cause token, not the invocation record alone.
- The eight response-only `task` evals' graders read the response the runner
  passes them: a grading run against the captured `response.txt` resolves the
  planted subject, and the same run against an empty response file exits
  non-zero.
- Searching `tests/git_checkout/evals/grade.sh`,
  `tests/git_checkout/evals/README.md`, `tests/git_refresh/evals/grade.sh`,
  `tests/git_refresh/evals/README.md`, and every tracked file under
  `tests/task/`, each read as continuous prose with leading comment markers
  and hard wraps collapsed to single spaces and emphasis markers stripped,
  for `never decide the exit code`, `cannot read the agent's response text`,
  `never sees the agent's response text`, `cannot be checked here`, `which
  helper ran`, `the one place free-form response text is load-bearing`,
  `stay for you to confirm from the captured`, `remain operator-confirmed`,
  and `leave verdict-string checks to` returns no passage asserting that a
  response or helper-invocation expectation cannot decide the exit code, and
  every file the selector reaches states the post-change division in place.
- The probe is recorded for commit as a script or a note under
  `tests/lib/`, naming the command that runs it and the harness set it covers,
  so a later change can re-measure the same property rather than re-derive it.
- `make lint` passes, and `tests/AGENTS.md` and `tests/CLAUDE.md` name the new
  `script_tests/` scenario in their parallel-workers and coverage prose where
  those files already enumerate harness scenarios.
