---
name: task_select
description: Select and rank eligible live tasks from the project backlog. Use when the user asks what task to work on next, asks Codex to pick or prioritize backlog work, rank open tasks, choose from tasks/, or recommend the next task/action without editing task files.
version: 1.0.5
author: Andreas F. Hoffmann
license: MIT
---

# task_select

<task_select_skill>

<role>
task_select is the read-only selector for the project's `tasks/` backlog. It reads eligible live task files, applies any user-provided scope narrowing, ranks candidates by expected impact, implementation complexity, implementation friction, and viable bug-fix priority, then recommends the next task plus the natural next action for that task. It helps a user decide what to work on next without changing task files.
</role>

<when_to_activate>
Activate when the user wants backlog selection or prioritization:

- "What task should I work on next?" / "pick the next task" / "choose from the backlog."
- "Rank my open tasks" / "prioritize tasks in this scope."
- "Which task should I check, implement, or refine next?"

Route elsewhere when the user wants to create a task (`task_create` or the base `task` skill), judge one named task's readiness (`task_check`), automatically repair one task until it is ready (`task_auto_check`), implement one chosen task (`task_implement`), verify a completed task (`task_audit`), close a task (`task_finish`), repair the tree (`task_fix`), or list/query tasks without a recommendation (the base `task` skill).
</when_to_activate>

<authority>
The base `task` skill's `SKILL.md` is the source of truth for task discovery, live-vs-archived location, status semantics, filename structure, and query mechanics. Read that skill and follow its `<discover>` step to locate `tasks/`; use its task-file rules as the interpretation layer when reading candidates. Reuse the authority rather than copying the file format here.
</authority>

<path_resolution>
The base `task` skill's `discover_tasks.sh` ships in `scripts/` next to that skill's `SKILL.md`, not next to this one. After reading the base `SKILL.md` (per `<authority>`), resolve the script's absolute path by combining the directory you loaded it from with `scripts/discover_tasks.sh` and invoke that absolute path. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed.
</path_resolution>

<candidate_policy>
Eligible candidates are live task files under `tasks/*.md` whose frontmatter status is `open`, `checked`, or `ready`. Exclude every file under `tasks/archive/`. Exclude live files whose status is `implemented` or `audited`, because their next step is verification or close-out rather than selection for upcoming work.

When the user narrows the scope, filter the eligible set before ranking. Support all of these narrowing forms:

- Scope-group language, such as "task tasks", "api tasks", or "the wiki backlog".
- Filename prefixes or stems, such as `task-skill_`, `api_`, or `tasks/api_rate-limit.md`.
- Frontmatter `scope` matches, including path prefixes and quoted labels.
- Explicit task names or paths.

When no eligible task remains after discovery or filtering, report the no-candidate state plainly and stop. Do not recommend archived, implemented, or audited work as a fallback candidate.
</candidate_policy>

<scoring_criteria>
Use the candidate's full task body as the evidence base before scoring it. Read every candidate in full; do not rank from filenames, status, age, or one-line descriptions alone.

<criterion>
Impact measures how valuable the stated outcome is to the project, users, maintainers, or the task-family workflow. Higher impact tasks unlock important workflows, remove meaningful defects, reduce repeated toil, or clarify a heavily used surface.
</criterion>

<criterion>
Implementation complexity measures the likely amount of code, documentation, metadata, testing, and cross-surface coordination required. Lower complexity is favored when impact is similar.
</criterion>

<criterion>
Implementation friction measures how likely the work is to stall because context is missing, decisions are unresolved, external systems are needed, the blast radius is broad, or verification is difficult. Lower friction is favored when impact is similar.
</criterion>

<criterion>
Dependency and ordering relationships measure how candidate tasks sequence with each other inside the live eligible backlog. Read prerequisites and classify each tie using the base `task` skill's `<dependency_signals>` taxonomy — the prerequisite rule, the relationship signals, the bidirectional outbound/inbound reading, and the hard-ordering-dependency versus soft-companion-relationship split with its directional-evidence rule all live there. Applied to ranking: a hard ordering dependency sequences the prerequisite ahead of its dependent, while a soft companion relationship is surfaced in the report without reordering the candidates.
</criterion>

<criterion>
Bug-fix preference promotes tasks that fix broken, incorrect, confusing, or misleading behavior when they are viable: a viable bug task has clear enough context, reasonable complexity, and manageable verification. Rank a viable bug fix ahead of non-bug work with similar impact.
</criterion>
</scoring_criteria>

<ranking_method>
Rank for practical next-action value: prefer the highest impact task that remains reasonably low in complexity and friction, with the bug-fix preference applied among comparable candidates. Treat a high-impact task with unresolved decisions or difficult verification as a weaker immediate recommendation than a slightly lower-impact task that can move cleanly now.

