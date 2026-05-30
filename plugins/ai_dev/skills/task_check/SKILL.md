---
name: task_check
description: Assess whether one task file in tasks/ is ready to hand to an implementer — judge it against a readiness checklist (structure, scope sizing, focus, complexity, contradictions, ambiguity) and report a General assessment plus a ranked Issues list. Read-only: it judges, it does not edit. Use before building a task. For doing the work use task_implement; for verifying a believed-done task use task_audit; for whole-tree health use task_fix.
version: 1.0.1
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
The base `task` skill's `SKILL.md` is the source of truth for the task-file shape; read it and use its `<discover>` step to locate `tasks/` and its `<file_format>` / `<body>` / `<one_task_per_file>` / `<split_at_300>` rules as the structural bar you assess against. Assess the task — do not edit it.
</authority>

<assessment>
The bar: a one-shot AI coder receives this task as its sole input and produces a full implementation in a single pass. Evaluate every issue against that bar.

1. **Structural check first.** Confirm the body opens with a single `# Title` and carries the `## Goal` / `## Context` / `## Approach` / `## Acceptance` sections, with valid frontmatter, per the base skill's `<body>` and `<file_format>`. A one-shot implementer follows structure literally, so a structural gap is high-severity — run this before the content lens.
2. **Content lens.** Read the task thoroughly and surface every issue that could derail a correct, complete one-shot implementation:
   - **Scope sizing** — the most compact scope that still delivers a coherent, independently testable unit. Flag too-large (multi-pass risk, past the 300-line split) and too-small (coordination overhead, no standalone capability).
   - **Focus** — one atomic item. Flag scope creep that belongs in a sibling task and should be cross-linked rather than folded in.
   - **Complexity** — implementable in a single pass. Flag hidden multi-step or cross-cutting work.
   - **Contradictions** — internal consistency, including behavioural contradictions where one part makes another non-functional.
   - **Ambiguity / under-specification** — missing requirements, unstated assumptions, or vague pointers that lead to divergent implementations.
   - **Over-specification** — constraints that needlessly narrow an implementation choice the task meant to leave open.
   - **Negation-framed behaviour** — behaviour defined as "not X" that an implementer must invert to act on; recommend a direct positive statement that preserves the technical detail.

Stay read-only throughout — assess and report, change nothing.
</assessment>

<output_contract>
Borrow `spec_check`'s shape exactly:

- Lead with a `# General assessment` paragraph: one short paragraph stating whether the task is ready to build and why.
- Then a `## Issues` section. When clean, output exactly `No issues found.` Otherwise list every issue as a single ordered list, ranked by how likely each is to cause a wrong or divergent one-shot implementation — most problematic first. Each entry: `**[short title]** — what is wrong, the implementation impact, and the minimum fix.`

Include every issue regardless of size; minor clarity improvements belong at the bottom. Make no edit and move no file — acting on the findings is `task_create`/editing, and building is `task_implement`.
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
