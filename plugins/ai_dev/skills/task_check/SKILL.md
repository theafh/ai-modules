---
name: task_check
description: Assess whether one task file in tasks/ is ready to hand to an implementer — judge it against a readiness checklist (structure, scope sizing, focus, complexity, contradictions, ambiguity) and report a General assessment plus a ranked Issues list. Read-only: it judges, it does not edit. Use before building a task. For doing the work use task_implement; for verifying a believed-done task use task_audit; for whole-tree health use task_fix.
version: 1.1.0
author: Andreas F. Hoffmann
license: MIT
---

# task_check

<task_check_skill>

<role>
task_check assesses whether a single task file is ready to hand to `task_implement`. It reads one task and produces a direct readiness verdict against a checklist — structure, scope sizing, focus, complexity, freedom from contradiction and ambiguity — surfacing every issue that would lead a one-shot implementer to a wrong or divergent result. It is the pre-implementation gate the base skill's single-shot-ready body design implies. It is **read-only**: it judges and reports; it makes no edit and moves no file.
</role>

<when_to_activate>
Activate when the user wants a single task's readiness judged before building:

- "Is `<task>` ready?" / "check this task before I build it" / "assess this task's readiness."
- "Will a one-shot implementer get this right?"

Route elsewhere when the user wants to write a task (`task_create` or the base `task` skill), do the implementation work (`task_implement`), verify a believed-done task against the codebase (`task_audit`), close a task (`task_finish`), or health-check the whole tree (`task_fix`). The crisp line: task_check judges *one task's readiness before building*; `task_audit` verifies *one task's claimed completion after building*.
</when_to_activate>

<authority>
The base `task` skill's `SKILL.md` is the source of truth for the task-file shape; read it and use its `<discover>` step to locate `tasks/`, its `<readiness_checklist>` as the lens you assess with, and its `<file_format>` / `<body>` / `<one_task_per_file>` / `<split_at_300>` rules as the structural bar behind that lens. Assess the task — do not edit it.
</authority>

<path_resolution>
The base `task` skill's `discover_tasks.sh` ships in `scripts/` next to that skill's `SKILL.md`, not next to this one. After reading the base `SKILL.md` (per `<authority>`), resolve the script's absolute path by combining the directory you loaded it from with `scripts/<script-name>` and invoke that absolute path — never a bare `scripts/...`, which resolves against the current working directory (the target project) rather than the skill. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed.
</path_resolution>

<assessment>
The bar is the base skill's self-sufficiency concept: the task file on its own is enough to produce a full implementation in a single pass, and the implementer draws on everything actually available — the codebase, the project's standing instructions (`CLAUDE.md` / `AGENTS.md` and equivalents), the user. Judge the task the way it is consumed: a task that leans on a standing project instruction is correctly authored when it cites the rule, and flagging the absence of content a standing instruction already owns is a false positive. Evaluate every issue against that bar.

Assess against the base `task` skill's `<readiness_checklist>`, in its order — the structural check first, then the content lens item by item. The checklist lives once in the base skill as the family's single source; apply it from there rather than from a copy here.

Ground every issue before reporting it: an issue enters the report only after you have confirmed it against the repository — read the file it implicates, run the command the acceptance names, check the policy the task cites. An unverifiable suspicion is voiced as a question in the general assessment, never as a numbered issue.

Stay read-only throughout — assess and report, change nothing.
</assessment>

<output_contract>
Borrow `spec_check`'s shape exactly:

- Lead with a `# General assessment` paragraph: one short paragraph stating whether the task is ready to build and why.
- Then a `## Issues` section carrying verified implementation-divergence issues exclusively. When clean, output exactly `No issues found.` Otherwise list every verified issue as a single ordered list, ranked by how likely each is to cause a wrong or divergent one-shot implementation — most problematic first. Each entry: `**[short title]** — where it sits, what is wrong, the implementation impact, and the minimum fix.` Locate each issue by label or unambiguous description — the section heading, the pseudo-XML tag, a quoted phrase — per the base skill's soft-pointer rule.
- After the list, add a short unnumbered **Style notes** tail for style-level findings — negation framing, wording polish; omit the tail when there are none.

Include every verified issue regardless of size. Make no edit and move no file — acting on the findings is `task_create`/editing, and building is `task_implement`.
</output_contract>

<family>
The `task_*` family — each sibling does one job, then points to the next; the base `task` skill is the hub that can do all of it:

- `task_create` — write one task file
- `task_check` — readiness gate before building (read-only) **(this skill)**
- `task_implement` — do the work
- `task_audit` — verify a believed-done task against the codebase (read-only)
- `task_finish` — close out: set status, bump `updated`, archive
- `task_fix` — audit and repair the whole tasks tree

These ship together as a family; any sibling may be absent if a deployment excluded it. The natural chain is create → check → implement → audit → finish, with fix maintaining the tree.
</family>

</task_check_skill>
