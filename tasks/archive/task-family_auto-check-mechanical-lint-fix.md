---
description: Add a task_auto_check step that auto-fixes a task's mechanical lint findings (overlong description, broken links, datetime/format) before reporting done, even when task_check already stamped it ready.
scope: "task_* family: task_auto_check + base task <lint>"
created: 2026-06-29T18:48:53
updated: 2026-07-01T19:58:13
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# task_auto_check: auto-fix mechanical lint findings on the task before reporting ready

## Goal

`task_auto_check` prepares one task for implementation by looping `task_check` over the body and applying verified body repairs, but it never brings the file to a clean linter state. Its only linter touch sits in `<apply_repairs>`, which runs the linter to "fix any blocking finding introduced by the edit" — a post-edit regression guard that ignores pre-existing findings, and that the loop skips entirely when `<gate>` sees an immediate `ready` verdict and stops with "zero further edits were needed". So a task that is body-ready but carries a mechanical lint finding gets stamped `ready` (or surfaced) with that finding reported and unrepaired; the motivating case was an over-budget `description` the loop named but left for the user.

Give `task_auto_check` a standing step that brings its single target file to mechanical lint-clean before it reports done. The step auto-fixes the mechanically-fixable findings — an overlong `description` via a meaning-preserving rewrite, a broken local cross-reference link, a non-ISO datetime, frontmatter and markdown-policy fixes the task linter enforces — and leaves judgement-call findings surfaced rather than guessed. The altitude is the general behavior the incident argues for (auto-fix the mechanical findings), with the overlong `description` as its motivating illustration. Outcome: a `task_auto_check` run leaves the file both body-ready and lint-clean, instead of reporting a mechanical finding it declined to fix.

## Context

The relevant surfaces, each located by a greppable label:

- In `task_auto_check`, the linter runs only inside `<apply_repairs>` ("fix any blocking finding introduced by the edit"), and `<gate>` returns early on an immediate `ready` verdict ("stop successfully and report that zero further edits were needed"). Together these are why a pre-existing mechanical finding survives a run untouched.
- `task_check`'s `<assessment>` judges the body against the base `task` skill's `<readiness_checklist>`; it does not assess lint conformance, so a task can hold a clean readiness verdict while still tripping the linter. Lint cleanliness and readiness are separate axes.
- The base `task` skill's `<lint>` defines the blocking / warn / info buckets, and its `<frontmatter>` sets the `description` budget ("roughly 180 characters; the linter warns above 200"). An over-budget `description` is a warn, not a blocker — which is why the narrow blocking-only guard in `<apply_repairs>` never touches it.
- The family already carries the "mechanical, inline-fixable" repair notion: `task_fix`'s `<workflow>` remediate phase auto-fixes "the safe mechanical findings in place" — frontmatter, status, location, link, datetime, provenance — across the whole tree, and routes the rest to `<surface_for_review>`. This task brings that same notion to `task_auto_check`'s single file. It is a rule two siblings now share, so it is single-sourced per the standing repo rule that a skill-family rule is authored once in the family's base skill (see the Approach open decision for where).
- Co-edit on `task_auto_check`'s `<loop_policy>`: the [intent-drift task](task-family_intent-drift-detection.md) adds a *human-route* boundary there, modeled on `<structural_split_boundary>`; this task adds an *auto-fix* path. They compose into one taxonomy — auto-fixable findings (verified body repairs, and now mechanical lint findings) versus surfaced or human-routed findings (structural splits, intent drift, undeterminable mechanical fixes). Land both without duplicating or contradicting the other's boundary wording.
- A `description` rewrite must preserve the description's *named scope*, not just its gist, so it cannot create the under-naming finding the [title/description coverage task](task-family_title-body-coverage-check.md) adds to the readiness checklist.
- This edits shipped skill content under `plugins/ai_dev/`, so the standing plugin-version-bump and validation gates apply.

## Approach

**Open decision: where the shared "mechanically-fixable lint finding" set is authored.** Default — name it once in the base `task` skill's `<lint>` as a finding-type subset (datetime normalise, broken local link re-point, missing or malformed frontmatter fill, soft-pointer line-number strip, provenance backfill, markdown-policy conversion of a linter-blocked stray wikilink or footnote to standard markdown when the conversion target is determinable, and the over-budget `description` rewrite as a mechanical-with-care fix), and let each sibling apply the subset in its own context: `task_fix` tree-wide including archive moves, `task_auto_check` on its single open file. Anchor `task_fix`'s existing remediate enumeration to that base subset with a light citation, keeping its operational prose intact rather than rewriting it. This honors the single-source repo rule and resolves the tree-versus-single-file mismatch by sharing finding *types*, not their application. Lighter alternative an implementer may take instead: leave the set in `task_fix`'s remediate phase and have `task_auto_check` cite it sibling-to-sibling, accepting the archive-specific bits that do not apply to a single open task. The new `task_auto_check` behavior is identical either way; only the authoring location differs.

