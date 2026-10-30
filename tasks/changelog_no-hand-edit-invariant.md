---
description: Move the "changelog is committed-history-derived, never hand-edited" invariant into the update_changelog skill so the artifact owns it, then remove the duplicated standing repo rule.
scope: plugins/ai_dev/skills/update_changelog
created: 2026-06-21T13:25:38
updated: 2026-10-29T22:57:51
status: ready
reported-by: Andreas Hoffmann
---

# Make the update_changelog skill own the committed-history, never-hand-edit invariant

## Goal

State, inside the `update_changelog` skill itself, the load-bearing invariant the
skill currently leaves implicit: a changelog records only **committed** git
history, every entry is produced by running the skill over commits, and the file
is never hand-authored or hand-edited. Committing the skill's generated output is
how it is persisted. Today this invariant lives only as a standing repo
instruction local to this repo, so any repo that installs the skill without that
instruction inherits none of it. Make the shipped skill carry the invariant so it
travels with the artifact, then remove the now-duplicated standing repo rule once
the skill states it.

## Context

- Skill: `plugins/ai_dev/skills/update_changelog/SKILL.md`. The `<policy>` block
  governs day ordering, entry granularity, date immutability, and summary style,
  and its `<run_scope>` clause states "Build each run from committed git history
  only", scoped to which days a run rebuilds. No clause forbids hand-editing or
  names committing the skill's output as how the file is persisted. The
  `<objective>` calls the file "derived from git commits" without making the
  never-hand-edit prohibition explicit.
- The invariant currently lives as a standing repo instruction, mirrored in this
  repo's `CLAUDE.md` and `AGENTS.md`: "CHANGELOG.md is git-history-derived. Update
  it only through the update_changelog skill, run on demand. Don't hand-edit
  CHANGELOG entries as part of other work. Committing the skill's output is fine."
  That binds the rule to this one repo rather than to the skill that should own it.
  This task is the follow-up the "Only committed work counts" bullet in
  [changelog_incremental-day-boundaries.md](archive/changelog_incremental-day-boundaries.md)
  points at. That task's run-scope corollary now ships as the skill's
  `<run_scope>` clause, and that task owns the date-enumeration logic. This
  task owns the general invariant the corollary specializes.
- Motivating case: an agent hand-wrote entries for uncommitted working-tree
  changes and they had to be reverted, the failure this invariant prevents.
- The standing repo rule is also the always-in-context guard for an agent doing
  unrelated work in this repo, who never loads the skill. Removing it is therefore
  gated on the skill carrying the invariant: until the skill states it, the repo
  instruction is the invariant's only home.

## Approach

- Add a new `<source_of_truth>` sibling under the skill's `<policy>` block for
  changelog provenance, leaving the existing `<workflow_authority>` clause
  unchanged as the authority for `/update_changelog` workflow, output format, and
  entry style. The new clause states positively: the changelog records committed
  git history only; every entry is produced by running the skill over commits; the
  operator persists it by committing the skill's output; the file is never
  hand-authored or hand-edited. Frame the guardrail (never hand-edit) alongside
  the action (run the skill, commit its output).
- Reflect the invariant in `<objective>` as a brief provenance mention naming
  committed git history as the sole source, and keep the never-hand-edit
  prohibition and the commit-the-output mechanics in the `<source_of_truth>` clause
  alone, so `<objective>` stays a one-liner rather than duplicating the policy clause.
