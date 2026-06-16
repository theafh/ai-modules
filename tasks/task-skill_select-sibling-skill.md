---
description: Add a `task_select` sibling skill that ranks open tasks by impact, implementation complexity, friction, and bug-fix priority, then recommends the next task to build.
scope: plugins/ai_dev
created: 2026-06-15T23:42:00
updated: 2026-06-15T23:42:00
status: open
reported-by: Andreas Hoffmann
---

# Add the `task_select` sibling skill

## Goal

Add a small read-only sibling skill named `task_select` that helps a user choose the next task to implement from the current backlog. The skill reads open task files, applies any user-provided scope narrowing, classifies candidates by expected impact, implementation complexity, and implementation friction, gives bug fixes preference when they are viable, and recommends the next task to hand to `task_implement`.

The output is a recommendation, not an edit. `task_select` does not change task files, statuses, timestamps, or archive location.

## Context

The task family already has focused siblings for creation, checking, implementation, audit, finishing, and tree repair. `task_select` fills the missing selection step before implementation: when a user asks "what should I work on next", the agent should inspect the live backlog and make a grounded recommendation instead of choosing by filename order or recency.

Related family entries:

- [task_create](archive/task-skill_create-sibling-skill.md) created the focused single-task creation sibling.
- [task_check](archive/task-skill_check-sibling-skill.md) created the readiness gate for one task.
- [task_implement](archive/task-skill_implement-sibling-skill.md) created the implementation sibling that consumes one task.
- [task_finish](archive/task-skill_finish-sibling-skill.md) created the close-out sibling.

The base `task` skill remains the authority for discovering the tasks directory, open-vs-archived status, filename structure, and the query mechanics under `plugins/ai_dev/skills/task/SKILL.md`. `task_select` should reuse that authority rather than restating the file format. The new skill belongs under `plugins/ai_dev/skills/task_select/` and should be registered in the same plugin and repository metadata surfaces as the other `task_*` siblings.

## Approach

1. Create `plugins/ai_dev/skills/task_select/SKILL.md` with pseudo-XML structure and positive, action-oriented language.
2. Define activation around selection and prioritization requests, such as "what task should I do next", "pick the next task", "choose from the backlog", and "rank open tasks". Keep the boundary distinct from `task_check` (readiness of one named task), `task_implement` (build one chosen task), and the base `task` skill's broader list/query workflows.
3. Implement a read-only workflow:
   - discover `tasks/` through the base skill's bundled discovery script;
   - list live tasks only, excluding `tasks/archive/`;
   - if the user narrows the scope, filter the live tasks first by matching the requested scope group, filename prefix, frontmatter `scope`, or explicit task names;
   - when no open tasks remain after discovery or filtering, report that state and stop without recommending archived work;
   - read each candidate task in full before scoring it.
4. Define the ranking rubric in the skill body:
   - **Impact**: how valuable the task's stated outcome is to the project, users, maintainers, or the task family workflow.
   - **Implementation complexity**: how much code, documentation, metadata, testing, and cross-surface coordination the task appears to require.
   - **Implementation friction**: how likely the work is to stall because of missing context, external dependencies, unclear decisions, broad blast radius, or verification difficulty.
   - **Bug-fix preference**: when a task fixes broken, incorrect, or misleading behavior and is not blocked by high complexity or high friction, rank it ahead of non-bug work with similar impact.
5. Have the output name the recommended task first, followed by the top alternatives and the reasoning. The reasoning should be concrete enough that the user can accept the recommendation or override it, but compact enough that this remains a selection helper rather than a full readiness review.
6. Register the skill in `plugins/ai_dev/README.md`, root `README.md`, both plugin manifests, and marketplace registrations per the repo rules. Because this adds a skill to an existing plugin, the plugin metadata must bump lockstep at commit time; the new `task_select` skill itself ships at `1.0.0`.

## Acceptance

- A new `plugins/ai_dev/skills/task_select/SKILL.md` exists with `name: task_select`, an H1 aligned to that name, pseudo-XML sections, and a description that triggers on next-task selection and backlog-prioritization requests.
- The skill's workflow discovers live tasks through the base `task` skill, excludes `tasks/archive/`, reads each candidate task before scoring, and reports a clear no-open-task outcome when there are no candidates.
- User scope narrowing is applied before ranking and supports at least scope-group language, filename prefixes, frontmatter `scope`, and explicit task names.
- The ranking rubric explicitly balances highest impact against lowest implementation complexity and lowest friction, and states the bug-fix preference for viable bug tasks.
- The output contract recommends one task first, includes the top alternatives, and explains the tradeoff in impact, complexity, friction, and bug-fix priority without editing any task files.
- The new skill is registered in the ai_dev README, root README, Codex plugin manifest, Claude plugin manifest, and local marketplace registrations according to the standing repo rules.
- Focused trigger coverage distinguishes `task_select` from `task`, `task_check`, and `task_implement`.