Add the mechanical-lint-clean step to `task_auto_check` with these properties:

1. It runs on every exit path before the run reports done — including the immediate-`ready` early return in `<gate>`, which today bypasses all linter work. Placing it as a finalization step that always executes is the natural fit, so a body-ready but lint-dirty task still gets cleaned.
2. It runs the base task linter directory-wide — the same `lint.py --quiet` discovery-based invocation the existing `<apply_repairs>` guard already uses, which auto-discovers `tasks/` and reports findings per file — then reads the findings attributed to the target file across all severities (rather than the blocking-only, edit-introduced findings the `<apply_repairs>` guard weighs) and resolves the mechanically-fixable ones in place: rewrite an over-budget `description` within budget while preserving its meaning and named scope; re-point a broken local cross-reference link when its correct target is determinable; normalise a non-ISO datetime; fill malformed frontmatter; convert a markdown-policy violation the task linter blocks, such as a stray wikilink or footnote, to standard markdown.
3. It applies these mechanical fixes directly, separate from the body-repair reviewer/verifier path, which stays scoped to the `task_check` issues it already serves. Mechanical fixes do not re-gate `task_check`, because they leave body readiness unchanged; the `description` rewrite preserves named scope precisely so it introduces no readiness regression.
4. It leaves judgement-call findings surfaced rather than guessed, modeled on `<structural_split_boundary>`: an oversized page that needs a split, a broken link with no determinable target, anything the shared subset marks "surface". This composes with the intent-drift boundary on `<loop_policy>` rather than restating it.
5. It bumps `updated` once when it changes the file and leaves `updated` untouched when it makes no change, validates the edit group against `CHARTER.md` when present exactly as `<apply_repairs>` already does, and re-runs the directory-wide linter to confirm the target file's findings are cleared before reporting.

Reflect the new behavior in `task_auto_check`'s `<output_contract>`: report the mechanical fixes applied and any finding surfaced-but-not-fixed, alongside the existing readiness report.

Non-goals: deeper markdown *style* beyond what the task linter enforces (blank-line and bullet-style nits stay with the standing repo `make lint` gate); auto-resolving structural splits or intent drift (those stay surfaced or human-routed); and promoting a body-readiness `checked` verdict to `ready` on the strength of lint cleanliness, since readiness stays `task_check`'s call.

## Acceptance

- `task_auto_check` carries a standing mechanical-lint-clean step that a grep of its `SKILL.md` finds, and the step runs before the run reports done.
- Motivating case, on a staged fixture: a task whose body is already readiness-clean but whose `description` exceeds the budget runs through `task_auto_check`, and the run rewrites the `description` within budget — preserving its meaning and named scope — and the post-fix directory-wide re-lint reports no remaining findings against the target file. This proves the step executes on the immediate-`ready` path where `<gate>` would otherwise stop with zero edits.
- The `description` rewrite supersedes the stale over-budget text: after the run, one canonical `description` remains within budget and the prior over-budget wording is gone, not appended beside it.
- On a staged task with a broken local cross-reference whose target is determinable, the step re-points the link; on a staged task whose target is not determinable, the step surfaces it unfixed rather than guessing.
- On a staged task with a non-ISO datetime or malformed frontmatter, the step normalises or fills it and the re-lint comes back clean.
- On a staged task carrying a stray wikilink or footnote that the task linter blocks, the step converts it to standard markdown and the re-lint comes back clean.
- The mechanical-fix path is separate from the body-repair reviewer/verifier path and does not re-run `task_check`: inspection of the step confirms it neither spawns the reviewer/verifier agents for these findings nor re-gates readiness after applying them.
- Judgement-call findings stay surfaced: a staged oversized task is reported for a split rather than auto-edited, and the step cites `<structural_split_boundary>` as its model and composes with the drift boundary the [intent-drift task](task-family_intent-drift-detection.md) adds to `<loop_policy>` without duplicating or contradicting it.
- The step bumps `updated` once when it changes the file, leaves `updated` unchanged when it makes no change, and validates its edit group against `CHARTER.md` when present, matching the existing `<apply_repairs>` charter guard.
- `task_auto_check`'s `<output_contract>` reports both the mechanical fixes applied and any finding surfaced-but-not-fixed.
- The mechanically-fixable finding set is single-sourced per the open decision's resolution: a grep confirms one authoritative list that the other sibling cites, rather than two divergent copies across `task_fix` and `task_auto_check`.