- State the invariant once. The skill's `<source_of_truth>` clause is the canonical
  statement, and the shipped `<run_scope>` clause already carries a standalone
  committed-history sentence: reconcile the two so the general invariant lives only
  in `<source_of_truth>`. Rewrite `<run_scope>` to this target text, keeping its
  second sentence verbatim and replacing the first with a deferring reference:

  ```text
  <run_scope>Build each run from the dates `<enumerate_dates>` selects, taking provenance from `<source_of_truth>`. On incremental runs, treat the most recent recorded day as provisionally complete because commits can share that calendar day after its section was first written. Reopen that day and every later committed date; days older than the most recent recorded day are settled for that run.</run_scope>
  ```

  Move the run-input half of the current first sentence into `<source_of_truth>`,
  because it states what a run reads rather than which days it rebuilds. Write the
  new clause as this settled text:

  ```text
  <source_of_truth>The changelog records committed git history only; ignore uncommitted and untracked working-tree state. Every entry is produced by running this skill over commits. The operator persists the changelog by committing the skill's output. Never hand-author or hand-edit `CHANGELOG.md`.</source_of_truth>
  ```

  The phrase `committed git history only` therefore stays in `<source_of_truth>`,
  where the existing `tests/update_changelog/script_tests/run.sh` skill-text
  assertion still finds it.
- After the skill carries the invariant, replace the duplicated changelog paragraph in
  the standing repo instructions mirrored in `CLAUDE.md` and `AGENTS.md` with the
  one-line pointer `CHANGELOG.md` is owned by the `update_changelog` skill. The pointer
  keeps an always-on route from the repo instructions to the owning artifact without
  restating the invariant the skill now carries: it names the skill and adds no
  provenance statement, no hand-edit prohibition, and no persistence mechanics. Run this removal only once the skill change is
  in place. The repo rule is the interim always-on home and stays until then.

- Land the skill text and its script pin together. `tests/update_changelog/script_tests/run.sh`
  is an edit site in this change: its `s1` scenario asserts `<run_scope>` exists and
  asserts the verbatim string `committed git history only`, a whole-file check this
  change relocates into `<source_of_truth>`. Keep both assertions green and extend
  `s1` with assertions that the skill text carries the `<source_of_truth>` clause and
  its never-hand-authored-or-hand-edited prohibition. The suite passes today and after
  the change with no failed scenario.

**Out of scope:**

- Changing the day-section output format.
- Changing the `prepare_changelog_day.sh` script.
- Editing existing `CHANGELOG.md` content.
- Recording a version bump in this change; the standing repo rules leave any
  version bump to commit time rather than recording it here.

## Acceptance

- The skill's `<policy>` carries a clause stating the changelog records committed
  git history only, entries are produced by running the skill, the file is never
  hand-authored or hand-edited, and committing the skill's output is how it is
  persisted. (Today `<run_scope>` covers only committed-history run scope; the
  hand-edit prohibition and output-persistence mechanics appear nowhere.)
- The existing `<workflow_authority>` clause still states the skill is the source
  of truth for `/update_changelog` workflow, output format, and entry style, and
  the provenance invariant lives in a separate `<source_of_truth>` sibling rather
  than by renaming, merging into, or replacing that clause.
- The `<objective>` names committed git history as the sole source of changelog
  content.
- The invariant is stated once in the skill: the `<source_of_truth>` clause is
  canonical, and the `<run_scope>` clause stays scoped to which days a run
  rebuilds, deferring to the canonical clause rather than restating the general
  invariant.
- After the skill carries the invariant, the standing repo instructions in
  `CLAUDE.md` and `AGENTS.md` carry the one-line pointer naming the `update_changelog`
  skill as the owner of `CHANGELOG.md`, and neither file restates the invariant: no
  passage in either file states committed-history-only provenance, the hand-edit
  prohibition, or the commit-the-output mechanics.
- Reading the skill alone, without this repo's standing instructions, tells an
  operator the changelog comes from committed history and must not be hand-edited.
- `git diff` shows no change to the day-section output format, first-run
  behavior, or date-enumeration logic in the skill; no change to
  `scripts/prepare_changelog_day.sh`; and no change to existing
  `CHANGELOG.md` content.
- `bash tests/update_changelog/script_tests/run.sh` exits 0 with no failed scenario
  after the change, and its `s1` scenario asserts both the `<source_of_truth>` clause
  and its statement that the file is never hand-authored or hand-edited, extracts the
  `<source_of_truth>` element from the skill text and asserts that element carries the
  sentence `ignore uncommitted and untracked working-tree state`, with the prior
  `committed git history only` assertion still green against the settled skill text.
