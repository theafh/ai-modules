---
description: Consolidate the task skill's two local test directories into one, register every task-family harness in the tests inventory table, and add the missing task_auto_check trigger cases.
scope: "task_* family local test harness"
created: 2026-08-11T18:58:50
updated: 2026-08-11T18:58:50
status: open
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

The inventory table under the `## What's here` heading in the tests tree's own
`CLAUDE.md` lists four harnesses, none of them from the task family. The same file
contradicts that table elsewhere: its model-policy table and its verdict-cache
section both name the task family's eval runners by path. A reader trusting the
inventory concludes the family has no harness at all.

The trigger eval set for the family covers the hub and eight siblings, and carries
no case naming `task_auto_check` as the expected skill. It is the closest neighbour
to `task_check` and the only family member with no routing test. The family's own
preference is that `task_auto_check` is the route to reach, rather than driving
`task_check` by hand — the same preference that keeps `task_check` out of the
per-skill bullet lists in the plugin and root READMEs.

[The sibling trigger-routing task](archive/task-family_sibling-trigger-routing.md)
fixes the protocol any trigger-eval work here follows: `--runs-per-query 3`, a 50%
per-query threshold, and the verdict read from a run's written `results.json`
summary. It also established that added or re-annotated entries must never inflate
the headline rate, so a changed denominator is reported rather than absorbed.

The whole tests tree is gitignored, so this task file is the only artefact of this
work that gets committed, and every acceptance item below is verified locally.

## Approach

Merge the two directories into the one named for the `task` skill, keeping both
surfaces intact and distinct inside it: the family contract assertions stay their
own `run.sh` under the script-tests surface, and the behavioral evals and `lint.py`
unit tests keep their existing structure. Re-point every path the move invalidates,
including the runner and cache references that name the old directory from the
tests tree's `CLAUDE.md` and from any harness script that resolves a sibling path.

Rewrite the inventory table under `## What's here` in place so it names every
task-family harness that exists alongside the four already listed, with the same
columns the table already uses. Reconcile it with the model-policy table and the
verdict-cache section in that file so all three name the same directories.

Add trigger eval cases naming `task_auto_check` as the expected skill, matching the
per-sibling case count the set already uses, and phrase them as the requests a user
actually makes to reach the loop rather than as variants of a readiness question
that the family accepts routing to `task_check`. Re-run the set under the recorded
protocol and report the new cases' own pass rate separately from the pre-existing
denominator, so the headline rate stays comparable to the recorded baseline.

**Out of scope:** editing any `description:` frontmatter to move a routing result.
[The sibling trigger-routing task](archive/task-family_sibling-trigger-routing.md)
measured that lever and holds it rejected, and this task changes test coverage
rather than the skills under test.

## Acceptance

- One directory named for the `task` skill holds both surfaces, and the
  plural-named sibling directory no longer exists.
- The family contract assertions and the behavioral evals both run from their new
  home and pass: the contract `run.sh` exits 0, and the `lint.py` unit-test
  scenarios report the same pass count they report today.
- A search of the tests tree for the old plural directory path returns no
  references from any runner, cache helper, or documentation file.
- The inventory table under `## What's here` names every task-family harness
  directory that exists on disk, and its rows agree with the directories named in
  that file's model-policy table and verdict-cache section.
- The family trigger eval set contains cases naming `task_auto_check` as the
  expected skill, where it contains none today, at the per-sibling count the set
  already uses.
- The set is re-run under the recorded protocol (`--runs-per-query 3`, 50%
  per-query threshold), and the run's `results.json` summary is read for two
  separately reported numbers: the pass rate over the pre-existing entries, at or
  above the rate recorded in [the sibling trigger-routing task](archive/task-family_sibling-trigger-routing.md)'s
  Findings note, and the pass rate over the newly added `task_auto_check` entries.
- Both numbers are written into this task body as a Findings note citing the new
  run directory. A `task_auto_check` pass rate below the per-query threshold is
  recorded there with its disposition rather than chased with description edits.
