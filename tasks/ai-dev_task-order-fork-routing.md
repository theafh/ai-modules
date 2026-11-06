---
description: "Wire the live-task ordering fork to `<dependency_signals>` in the base task skill and the verifier, so directional evidence settles a ship order instead of surfacing it."
scope: plugins/ai_dev
created: 2026-11-06T10:47:26
updated: 2026-11-06T10:47:26
status: open
reported-by: Andreas Hoffmann
---

# Route a live-task ordering fork through `<dependency_signals>` before surfacing it

## Goal

A shared-surface collision between two live tasks is ordered from `<dependency_signals>` directional evidence by the readiness lenses and the verifier, so a ship order the task data already settles never reaches the user as an open preference.

## Context

The family's ordering rule already exists: `<dependency_signals>` in `plugins/ai_dev/skills/task/SKILL.md` defines a prerequisite as any live task at `open`, `checked`, or `ready`, and makes a hard ordering dependency hold on directional evidence — one task creates, renames, removes, or rewrites a block, symbol, rule, or file state the other consumes. A shared surface without that evidence is a soft companion relationship, which stays a user call.

The [dependency task](archive/task-family_honor-task-dependencies.md) lifted that block into the base skill and wired `task_select` and `task_implement` to consume it. The readiness path was never wired: `task_check` and `task_auto_check` judge a task's own body, and the gate and verifier agents apply that same checklist, so none of them consults the ordering rule. Two decision points show the gap. The `<readiness_checklist>` **Interaction scan** closes with "Route the disposition through Decide or label" and hands the fork over without naming `<dependency_signals>`, and **Decide or label**'s tier (d) says only "related and older tasks, both linked live siblings and archived precedent". `auto_verifier_task`'s human-input-boundary rule then rejects an ordering proposal made "without repository evidence", without saying that directional evidence counts as repository evidence or that a sibling's lifecycle stage is not evidence against the order.

A `task_auto_check` run on the `module-viewers` backlog hit this exactly: a task consuming the git-context resolver and the worktree read that two live siblings create was routed to the user as a ship-order preference, the verifier rejected the directionally grounded proposal, and three repair rounds plus an operator interruption followed before the order was recorded. The rule itself was never in doubt; the lenses did not reach it.

## Approach

Add a pointer at each decision point and leave the rule text where it lives; `<dependency_signals>` keeps owning the definition, following the consumption pattern the dependency task established.

In `plugins/ai_dev/skills/task/SKILL.md`, extend the **Interaction scan** routing bullet so a shared-surface collision between live tasks reads its order from `<dependency_signals>` before the fork is called open: directional evidence settles it as a hard ordering dependency and is reconciled, while a collision with no directional evidence stays a soft companion relationship and may surface.

In the same file, extend **Decide or label** tier (d) so related live siblings are read through `<dependency_signals>` for any ordering or ownership fork.

In `plugins/ai_dev/agents/auto_verifier_task.md`, extend the human-input-boundary rule to treat a stated order grounded in `<dependency_signals>` directional evidence as repository evidence, and to state that a sibling's lifecycle stage alone is not evidence against that order.

**Out of scope:** Changing `<dependency_signals>`'s own definition, its four signals, or its hard-versus-soft split; changing `task_select`'s ranking or `task_implement`'s prerequisite gate, which already consume that block.

## Acceptance

- A deterministic script test under `tests/task/script_tests/` fails against the current skill text and passes after the change, asserting that the **Interaction scan** routing bullet names `<dependency_signals>`.
- A deterministic check asserts that **Decide or label** tier (d) names `<dependency_signals>`.
- A deterministic check asserts that `auto_verifier_task.md` carries both the directional-evidence clause and the lifecycle-stage clause.
- The existing `tests/task` and `tests/task_auto_check` deterministic harnesses stay green after the change.