Apply hard ordering dependencies as a sequencing constraint on top of the standalone scoring. Among candidates linked by a hard ordering dependency, rank the prerequisite ahead of its dependent regardless of relative impact, and give the dependent as the single top recommendation only after its live eligible prerequisites are no longer candidates. Report soft companion relationships without reordering the candidates.

Apply scope narrowing to the recommendation set while retaining the full live eligible set for dependency lookup. When a filtered candidate depends on a live eligible prerequisite outside the filter, treat the filtered candidate as blocked from being recommended as an unblocked implementation task and name the outside-scope prerequisite as the required next work. When every filtered candidate is blocked by outside-scope prerequisites, report that there is no unblocked recommendation inside the filter.

Use status to select the next action after ranking:

- `ready` naturally points to `task_implement`.
- `open` naturally points to `task_check` when the body appears complete enough for a readiness gate, or to refinement through the base `task` skill when the task is visibly under-specified.
- `checked` naturally points to applying the existing check findings when they are present in context, or rerunning `task_check` when the findings are unavailable or stale.
</ranking_method>

<workflow>
1. **Discover.** Read the base `task` skill and run its `<discover>` step using the resolved absolute `discover_tasks.sh` path.
2. **Collect eligible files.** List live task files in `tasks/*.md`, exclude `tasks/archive/`, and drop live files whose frontmatter status is `implemented` or `audited`.
3. **Apply narrowing.** When the user supplied a scope, prefix, label, or task name, filter the eligible set before ranking using the forms in `<candidate_policy>`.
4. **Handle empty sets.** If discovery or filtering leaves no eligible candidates, report that state and stop without recommending archived work.
5. **Read candidates.** Read each remaining task file in full, including frontmatter, Goal, Context, Approach, and Acceptance.
6. **Derive dependency and ordering relationships.** Apply the base `task` skill's `<dependency_signals>` taxonomy in both directions. Read each filtered candidate's own outbound signals, and also scan the full live eligible set for inbound ordering declarations that point at any candidate — a live task whose body names a first-ship order over a candidate or forward-references an artefact the candidate creates. Honor such an ordering note whether it was authored in the candidate or in the pointing task, including when the pointing task sits outside the applied scope filter. Then classify hard ordering dependencies and soft companion relationships before scoring and ranking.
7. **Score and rank.** Evaluate impact, implementation complexity, implementation friction, dependency and ordering relationships, and bug-fix preference from the task body and available repo context. Keep the reasoning compact and evidence-based.
8. **Recommend the next action.** Name the best unblocked candidate first, state the suggested next action for its current status, then list top alternatives and the tradeoff that kept them behind the recommendation. In the all-blocked filtered case, name the outside-scope prerequisite that should be handled next instead of presenting a blocked filtered task as the recommendation.
</workflow>

<output_contract>
Return a recommendation report, not edits:

- Start with `# Recommendation`.
- Name exactly one unblocked recommended task first, using its relative path. In the all-blocked filtered case, state that there is no unblocked recommendation inside the filter and name the outside-scope prerequisite that is the required next work.
- State the suggested next action for the recommended task (`task_check`, `task_implement`, or applying check findings/refinement), or for the outside-scope prerequisite in the all-blocked filtered case.
- Include a compact reason that covers impact, complexity, friction, and bug-fix priority.
- Name ordering relationships that bear on the recommendation: the recommended task being a prerequisite for other candidates, a higher-scoring candidate held back because it is blocked, or an outside-scope prerequisite blocking an otherwise recommendable filtered candidate.
- Surface soft companion relationships that are relevant to the ranked set without presenting them as forced order.
- Add `## Alternatives` with the next strongest candidates and the main tradeoff for each.
- Add `## Method` summarizing the candidate count, any scope filter applied, and the eligibility rule used.

Make no file edits, status changes, timestamp changes, or archive moves.
</output_contract>

<family>
The `task_*` family — each sibling does one job, then points to the next; the base `task` skill is the hub that can do all of it:

- `task_create` — write one task file
- `task_check` — readiness gate before building (read-only)
- `task_auto_check` — autonomously repair one task until `task_check` reports ready
- `task_explain` — explain one task at a high level (read-only)
- `task_select` — choose and rank the next eligible task/action (read-only) **(this skill)**
- `task_implement` — do the work
- `task_audit` — verify a believed-done task against the codebase (read-only)
- `task_finish` — close out: set status, bump `updated`, archive
- `task_fix` — audit and repair the whole tasks tree

These ship together as a family; any sibling may be absent if a deployment excluded it. The default manual chain is create → check → implement → audit → finish, with `task_auto_check` as an opt-in readiness repair loop, `task_select` a read-only chooser for what to work on next, and `task_fix` maintaining the tree.
</family>

</task_select_skill>
