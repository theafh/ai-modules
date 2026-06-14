---
description: "Add composition guidance to the task skill: write frontmatter descriptions to roughly 180 characters, keeping the linter's 200-character warning as ceiling headroom."
scope: "task_* family skills"
created: 2026-06-09T10:45:16
updated: 2026-06-10T20:50:09
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Description length budget: compose to roughly 180 characters

## Goal

Task descriptions come out of creation at roughly 180 characters, comfortably
under the linter's 200-character warning, and the recurring lint → trim →
re-lint loop on overlong descriptions disappears.

## Context

- The overlong-description warn was the most frequent mechanical defect in
  recent task-family usage: at least six occurrences across creates and
  broadening rewrites (224, 228, 214, and 211 chars on live tasks, plus a
  212/213/209 trio on archived ones), and one trim landed at 201 characters,
  costing a second trim round.
- `task/SKILL.md` `<frontmatter>` documents the field as "compact one-liner
  (<=200 chars)" and the bundled `lint.py` warns above 200 — both treat 200 as
  the boundary, so composition happens right at the limit and any overshoot or
  later broadening edit trips the warn.
- `task_create` consumes `<frontmatter>` through its `<authority>` section, so
  guidance added in the base skill reaches the create path without a second
  copy.

## Approach

- Extend the `description` bullet in `task/SKILL.md` `<frontmatter>`: compose
  to roughly 180 characters; 200 stays the lint ceiling — headroom for a later
  broadening edit, rather than the length to write at.
- `lint.py` keeps its current 200-character warn threshold unchanged.

## Acceptance

- The base `<frontmatter>` description guidance names the ~180 composition
  target alongside the 200 ceiling.
- The 180 figure appears in `task/SKILL.md` and in no other family SKILL.md.
