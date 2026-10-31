---
description: "Reconcile tests-tree docs with the harness: stale scenario counts, a wrong fixture count, and a drifted parallel-workers section."
scope: "local test harnesses"
created: 2026-10-30T23:33:51
updated: 2026-10-30T23:41:12
status: open
reported-by: Andreas Hoffmann
---

# Reconcile the tests-tree docs with the harness they describe

## Goal

The committed descriptions of the test tree match what the tree actually
contains, so a reader sizing a run or checking coverage trusts them. Today
several scenario counts are stale, one fixture count is wrong, and the
parallel-workers section has drifted between the two operator guides that are
required to stay in lockstep.

The user-visible outcome: every count in `tests/README.md` and the
`tests/CLAUDE.md` inventory either states the command that derives it or
matches a fresh run, and the `### Parallel workers` sections of
`tests/AGENTS.md` and `tests/CLAUDE.md` state the same rule.

## Context

Measured on 2026-10-30 at commit `54680e4` against each harness's recorded
tally and its committed `evals.json`.

**Stale scenario counts.** `tests/README.md` says `git_commit/` has "31
bundled-script scenarios" while `tests/git_commit/results/layer1.log` records
33, `git_checkout/` "14" while its log records 15, `git_review/` "34" while
its log records 39, and `task/` "86 scenarios" while
`tests/task/script_tests/run.sh` carries 115.

**Wrong fixture count.** `tests/CLAUDE.md`'s `guardrail_audit/` row says "five
staged fixtures with byte-identity grading" while `evals/fixtures/` holds six
fixture directories — `direction_target`, `doc_vs_code`, `doc_vs_doc`,
`missing_testing`, `nature_mismatch`, `presence_gate`, beside `_common.sh` —
for the six evals in `evals/evals.json`.

The `git_review/` "48 behavioral evals over 36 fixtures" and `git_checkout/`
"seven behavioral evals over five fixtures" claims are correct as written and
stay untouched.

**Operator-guide drift.** `tests/AGENTS.md` and `tests/CLAUDE.md` are required
to stay in lockstep on the parallel-workers rule, stated in both files and in
the repo `AGENTS.md` **Regression test harnesses** section. Their `###
Parallel workers` sections already diverge: `CLAUDE.md` carries a heading with a
rationale clause and an extra sentence about raising the default past 4 that
`AGENTS.md` lacks.

**Why counts drift.** A frozen count restates a mutable set and goes stale on
the next added scenario, which is exactly what happened here. The repo `AGENTS.md`
task-family rules already prefer naming a mutable set by its selector over
freezing its size; these are not task files, but the reasoning transfers and the
drift is already real.

## Approach

Re-derive each number at implementation time rather than copying the values in
Context, and prefer a derivation over a frozen count where the count is not the
subject of the sentence.

1. **Replace frozen counts with their derivation.** In `tests/README.md` and
  the `tests/CLAUDE.md` inventory, state the command that counts the scenarios
  or evals where the surrounding sentence reads naturally that way, and correct
  the number where the sentence needs the magnitude. The tally line each
  harness's own `results/layer1.log` prints and `jq '.evals | length'` on its
  `evals.json` are the two derivations to name.
2. **Correct the `guardrail_audit` fixture count** in the `tests/CLAUDE.md` row
  to the number `ls tests/guardrail_audit/evals/fixtures` reports beside
  `_common.sh`.
3. **Bring the two operator guides back into lockstep** on `### Parallel
  workers`: one canonical statement per file, the same runner list, the same
  serial-exception lists. Keep whichever wording states the rule more precisely,
  and carry the extra sentence into both files rather than deleting it from one.

**Out of scope:** Rewriting harness-local `README.md` / `RUNBOOK.md` files
beyond what a wrong count in them requires. The stage-guard scenarios, which
[the stage-guard task](tests_eval-stage-guard.md) owns. Any change to what a
suite asserts.

**Co-edits.** The `### Parallel workers` sections are the same passages four
live tasks rewrite, so whichever lands second rebases. [The git-review
parallel-evals task](tests_git-review-parallel-evals.md) and [the task-hub
parallel-evals task](tests_task-hub-parallel-evals.md) both rewrite those two
sections' runner lists and serial-exception lists. [The trigger-evals
cursor-vendor task](tests_trigger-evals-cursor-vendor.md) rewrites the trigger
runner's entry in both sections. This task's job is only to bring the two
sections into lockstep, so it should land after the runner-list edits settle,
or restrict itself to the heading and the extra sentence if it lands first. The
`git_review/` inventory row in `tests/CLAUDE.md` and the `**git_review/**`
bullet in `tests/README.md` are also rewritten by the git-review parallel-evals
task; this task touches those only for a wrong count.

## Acceptance

- Every scenario count and eval count in `tests/README.md` and the
  `tests/CLAUDE.md` inventory either states the command that derives it or
  matches a fresh run of that harness's `script_tests/run.sh` and its
  `evals.json`; the four wrong numbers named in Context no longer appear where
  they were wrong.
- The `guardrail_audit` row in `tests/CLAUDE.md` states the number of fixtures
  the harness ships, and that number matches `ls
  tests/guardrail_audit/evals/fixtures` beside `_common.sh`.
- The `### Parallel workers` sections of `tests/AGENTS.md` and
  `tests/CLAUDE.md` name the same runner list and the same serial-exception
  lists, one canonical statement of the rule remains per file, and a diff of the
  two sections shows only heading wording differences the files' own lockstep
  rule permits.
- `make lint` passes.
