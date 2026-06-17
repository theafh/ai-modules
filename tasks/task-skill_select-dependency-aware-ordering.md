---
description: Extend task_select to detect dependency and ordering relationships between candidate tasks and rank prerequisites ahead of the tasks that need them, so it never recommends a blocked task first.
scope: plugins/ai_dev/skills/task_select
created: 2026-06-17T23:08:20
updated: 2026-06-17T23:47:23
status: ready
reported-by: Andreas Hoffmann
---

# Make task_select dependency-aware when ranking

## Goal

Extend the `task_select` skill so its ranking and recommendation account for dependency and ordering relationships **between** candidate tasks, not just each task's standalone merit. The user-visible outcome: when one eligible task must be done before another, `task_select` ranks the prerequisite ahead of its dependent, recommends an unblocked task as the top pick, and names the ordering relationship in its report so the user sees the build order. The skill stays read-only — this changes how it ranks and what it reports, never whether it edits files.

## Context

The skill lives at `plugins/ai_dev/skills/task_select/SKILL.md`. Today its `<scoring_criteria>` scores each candidate in isolation on four dimensions — impact, implementation complexity, implementation friction, and bug-fix preference — and `<ranking_method>` prefers the highest-impact candidate that stays low in complexity and friction, with the bug-fix preference applied among comparable candidates. None of these dimensions looks at how one candidate relates to another, so the recommendation can place a task ahead of the very task it depends on.

That gap surfaces whenever a backlog holds several not-yet-implemented tasks that touch overlapping ground. A representative case: a set of open tasks where the question "can these be picked one after another, or do they need ordering first?" only resolved after reconstructing an ordering graph by hand:

- two tasks were mutual companions whose acceptance each forward-referenced a block the other task creates;
- one task was a predecessor of another because the second's edit had to point at text the first changes;
- one task was gated behind another because both rewrite the same files, so building them out of order forces re-work.

The correct order had to be worked out manually. `task_select`, asked which task to do next, would have ranked purely on impact and friction and could have recommended a blocked task first.

The signals needed to detect these relationships already live in the task data, so this stays a read-only inference rather than a new data field:

- **Explicit relationship prose** in a candidate's body — "depends on", "blocked by", "must follow", "after", or a companion reference naming another task file.
- **Cross-links that mark a dependency.** The base `task` skill's `<markdown_policy>` (in `plugins/ai_dev/skills/task/SKILL.md`) already defines a task-to-task link as marking a dependency: "this task builds on, extends, or must follow the other." A candidate that links another live candidate that way is a sequencing signal.
- **Forward references** to a block, section, rule, or artefact that another candidate is the one to create.
- **Shared-surface collisions** — two candidates that edit the same file or surface, where building them out of order forces re-work.

Distinguish the new criterion from the existing friction dimension to keep `<scoring_criteria>` internally consistent: friction's "external systems are needed" is about a single task stalling on something **outside** the backlog; this task is about ordering relationships **among the candidate tasks themselves**. A prerequisite is a live, eligible candidate that is not yet done — a relationship to an already-`implemented`, `audited`, or archived task is satisfied and imposes no ordering.

Scope narrowing defines the recommendation set, not the whole relationship universe. `task_select` still filters candidates before ranking according to `<candidate_policy>`, while retaining the full live eligible set for dependency lookup. A live prerequisite outside the user's filter does not become an ordinary ranked alternative, but it does block the filtered dependent from being presented as the single top implementation recommendation. If every filtered candidate is blocked by an outside-scope prerequisite, the report says there is no unblocked recommendation inside the filter and names the outside-scope prerequisite as the required next work.

The archived [task that introduced `task_select`](archive/task-skill_select-sibling-skill.md) established the four-dimension rubric this task extends.

## Approach

Edit `plugins/ai_dev/skills/task_select/SKILL.md` only, in positive, action-oriented language and the file's existing pseudo-XML structure:

1. **Add a dependency-and-ordering criterion** to `<scoring_criteria>` that names the relationship signals from `## Context` (explicit relationship prose, dependency cross-links, forward references, shared-surface collisions) and defines a prerequisite as a live, eligible candidate that is not yet done. Have it separate two relationship strengths:
   - a **hard ordering dependency** — a forward reference to an artefact another candidate creates, explicit prose naming the required order, or a shared-surface collision with directional evidence that one task creates, renames, removes, or rewrites a specific block, symbol, rule, or file state that the other task consumes — which sets a required build order;
   - a **soft companion relationship** — a coherence or cross-reference tie, or a shared-surface overlap without directional evidence, which carries no required order but is still worth surfacing.
