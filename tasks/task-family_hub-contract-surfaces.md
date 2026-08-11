---
description: Give the base task skill an output_contract and widen not_in_scope to state when a focused sibling is the better route than the hub itself.
scope: plugins/ai_dev/skills/task
created: 2026-08-11T18:58:50
updated: 2026-08-11T18:58:50
status: open
reported-by: Andreas Hoffmann
---

# Complete the base task skill's contract surfaces

## Goal

The base `task` skill states what a run reports back and when a focused sibling
serves a request better than the hub does. An agent that has loaded the hub then
hands off deliberately instead of absorbing work a sibling owns, and closes every
workflow in one predictable reporting shape. Two sections of
`plugins/ai_dev/skills/task/SKILL.md` change: a new `<output_contract>`, and a
widened `<not_in_scope>` that carries the sibling-preference boundary beside the
wiki boundary it already states.

## Context

Every `task_*` sibling skill under `plugins/ai_dev/skills/` carries an
`<output_contract>` section. The hub carries none. Its sections run from `<role>`
through `<family>` with no statement of what a run returns, so each hub workflow
(`<create>`, `<query>`, `<update>`, `<archive>`, `<lint>`) ends without a shared
reporting shape while its front ends all define one.

The sibling contracts show the shape the hub is missing. They report the files
touched with their relative paths, the linter outcome, and every assumption or
judgement call left for the user — `task_create` reports "the relative path of the
one task file created", `task_fix` closes on `audit complete — N issues resolved,
K flagged for review`, and `task_select` opens its report with `# Recommendation`
and states it makes no edits.

The hub's `<not_in_scope>` states one boundary only, led by "The wiki skill
captures durable knowledge". Nothing in the body says when a request naming a
single task is better served by a focused sibling than by the hub. The `<family>`
section already lists every sibling with a one-line role, so the new boundary
points at that list rather than repeating it.

The boundary is a routing preference rather than a capability denial: `<family>`
opens by stating the hub "can do all of the backlog work itself", and that stays
true.

The router reads only `description:` frontmatter and never the body, a limit
measured by [the sibling trigger-routing task](archive/task-family_sibling-trigger-routing.md).
A body-level boundary therefore changes how an already-loaded agent hands off and
leaves trigger routing untouched.

## Approach

Write `<output_contract>` as one section covering every hub workflow rather than a
per-workflow contract, since the workflows already differ in their steps and share
their reporting needs: the files touched with relative paths, the status or
lifecycle move made where one applies, the linter outcome, and the assumptions and
judgement calls the user should correct. Follow the sibling contracts' altitude,
and place the section where the siblings place theirs so a reader moving between
family files finds it in the same position.

Widen `<not_in_scope>` in place so it holds both boundaries as one statement of
what the hub defers: keep the existing wiki sentence as the single canonical
statement of that boundary, and add the sibling-preference boundary next to it,
pointing at `<family>` for the per-sibling roles. State the preference positively —
a request naming one task and one lifecycle step is served by the sibling that owns
that step, while broad or multi-task backlog work stays with the hub.

**Out of scope:** editing the hub's `description:` frontmatter to cede sibling
verbs or add a counter-boundary. [The sibling trigger-routing task](archive/task-family_sibling-trigger-routing.md)
measured that lever, recorded a regression from precise 14/25 to 12/25 and family
20/25 to 14/25, reverted it, and holds the approach rejected; it also records the
hub firing for a bare action verb as a known accepted limitation.

## Acceptance

- `rg '<output_contract>' plugins/ai_dev/skills/task/SKILL.md` returns a hit,
  where it returns nothing today.
- The new section names, at minimum, the relative paths of files touched, the
  linter outcome, and the assumptions or judgement calls surfaced for the user.
- `python3 plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py plugins/ai_dev/skills/task/SKILL.md`
  reports PASS with the new tag closed and snake_case.
- The hub's `<not_in_scope>` states the sibling-preference boundary, and the
  sentence led by "The wiki skill captures durable knowledge" remains the single
  statement of the wiki boundary rather than being duplicated elsewhere in the body.
- The sibling boundary refers to `<family>` for the per-sibling roles, so one
  canonical sibling list remains in the file.
- The hub's behavioral eval set gains one scenario asserting that a hub run closes
  in the shape the new `<output_contract>` defines, and it passes. That eval set
  lives in the hub's `evals/evals.json`, whose directory
  [the test-harness consolidation task](task-family_test-harness-consolidation.md)
  relocates.
