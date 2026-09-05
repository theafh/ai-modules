---
name: task_check
description: Check one task before implementation. Use when the user asks if a task is ready to build or still valid. Assess structure, scope, focus, complexity, contradictions, and ambiguity, verify the task's premise and described current state against the codebase, surface a stale invalidated task with deferral as the user's option, then stamp ready or checked and report readiness issues.
version: 1.1.11
author: Andreas F. Hoffmann
license: MIT
---

# task_check

<task_check_skill>

<role>
task_check assesses whether a single task file is ready to hand to `task_implement`. It reads one task and produces a direct readiness verdict against a checklist covering structure, scope sizing, focus, complexity, and freedom from contradiction and ambiguity, surfacing every issue that would lead a one-shot implementer to a wrong or divergent result. It is the pre-implementation gate the base skill's single-shot-ready body design implies. It changes only the lifecycle stamp: `ready` on a clean verdict, `checked` when blocking issues remain, plus `updated`; it moves no file and changes no body content or other frontmatter.
</role>

<when_to_activate>
Activate when the user wants a single task's readiness judged before building:

- "Is `<task>` ready?" / "check this task before I build it" / "assess this task's readiness."
- "Will a one-shot implementer get this right?"

Route elsewhere when the user wants to write a task (`task_create` or the base `task` skill), automatically repair a task until this gate reports ready (`task_auto_check`), choose what to work on next (`task_select`), do the implementation work (`task_implement`), verify a believed-done task against the codebase (`task_audit`), close a task (`task_finish`), or health-check the whole tree (`task_fix`). The crisp line: task_check judges *one task's readiness before building*; `task_auto_check` is the opt-in loop that edits the task and reuses this gate; `task_select` ranks eligible backlog candidates; `task_audit` verifies *one task's claimed completion after building*.
</when_to_activate>

<authority>
The base `task` skill's `SKILL.md` is the source of truth for the task-file shape; read it and use its `<discover>` step to locate `tasks/`, its `<readiness_checklist>` as the lens you assess with, its `<backward_move_guard>` before stamping, and its `<file_format>` / `<body>` / `<one_task_per_file>` / `<split_at_300>` rules as the structural bar behind that lens. Assess the task and limit mutation to the status/`updated` stamp.
</authority>

<path_resolution>
The base `task` skill's `discover_tasks.sh` ships in `scripts/` next to that skill's `SKILL.md`, not next to this one. After reading the base `SKILL.md` (per `<authority>`), resolve the script's absolute path by combining the directory you loaded it from with `scripts/<script-name>` and invoke that absolute path, never a bare `scripts/...`, which resolves against the current working directory (the target project) rather than the skill. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed.
</path_resolution>

<assessment>
The bar is the base skill's self-sufficiency concept: the task file on its own is enough to produce a full implementation in a single pass, and the implementer draws on everything actually available, including the codebase, the project's standing instructions (`CLAUDE.md` / `AGENTS.md` and equivalents), and the user. Judge the task the way it is consumed: a task that leans on a standing project instruction is correctly authored when it cites the rule, and flagging the absence of content a standing instruction already owns is a false positive. Evaluate every issue against that bar.

Assess against the base `task` skill's `<readiness_checklist>`, in its order: the charter and structural checks, then the premise, approach-fitness, and **Interaction scan** checks against the codebase, then the content lens item by item. The checklist lives once in the base skill as the family's single source; apply it from there rather than from a copy here. Every verified checklist finding is a readiness issue and belongs in `## Issues`; do not demote a checklist finding to style notes because the implementation could still proceed around it.

Ground every issue before reporting it: an issue enters the report only after you have confirmed it against the repository by reading the file it implicates, running the command the acceptance names, and checking the policy the task cites. An unverifiable suspicion is voiced as a question in the general assessment, never as a numbered issue.

When the **Ambiguity / under-specification** lens surfaces an open decision, apply the base skill's **Decide or label** reconciliation rule against its evidence base: when that evidence settles the decision, report the reconciled resolution as the issue's minimum fix; when it does not, surface the decision in the issue with its options and at least one suggested path for the user. Either way task_check stays read-only: it recommends and surfaces, leaving writing the reconciled decision to the editing siblings and the user's apply-findings edit, so the status/`updated` stamp remains its only mutation.

When the premise check returns its invalidated outcome, state that plainly in the general assessment and surface the base rule's disposition options as the user's decision to make: close as `deferred` through `task_finish`, re-scope the intent, or refute the finding with evidence. The status stamp stays this skill's only mutation either way.

When the base checklist's **Interaction scan** lens confirms a contradiction or an unattended interaction, report it as a readiness issue carrying its code evidence, the written juxtaposition of the interacting code against the task's change. Apply the base **Decide or label** rule: recommend the reconciled fix as the issue's resolution when the found code settles it, or surface the interaction with its options and at least one suggested path when it does not. task_check stays read-only either way. It recommends and surfaces and writes no task body content, so the status/`updated` stamp remains its only mutation.

After assessing, stamp the outcome only: `status: ready` for a clean implementation-ready verdict, otherwise `status: checked`, honoring the base skill's `<backward_move_guard>`, and bump `updated`. Preserve the task body, all other frontmatter fields, and the file path.
</assessment>

<output_contract>
Structure the report in exactly this shape:

- Lead with a `# General assessment` paragraph: one short paragraph stating whether the task is ready to build and why.
- Then a `## Issues` section carrying verified implementation-divergence issues exclusively. When clean, output exactly `No issues found.` Otherwise list every verified issue as a single ordered list, ranked by how likely each is to cause a wrong or divergent one-shot implementation, most problematic first. Each entry: `**[short title]**: where it sits, what is wrong, the implementation impact, and the minimum fix.` Locate each issue by label or unambiguous description, such as the section heading, the pseudo-XML tag, or a quoted phrase, per the base skill's soft-pointer rule.
- After the list, add a short unnumbered **Style notes** tail only for non-checklist wording polish; omit the tail when there are none.

Include every verified issue regardless of size. Make only the status/`updated` stamp and move no file, because acting on the findings is `task_create`/editing, and building is `task_implement`.
</output_contract>

<family>
The `task_*` family, where each sibling does one job then points to the next, and the base `task` skill is the hub that can do all of it:

- `task_create`: write one task file
- `task_check`: readiness gate before building (read-only) **(this skill)**
- `task_auto_check`: autonomously repair one task until `task_check` reports ready
- `task_explain`: explain one task at a high level (read-only)
- `task_select`: choose and rank the next eligible task/action (read-only)
- `task_implement`: do the work
- `task_audit`: verify a believed-done task against the codebase (read-only)
- `task_finish`: close out (set status, bump `updated`, archive)
- `task_fix`: audit and repair the whole tasks tree

These ship together as a family; any sibling may be absent if a deployment excluded it. The default manual chain is create → check → implement → audit → finish, with `task_auto_check` as an opt-in readiness repair loop, `task_select` a read-only chooser for what to work on next, and `task_fix` maintaining the tree.
</family>

</task_check_skill>