2. **Make `<ranking_method>` apply ordering as a sequencing constraint on top of the existing scoring**, not as another additive score: among candidates linked by a hard ordering dependency, the prerequisite ranks ahead of its dependent regardless of their relative impact, and a candidate still blocked by a live prerequisite is never the single recommended top pick while that prerequisite is itself eligible. State once that soft companion relationships are reported but do not reorder.
3. **State the scope-filter interaction in `<ranking_method>`**: rank only the filtered recommendation set, use the full live eligible set to detect prerequisites, block a filtered dependent when its live prerequisite is outside the filter, and report "no unblocked recommendation inside the filter" when every filtered candidate is blocked by such an outside-scope prerequisite.
4. **Add a `<workflow>` step**, after the filtered candidates are read, that checks their links, relationship prose, forward references, and shared surfaces against the full live eligible set, then derives dependency-and-ordering relationships before scoring and ranking.
5. **Extend `<output_contract>`** so the report names any ordering relationship bearing on the recommendation: when the recommended task is a prerequisite of others, when a stronger-scoring candidate was held back because it is blocked, and when an outside-scope prerequisite blocks an otherwise recommendable filtered candidate. Make the contract normally name one unblocked recommendation first, while allowing the all-blocked filtered case from `<ranking_method>` to report that there is no unblocked recommendation inside the filter and to name the outside-scope prerequisite as the required next work. Keep the existing read-only clause intact.

Non-goals: do not add a dependency field to the task-file frontmatter or otherwise change the base `task` skill's file format — the relationships are inferred from existing content. Do not add scripts or new tooling; this is a prose edit to one skill. Do not change the eligibility rule in `<candidate_policy>`.

## Acceptance

- `plugins/ai_dev/skills/task_select/SKILL.md` `<scoring_criteria>` carries a dependency-and-ordering criterion that enumerates the relationship signals (explicit relationship prose, dependency cross-links, forward references, shared-surface collisions), defines a prerequisite as a live eligible candidate that is not yet done, and separates hard ordering dependencies from soft companion relationships.
- `<scoring_criteria>` or `<ranking_method>` defines directional evidence for shared-surface collisions: shared files become hard ordering dependencies only when one task creates, renames, removes, or rewrites a specific block, symbol, rule, or file state that the other task consumes; directionless overlap is surfaced as a soft companion relationship.
- `<ranking_method>` states that a prerequisite ranks ahead of its dependent under a hard ordering dependency irrespective of relative impact, and that a candidate blocked by a live eligible prerequisite is not given as the single top recommendation; it states that soft companion relationships are surfaced without reordering.
- `<ranking_method>` states that scope narrowing filters the recommendation set while the full live eligible set remains available for dependency lookup; an outside-scope live prerequisite blocks the filtered dependent from being recommended as an unblocked implementation task, and an all-blocked filtered set is reported as having no unblocked recommendation inside the filter.
- `<workflow>` includes a step that derives inter-candidate dependency-and-ordering relationships after filtered candidates are read and before ranking, checking relationship signals against the full live eligible set where needed.
- `<output_contract>` requires the report to name the ordering relationships bearing on the recommendation — the recommended task being a prerequisite, a higher-scoring candidate held back as blocked, and an outside-scope prerequisite blocking an otherwise recommendable filtered candidate — while keeping the read-only "make no file edits" clause.
- `<output_contract>` normally requires one unblocked recommendation first, but in the all-blocked filtered case it reports that there is no unblocked recommendation inside the filter and names the outside-scope prerequisite as the required next work, so the output contract stays consistent with `<ranking_method>`.
- Running the revised skill against a staged fixture of two eligible candidates where task B's body forward-references a block task A creates yields a recommendation that names A first, ranks A ahead of B, and reports the A-before-B ordering; running it against two file-disjoint companion candidates surfaces the relationship without forcing an order between them.
- The skill performs no file edits, status changes, timestamp changes, or archive moves while producing the dependency-aware recommendation.
