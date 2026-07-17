---
description: Add a `task_select` sibling skill that ranks eligible live tasks by impact, implementation complexity, friction, and bug-fix priority, then recommends what to work on next.
scope: plugins/ai_dev
created: 2026-06-15T23:42:00
updated: 2026-06-16T21:37:14
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Add the `task_select` sibling skill

## Goal

Add a small read-only sibling skill named `task_select` that helps a user choose what to work on next from the current backlog. The skill reads eligible live task files, applies any user-provided scope narrowing, classifies candidates by expected impact, implementation complexity, and implementation friction, gives bug fixes preference when they are viable, and recommends the next task plus the natural next action for that task.

Eligible live task files are tasks in `tasks/` whose frontmatter status is neither `implemented` nor `audited`. Archived tasks are never candidates.

The output is a recommendation, not an edit. `task_select` does not change task files, statuses, timestamps, or archive location.

## Context

The task family already has focused siblings for creation, checking, implementation, audit, finishing, and tree repair. `task_select` fills the missing selection step before the next focused backlog action: when a user asks "what should I work on next", the agent should inspect the live backlog and make a grounded recommendation instead of choosing by filename order or recency.

Related family entries:

- [task_create](task-family_create-sibling-skill.md) created the focused single-task creation sibling.
- [task_check](task-family_check-sibling-skill.md) created the readiness gate for one task.
- [task_implement](task-family_implement-sibling-skill.md) created the implementation sibling that consumes one task.
- [task_finish](task-family_finish-sibling-skill.md) created the close-out sibling.

The base `task` skill remains the authority for discovering the tasks directory, open-vs-archived status, filename structure, and the query mechanics under `plugins/ai_dev/skills/task/SKILL.md`. `task_select` should reuse that authority rather than restating the file format. The new skill belongs under `plugins/ai_dev/skills/task_select/` and should be registered in the same plugin and repository metadata surfaces as the other `task_*` siblings.

## Approach

1. Create `plugins/ai_dev/skills/task_select/SKILL.md` with pseudo-XML structure and positive, action-oriented language.
2. Define activation around selection and prioritization requests, such as "what task should I do next", "pick the next task", "choose from the backlog", and "rank open tasks". Keep the boundary distinct from `task_check` (readiness of one named task), `task_implement` (build one chosen task), and the base `task` skill's broader list/query workflows.
3. Implement a read-only workflow:
   - discover `tasks/` through the base skill's bundled discovery script;
   - list eligible live task files only, excluding `tasks/archive/` and excluding live tasks whose frontmatter status is `implemented` or `audited`;
   - if the user narrows the scope, filter the eligible live tasks first by matching the requested scope group, filename prefix, frontmatter `scope`, or explicit task names;
   - when no eligible tasks remain after discovery or filtering, report that state and stop without recommending archived work;
   - read each candidate task in full before scoring it.
4. Define the ranking rubric in the skill body:
   - **Impact**: how valuable the task's stated outcome is to the project, users, maintainers, or the task family workflow.
   - **Implementation complexity**: how much code, documentation, metadata, testing, and cross-surface coordination the task appears to require.
   - **Implementation friction**: how likely the work is to stall because of missing context, external dependencies, unclear decisions, broad blast radius, or verification difficulty.
   - **Bug-fix preference**: when a task fixes broken, incorrect, or misleading behavior and is not blocked by high complexity or high friction, rank it ahead of non-bug work with similar impact.
5. Have the output name the recommended task first, state the suggested next action for it, then show the top alternatives and the reasoning. A `ready` task can point naturally to implementation; an `open` or `checked` task can point naturally to checking, refinement, or applying existing check findings. The reasoning should be concrete enough that the user can accept the recommendation or override it, but compact enough that this remains a selection helper rather than a full readiness review.
6. Register the skill in `plugins/ai_dev/README.md`, root `README.md`, both plugin manifests, and marketplace registrations according to the standing repo rules.
7. Run a repo-wide scan, including hidden plugin and marketplace metadata, for every place that enumerates or describes the `task_*` siblings, their lifecycle order, or the task-family layout. Update every hit that needs to include `task_select`. The current confirmed source surfaces are the root `README.md` layout tree, root `README.md` ai_dev skill list and lifecycle text, `plugins/ai_dev/README.md` skill list and lifecycle text, and the `<family>` blocks in `plugins/ai_dev/skills/task/SKILL.md`, `plugins/ai_dev/skills/task_create/SKILL.md`, `plugins/ai_dev/skills/task_check/SKILL.md`, `plugins/ai_dev/skills/task_implement/SKILL.md`, `plugins/ai_dev/skills/task_audit/SKILL.md`, `plugins/ai_dev/skills/task_finish/SKILL.md`, and `plugins/ai_dev/skills/task_fix/SKILL.md`. Use search terms such as `task_*`, `task_create`, `task_check`, `task_implement`, `task_audit`, `task_finish`, `task_fix`, `natural chain`, `create → check`, and `<family>` so any newly added or moved repo surface is updated too.

## Acceptance

- A new `plugins/ai_dev/skills/task_select/SKILL.md` exists with `name: task_select`, an H1 aligned to that name, pseudo-XML sections, and a description that triggers on next-task selection and backlog-prioritization requests.
- The skill's workflow discovers eligible live tasks through the base `task` skill, excludes `tasks/archive/` and live tasks whose frontmatter status is `implemented` or `audited`, reads each candidate task before scoring, and reports a clear no-candidate outcome when there are no eligible tasks.
- User scope narrowing is applied before ranking and supports at least scope-group language, filename prefixes, frontmatter `scope`, and explicit task names.
- The ranking rubric explicitly balances highest impact against lowest implementation complexity and lowest friction, and states the bug-fix preference for viable bug tasks.
- The output contract recommends one task first, states the suggested next action for that task, includes the top alternatives, and explains the tradeoff in impact, complexity, friction, and bug-fix priority without editing any task files.
- The new skill is registered in the ai_dev README, root README, Codex plugin manifest, Claude plugin manifest, and local marketplace registrations according to the standing repo rules.
- A repo-wide scan across source files and hidden plugin metadata confirms every remaining `task_*` sibling enumeration, lifecycle-order description, layout tree, skill list, and `<family>` block has been updated to include `task_select` where applicable.
- Focused trigger coverage distinguishes `task_select` from `task`, `task_check`, and `task_implement`.
