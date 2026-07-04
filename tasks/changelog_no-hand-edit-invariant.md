---
description: Move the "changelog is committed-history-derived, never hand-edited" invariant into the update_changelog skill so the artifact owns it, then remove the duplicated standing repo rule.
scope: plugins/ai_dev/skills/update_changelog
created: 2026-06-21T13:25:38
updated: 2026-07-04T13:31:02
status: open
reported-by: Andreas Hoffmann
---

# Make the update_changelog skill own the committed-history, never-hand-edit invariant

## Goal

State, inside the `update_changelog` skill itself, the load-bearing invariant the
skill currently leaves implicit: a changelog records only **committed** git
history, every entry is produced by running the skill over commits, and the file
is never hand-authored or hand-edited — committing the skill's generated output is
how it is persisted. Today this invariant lives only as a standing repo
instruction local to this repo, so any repo that installs the skill without that
instruction inherits none of it. Make the shipped skill carry the invariant so it
travels with the artifact, then remove the now-duplicated standing repo rule once
the skill states it.

## Context

- Skill: `plugins/ai_dev/skills/update_changelog/SKILL.md`. The `<policy>` block
  governs day ordering, entry granularity, date immutability, and summary style,
  and its `<run_scope>` clause states "Build each run from committed git history
  only" — scoped to which days a run rebuilds. No clause forbids hand-editing or
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
  points at — that task's run-scope corollary now ships as the skill's
  `<run_scope>` clause, and this task owns the general invariant the corollary
  specializes.
- Motivating case: session `07a4d5ec`, where an agent hand-wrote entries for
  uncommitted working-tree changes and they had to be reverted — the failure this
  invariant prevents.
- The standing repo rule is also the always-in-context guard for an agent doing
  unrelated work in this repo, who never loads the skill. Removing it is therefore
  gated on the skill carrying the invariant: until the skill states it, the repo
  instruction is the invariant's only home.

## Approach

- Add a `<source_of_truth>` clause to the skill's `<policy>` block stating
  positively: the changelog records committed git history only; every entry is
  produced by running the skill over commits; the operator persists it by
  committing the skill's output; the file is never hand-authored or hand-edited.
  Frame the guardrail (never hand-edit) alongside the action (run the skill, commit
  its output).
- Reflect the invariant in `<objective>` as a brief provenance mention — name
  committed git history as the sole source — and keep the never-hand-edit
  prohibition and the commit-the-output mechanics in the `<source_of_truth>` clause
  alone, so `<objective>` stays a one-liner rather than duplicating the policy clause.
- State the invariant once. The skill's `<source_of_truth>` clause is the canonical
  statement, and the shipped `<run_scope>` clause already carries a standalone
  committed-history sentence: reconcile the two so the general invariant lives only
  in `<source_of_truth>`, with `<run_scope>` staying scoped to which days a run
  rebuilds and deferring to the canonical clause rather than restating it.
- After the skill carries the invariant, remove the duplicated changelog paragraph
  from the standing repo instructions mirrored in `CLAUDE.md` and `AGENTS.md`, since
  the portable artifact now owns it. Run this removal only once the skill change is
  in place — the repo rule is the interim always-on home and stays until then.

Non-goals: leave the day-section output format, the `prepare_changelog_day.sh`
script, and the date-enumeration logic unchanged (the incremental-day-boundaries
task owns enumeration); do not touch existing `CHANGELOG.md` content; per the
standing repo rules, leave any version bump to commit time rather than recording it
here.

## Acceptance

- The skill's `<policy>` carries a clause stating the changelog records committed
  git history only, entries are produced by running the skill, the file is never
  hand-authored or hand-edited, and committing the skill's output is how it is
  persisted. (Today `<run_scope>` covers only committed-history run scope; the
  hand-edit prohibition and output-persistence mechanics appear nowhere.)
- The `<objective>` names committed git history as the sole source of changelog
  content.
- The invariant is stated once in the skill: the `<source_of_truth>` clause is
  canonical, and the `<run_scope>` clause stays scoped to which days a run
  rebuilds, deferring to the canonical clause rather than restating the general
  invariant.
- After the skill carries the invariant, the standing repo instructions in
  `CLAUDE.md` and `AGENTS.md` no longer carry the changelog hand-edit paragraph (the
  duplicate is gone from both mirrored files), and no other passage in those files
  still states it.
- Reading the skill alone — without this repo's standing instructions — tells an
  operator the changelog comes from committed history and must not be hand-edited.
- The day-section output format and first-run behavior are unchanged.
