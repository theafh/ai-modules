---
description: Add behavior eval harnesses for wiki_fix, wiki_import, and wiki_wrapup, the three prose-only front ends that ship no scripts and carry no coverage or documented reason for its absence.
scope: "local test harnesses"
created: 2026-08-11T18:59:52
updated: 2026-08-11T18:59:52
status: open
reported-by: Andreas Hoffmann
---

# Add behavior evals for the three wiki front-end skills

## Goal

`wiki_fix`, `wiki_import`, and `wiki_wrapup` each have a behavior eval harness
that exercises the promises their own skill files make, so a change to any of the
three is verified rather than assumed. Each harness produces a graded verdict per
scenario that a later change can be re-run against.

## Context

The local harness tree carries one harness for this family, covering the base
`wiki` skill's bundled scripts and its agent-level behavior. The three front ends
ship no bundled scripts, so the standing repo rule asking for eval coverage or an
explicit documented reason applies to them, and the tree's own README lists
neither a harness nor a reason for any of the three.

The promises to cover are stated in the skills themselves. `wiki_fix` invokes the
`auto_shaper_wiki` agent and returns its report verbatim, per its
`<surface_report>` policy. `wiki_import` and `wiki_wrapup` each emit a proposal
under the three headings `## New pages`,
`## Extensions to existing pages`, and `## Contradictions to reconcile`, and write
no wiki page before the user approves, with `wiki_import`'s raw capture the one
permitted pre-approval write per its
`<no_wiki_page_writes_before_approval>` contract.

The whole harness tree is gitignored, so this task's deliverable lives outside
version control and needs its shape stated here. The preferred layout the repo
names is the skill-creator-aligned one: scenarios in `evals/evals.json`, a
per-scenario fixture stager under `evals/fixtures/`, run output under
`workspace/iteration-N/`. The tree's convention pins the skill under test to one
fixed model so results do not drift with the host session, and keeps the
orchestrator and grader on the inherited model. The family's existing harness also
asserts two sandbox fail-safes on every scenario, no file written outside the
sandbox and no wiki created in the operator's real home directory, which is what
lets it run on a real machine without a container.

Co-edit: [tests_trigger-eval-harness-repair.md](tests_trigger-eval-harness-repair.md)
and [task-family_test-harness-consolidation.md](task-family_test-harness-consolidation.md)
both edit the tree README's harness listing, so coordinate that one section.

## Approach

1. Stage one harness per skill under the tree, following the preferred layout: a
   scenario set, a fixture stager per scenario that builds a wiki sandbox with a
   fake home directory, and a runner that spawns the skill under test at the
   pinned model.
2. Cover per skill: for `wiki_fix`, that the agent is invoked and its report comes
   back verbatim; for `wiki_import`, raw capture plus proposal shape plus no
   pre-approval page write; for `wiki_wrapup`, proposal shape plus no pre-approval
   write.
3. Grade deterministically wherever the filesystem answers the question, since a
   page written before approval either exists or does not and the three headings
   either appear or do not, and reserve subagent grading for prose-shape
   expectations.
4. Record each harness in the tree README's harness listing with its pattern and
   what it covers.

**Out of scope:**

- Coverage for the base `wiki` skill, which has its own harness.
- Migrating that legacy two-layer harness to the preferred layout, which the repo
  defers to its next significant iteration.

## Acceptance

1. Each of the three skills has a scenario set covering the promises named in
   Context, with one fixture stager per scenario that builds its sandbox and
   leaves the operator's real home wiki untouched.
2. A run of each harness writes a graded verdict per scenario, and the
   no-pre-approval-write expectation fails when a scenario is deliberately mutated
   to write a page before approval, proving the check has teeth rather than
   passing vacuously.
3. The `wiki_fix` harness asserts both that the agent was invoked and that the
   returned report matches the agent's report rather than a paraphrase of it.
4. Every scenario asserts the two sandbox fail-safes the family's existing harness
   uses, and a full run leaves no file outside its sandbox.
5. The tree README's harness listing names all three harnesses with pattern and
   coverage, so the gap it records today is closed.
