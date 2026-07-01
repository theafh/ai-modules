---
description: Add a readiness-checklist content-lens item that flags an H1 title or frontmatter description whose named scope is narrower than the body it heads, so a stale under-naming title is caught.
scope: plugins/ai_dev/skills/task
created: 2026-06-28T17:33:01
updated: 2026-07-01T19:09:39
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Readiness checklist: flag a title or description narrower than the body it heads

## Goal

The base `task` skill's `<readiness_checklist>` confirms a body has a single `# Title` (presence only) and that `description` is within its length budget, but nothing checks that the title's or description's *named scope* still covers what the body delivers. When a task is rewritten to carry more deliverables, the title often keeps naming the old, narrower set — a title naming two threads over a five-thread body — and no current check catches it, because under-naming leaves no internal contradiction to trip on. Add one content-lens item so a stale, under-naming H1 title or `description` surfaces as a readiness finding from the current file alone, with no git history needed.

## Context

The checklist lives once in the base `task` skill's `<readiness_checklist>` as the single source; `task_check` assesses by reference to it and `task_create` self-checks drafts against it. That single-source home was established by [the shared-readiness-checklist task](task-skill_shared-readiness-checklist.md).

Today's gaps, by anchor:

- The content lens's **Structural check** confirms only that a single `# Title` is *present*.
- The **Contradictions** item catches a title that *contradicts* the body (paraphrase drift), not one that merely *under-names* it.
- In `lint.py`, `H1_RE` is presence-only and the `description` check is length-only; neither compares title or description scope to body coverage.

Motivating case: a review-output-contract task in a sibling repo grew from a four-thread to a five-thread body while its H1 kept naming two threads — invisible to every current check, surfaced only by reading the file's history. This item closes that gap from current state.

## Approach

Add one new content-lens item to the base `task` skill's `<readiness_checklist>` — e.g. **Title/description coverage** — that flags an H1 title or frontmatter `description` whose named scope is narrower than the deliverables or sections the body now carries, framing the fix as widening the title or description to cover the body per **Rewrite in place**. Keep it distinct from the presence-only **Structural check** and from **Contradictions** (under-coverage is not a contradiction), and point at those rather than restating them, per **State once**.

Place the item only in the base checklist; add no second copy to `task_check`, which inherits it through its assess-by-reference design. Confirm `task_check` still defers to the base `<readiness_checklist>` rather than carrying its own list.

Keep the check model-applied. The judgment — does the title's named scope cover the body's deliverables — is semantic, so it belongs in the checklist lens, not as a new mechanical rule in `lint.py`; leave the linter's presence-only `H1_RE` and length-only `description` checks unchanged. This is the deliberate split: the linter stays mechanical and current-state-fast, the semantic coverage judgment lives in the checklist.

This edits shipped skill content under `plugins/ai_dev/`, so the standing plugin-version-bump and validation gates apply.

## Acceptance

- The base `task` skill's `<readiness_checklist>` carries a new content-lens item that flags an H1 title or frontmatter `description` whose named scope is narrower than the body's deliverables or sections; grepping the checklist finds it.
- The item reads as distinct from the **Structural check** (presence) and **Contradictions** (consistency) and points at them rather than restating either, per **State once**.
- `task_check` gains no separate copy of the rule and still assesses by reference to the base `<readiness_checklist>`.
- `lint.py` is unchanged: its `H1_RE` stays presence-only and its `description` check stays length-only; no new mechanical coverage rule is added.
- The item carries the under-naming example that fixes its meaning — a title naming fewer threads than its body delivers flips the finding on, a title that covers the body flips it off.
