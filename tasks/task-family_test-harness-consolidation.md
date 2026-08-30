---
description: Consolidate the task skill's two local test directories into one, register every task-family harness in the tests inventory table, and add the missing task_auto_check trigger cases.
scope: "task_* family local test harness"
created: 2026-08-11T18:58:50
updated: 2026-08-30T14:39:20
status: ready
reported-by: Andreas Hoffmann
---

# Consolidate and complete the task-family test harness

## Goal

The `task_*` family's local test tree matches the layout the standing repo rules
describe and covers every sibling's routing. One directory holds the `task` skill's
harness instead of two, the tests inventory table names every task-family harness
that exists, and the trigger eval set carries cases for the one sibling that has
none. An operator opening the tests tree then finds each harness where its skill
name says it should be, and a routing regression on any family member surfaces.

## Context

The `task` skill's harness is split across two sibling directories. One holds the
skill's behavioral evals and the `lint.py` unit tests, under a directory named for
the plural `tasks`; the other holds the family contract assertions, a single
`run.sh` of `assert_contains` checks spanning the hub, its siblings, and the
family's agents. The standing repo rule puts one harness per skill under a
directory named for that skill, and the skill is named `task`.

The plural name is a leftover rather than a decision. [The skill rename](archive/task-family_rename-tasks-to-task.md)
renamed the skill from `tasks` to `task` across every artefact that names it, and
settled that the managed backlog directory keeps the name `tasks/` because the
skill manages that data. The test directory names the skill rather than the data,
so it belongs on the singular side of that split and was missed by the rename.

The archived sibling [task-family_cross-link-hygiene.md](archive/task-family_cross-link-hygiene.md)
stages its `lint.py` fixtures under `tests/tasks/script_tests/` and proves them
through `tests/tasks/run_all.sh`. Those paths name the plural harness this task
removes, so the consolidation rewrites that sibling's harness paths in place when
the directory moves.

The inventory table under the `## What's here` heading in the tests tree's own
`CLAUDE.md` lists four harnesses, none of them from the task family. The same file
contradicts that table elsewhere: its model-policy table and its verdict-cache
section both name the task family's eval runners by path. A reader trusting the
inventory concludes the family has no harness at all.

Standing repo rules send operators to `tests/README.md` for the full layout; its
`## Current harnesses` list likewise names none of the task-family directories.

The trigger eval set for the family covers the hub and every family sibling except
`task_auto_check`, and carries no case naming `task_auto_check` as the expected
skill. It is the closest neighbour to `task_check` and the only family member with
no routing test. The family's own preference is that `task_auto_check` is the route
to reach, rather than driving `task_check` by hand — the same preference that keeps
`task_check` out of the per-skill bullet lists in the plugin and root READMEs.

[The sibling trigger-routing task](archive/task-family_sibling-trigger-routing.md)
fixes the protocol any trigger-eval work here follows: `--runs-per-query 3`, a 50%
per-query threshold, and the verdict read from a run's written `results.json`
summary. Its Findings note records precise `15/25` on the then-25-entry set as
historical protocol precedent only — not this task's numeric floor. Dated
evidence that the archived fraction is already unreachable on today's file:
precise `15/31` and `18/31` on the then-current cohort
(`tests/trigger_evals/results/task/2026-08-11_204958/` and
`tests/trigger_evals/results/task/2026-08-11_210206/`). The pre-existing
cohort is always the entries in `tests/trigger_evals/task.json` as it stands
before any new `task_auto_check` cases land — derived at measurement time,
never a frozen entry count.

**Trigger no-regression bar (canonical):** Before adding cases, take a fresh
pre-change precise measurement on that pre-existing cohort under the recorded
protocol (or reuse a recent same-cohort precise run when `task.json` is
unchanged since that run). After the change, report the precise pass rate over
those same pre-existing entries against that measured baseline on the same
denominator. Added or re-annotated entries must never inflate the headline
rate, so a changed denominator is reported rather than absorbed. When the
post-change pre-existing precise rate lands below that baseline, the recorded
shortfall and its disposition in the Findings note are the deliverable — do
not chase the gap with description edits (see Out of scope).

The authored harness is committed and linted, so this consolidation's directory
move, new runners, and documentation edits land in git and must pass `make lint`;
the task file is no longer the only committed artefact of the work. Each acceptance
item is still verified by running the harness locally.

## Approach

