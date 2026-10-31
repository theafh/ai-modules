---
description: "Reconcile tests-tree docs with the harness: stale scenario counts, wrong fixture counts, and a drifted parallel-workers section."
scope: "local test harnesses"
created: 2026-10-30T23:33:51
updated: 2026-10-31T10:50:49
status: ready
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

**Scenario counts.** The `git_commit/`, `git_checkout/`, and `git_review/`
sentences each state a base count plus named extras whose sum matches the
recorded tally — 33, 15, and 39 respectively — so those sentences stay as
written and the sweep verifies their totals. The `task/` sentence is stale:
it says "86 scenarios" where `tests/task/script_tests/run.sh` carries 115.

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

1. **Settle each count against its derivation.** In `tests/README.md` and
   the `tests/CLAUDE.md` inventory, state the command that counts the scenarios
   or evals where the surrounding sentence reads naturally that way, and correct
   the number where the sentence needs the magnitude. The `git_commit/`,
   `git_checkout/`, and `git_review/` sentences already state a base count plus
   named extras whose sum matches the harness tally, so keep those numerals and
   verify the sum; correct `task/`'s "86 scenarios" to the tally
   `bash tests/task/script_tests/run.sh` prints. The two derivations to name are
   `bash tests/<harness>/script_tests/run.sh`, whose tally line reports the
   scenario count, and `jq '.evals | length'` on that harness's `evals.json` for
   the eval count.
2. **Correct every fixture count** in `tests/README.md` and the
   `tests/CLAUDE.md` inventory to the number of fixture directories
   `ls tests/<harness>/evals/fixtures` reports beside that harness's shared
   helper files, re-finding each count by that selector rather than from a
   fixed harness list. That reaches the `guardrail_audit` row and bullet and
   the `skill_doctor` row and bullet; where a sentence enumerates its fixtures,
   the enumeration names every directory the selector finds, `direction_target`
   among the `guardrail_audit` fixtures.
3. **Bring the two operator guides back into lockstep** on `### Parallel
   workers`: unify the whole section body, not only the extra sentence. Keep
   `tests/CLAUDE.md`'s body text in both files — the sentence about raising the
   default past 4, the `Do not put this default in TESTING.md` note, the helper
   paragraph, and the bulleted runner enumeration — so the two section bodies
   read identically. Rewrite the operator-knobs sentence file-neutrally, as
   "Operator knobs live in this file and its twin guide, plus the runner
   `--workers` default.", so the one shared wording reads correctly in both
   guides; the heading line is then the one permitted difference:
   `tests/AGENTS.md` keeps `### Parallel workers` and `tests/CLAUDE.md` keeps
   its `: default 4 only where each job has its own sandbox` clause.

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
runner's entry in both sections. This task brings the two sections fully into lockstep against the tree as it
stands, then rebases onto the runner-list edits when the three sibling tasks
land; the full lockstep holds whichever of them lands first. The
`git_review/` inventory row in `tests/CLAUDE.md` and the `**git_review/**`
bullet in `tests/README.md` are also rewritten by the git-review parallel-evals
task; this task touches those only for a wrong count.

## Acceptance

- Every scenario count and eval count in `tests/README.md` and the
  `tests/CLAUDE.md` inventory either states the command that derives it or
  matches a fresh run of that harness's `script_tests/run.sh` and its
  `evals.json`. For each count sentence named in Context, the stated total —
  the base count plus every extra the same sentence names — equals the tally
  that harness's `script_tests/run.sh` prints, and the `task/` sentence states
  that tally rather than 86.
- Every fixture count in `tests/README.md` and the `tests/CLAUDE.md`
  inventory matches the number of fixture directories
  `ls tests/<harness>/evals/fixtures` reports beside that harness's shared
  helper files, with the members re-found by that selector over every harness
  that states a fixture count; the `guardrail_audit` and `skill_doctor` counts
  in both files match it, and where a count enumerates its fixtures, the
  enumeration names every directory the selector finds.
- The `### Parallel workers` sections of `tests/AGENTS.md` and
  `tests/CLAUDE.md` have identical body text: the same runner list, the same
  serial-exception lists, the same `TESTING.md` note, the same helper
  paragraph, and the same operator-knobs sentence, worded so it reads correctly
  in either file. A diff of the two sections shows only the heading line, which
  `tests/AGENTS.md` writes as `### Parallel workers` and `tests/CLAUDE.md` as
  `### Parallel workers: default 4 only where each job has its own sandbox`.
- `make lint` passes.