Merge the two directories into the one named for the `task` skill, keeping both
surfaces intact and distinct inside it. Under Pattern A, the `lint.py` unit-test
suite becomes `tests/task/script_tests/run.sh`; the family contract assertions
become `tests/task/script_tests/contract_run.sh`; and `tests/task/run_all.sh`
drives both runners, matching the dual-runner layout `tests/deployment/run_all.sh`
already uses. The behavioral evals keep their existing structure under
`tests/task/evals/`. Re-point every path the move invalidates, including the
runner and cache references that name the old directory from the tests tree's
`CLAUDE.md` and from any harness script that resolves a sibling path, and from
the archived sibling [task-family_cross-link-hygiene.md](archive/task-family_cross-link-hygiene.md)
whose Approach and Acceptance still name `tests/tasks/script_tests/` and
`tests/tasks/run_all.sh`.

Rewrite the inventory table under `## What's here` in place so it names every
task-family harness that exists alongside the four already listed, with the same
columns the table already uses. Reconcile it with the model-policy table and the
verdict-cache section in that file so all three name the same directories.

Rewrite the `## Current harnesses` list in `tests/README.md` in place so it names
every post-merge task-family harness directory that exists on disk alongside the
entries already listed, keeping that section's existing bullet shape (directory
name, pattern, one-line coverage).

Add trigger eval cases naming `task_auto_check` as the expected skill, matching the
per-sibling case count the set already uses, and phrase them as the requests a user
actually makes to reach the loop rather than as variants of a readiness question
that the family accepts routing to `task_check`. Re-run the set under the recorded
protocol and report the new cases' own pass rate separately from the pre-existing
cohort, applying the **Trigger no-regression bar** in Context.

**Out of scope:** editing any `description:` frontmatter to move a routing result.
[The sibling trigger-routing task](archive/task-family_sibling-trigger-routing.md)
measured that lever and holds it rejected, and this task changes test coverage
rather than the skills under test.

## Acceptance

- One directory named for the `task` skill holds both surfaces, and the
  plural-named sibling directory no longer exists.
- Under that singular harness, `script_tests/run.sh` holds the lint suite,
  `script_tests/contract_run.sh` holds the family contract assertions, and
  `run_all.sh` drives both; the contract runner exits 0; the `lint.py` unit-test
  scenarios report the same pass count they report today; and the
  behavioral-evals tree is present under `evals/`.
- A search of the tests tree for the old plural directory path returns no
  references from any runner, cache helper, or documentation file.
- Every `tests/tasks/` harness path in
  [task-family_cross-link-hygiene.md](archive/task-family_cross-link-hygiene.md)
  Approach and Acceptance is rewritten in place to the singular `tests/task/`
  equivalent, and searching that sibling for `tests/tasks/` returns no
  harness-path hits.
- The inventory table under `## What's here` in the tests tree's `CLAUDE.md`
  names every task-family harness directory that exists on disk, and its rows
  agree with the directories named in that file's model-policy table and
  verdict-cache section.
- The `## Current harnesses` list in `tests/README.md` names every post-merge
  task-family harness directory that exists on disk alongside its prior
  non-family entries, so an operator following the standing-repo-rules pointer
  finds each family harness by skill-directory name.
- The family trigger eval set contains cases naming `task_auto_check` as the
  expected skill, where it contains none today, at the per-sibling count the set
  already uses.
- Those `task_auto_check` cases use loop-invocation phrasing — the requests a
  user actually makes to reach the autonomous readiness loop — rather than
  readiness-question variants the family accepts routing to `task_check`.
- The set is re-run under the recorded protocol (`--runs-per-query 3`, 50%
  per-query threshold), and the run's `results.json` summary is read for two
  separately reported numbers: the precise pass rate over the pre-existing
  entries (same cohort and denominator as the fresh pre-change baseline named
  by the **Trigger no-regression bar** in Context), and the pass rate over the
  newly added `task_auto_check` entries.
- Both numbers are written into this task body as a Findings note citing the new
  run directory and the pre-change baseline run used for comparison. When the
  pre-existing precise rate is at or above that baseline, the no-regression check
  passes. When it lands below, the Findings note records the shortfall and its
  disposition (accepted limitation under Out of scope — no description edits)
  rather than treating the shortfall as incomplete work; a `task_auto_check`
  pass rate below the per-query threshold is recorded the same way.
