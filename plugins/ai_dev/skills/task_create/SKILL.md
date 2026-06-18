---
name: task_create
description: Create exactly one new task file for one upcoming work item. Use when the user asks to make, add, file, write, or capture a single task or todo. Use task for listing, querying, updating, archiving, linting, or multi task backlog work.
version: 1.1.3
author: Andreas F. Hoffmann
license: MIT
---

# task_create

<task_create_skill>

<role>
task_create is the focused on-ramp for adding a single item to the project's `tasks/` backlog. Its one job is to turn a single request into one conformant, lint-clean task file with no surrounding workflow. It is a thin, trigger-precise front end over the `task` skill: the `task` skill stays the authority for the file format and the create mechanics, and task_create lets a one-shot "make a task for X" load a narrow surface instead of the whole backlog-management skill.
</role>

<when_to_activate>
Activate when the user wants exactly one task file written:

- "Make / create / add / file / write a task (or todo) for X."
- "Capture this as a task" about a single piece of upcoming work.
- A single follow-up item that surfaced mid-conversation and should persist as one task file.

Route to the `task` skill instead when the user wants to list, query, update, refine, finish, implement, defer, archive, or lint tasks, or to derive several tasks from a larger document in one pass — those are the broader backlog workflows. Route to `task_select` when the user wants a recommendation about what backlog item to work on next.
</when_to_activate>

<authority>
The `task` skill's `SKILL.md` is the single source of truth; keep every shared rule there and follow it rather than copying it. Read that skill and apply:

- `<file_format>` — `<naming>`, `<frontmatter>` (including the `date`-stamped `created` / `updated`), `<markdown_policy>`, and the `<body>` sections.
- `<discover>` — locate or scaffold `tasks/` through the bundled `discover_tasks.sh` / `init_tasks.sh`.
- `<create>`'s `<prior_art>` — the two-tier duplicate / already-done gate run before writing.
- `<create>`'s `<lossless_conversion>` — the source-fidelity contract that fires whenever a task is derived from source material. This single-task on-ramp *is* the single-task-from-a-source path that contract names, so apply it verbatim from the base skill rather than restating it here, keeping the two in step.
- `<readiness_checklist>` — the lens the drafted body is self-checked against before the file is written.
- `<lint>` — the bundled `lint.py` and what each finding means.

These assets ship in the same plugin as task_create, so they are present wherever task_create is.
</authority>

<path_resolution>
The bundled scripts (`discover_tasks.sh`, `init_tasks.sh`, `lint.py`) ship in `scripts/` next to the base `task` skill's `SKILL.md`, not next to this one. After reading that base `SKILL.md` (per `<authority>`), resolve each script's absolute path by combining the directory you loaded it from with `scripts/<script-name>` and invoke that absolute path — never a bare `scripts/...`, which resolves against the current working directory (the target project) rather than the skill, and so finds the project's own `scripts/` or nothing. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed.
</path_resolution>

<workflow>
Create one file, in order:

1. **Discover.** Run the `task` skill's `<discover>` step to resolve `tasks/`, scaffolding it when it is missing.
2. **Gather.** Confirm the single item to capture and collect enough context to fill the `<body>` sections to the base skill's self-sufficiency bar: the file on its own is enough to implement, with everything actually available at implementation time — the codebase, the project's standing instructions, the user — staying in play. When the context is too thin for that, ask one sharp clarifying question, then proceed.
3. **Prior-art gate.** Run the `task` skill's `<prior_art>` step: a fast `rg` scan of `tasks/` + `tasks/archive/` that escalates to an in-depth project analysis only when the scan hits. When a match shows the work is already an open task, partially covered, already implemented, or already deferred, surface it with evidence and let the user decide how to proceed before writing — never auto-resolve.
4. **Scope and name.** Pick a `<scope>` from the groupings already present in `tasks/`, and a compact `<name>` that is unique across both `tasks/` and `tasks/archive/`. List both directories once to keep the name collision-free.
5. **Timestamp.** Run `date +%Y-%m-%dT%H:%M:%S` once and use its output verbatim for both `created` and `updated`.
6. **Self-check the draft.** Judge the drafted body against the `task` skill's `<readiness_checklist>` and resolve every finding before writing, so the file written already passes the lens `task_check` will apply.
7. **Write.** Create `<tasks>/<scope>_<name>.md` with `status: open` and `reported-by` resolved via the base skill's `<user_name_chain>`, then write a body that opens with a single `# Title` and fills Goal / Context / Approach / Acceptance per the `task` skill's `<body>`. When filling `## Context` and any cross-references, apply the cross-link discipline and the soft-pointer rule from the `task` skill's `<markdown_policy>`, so each link to another task earns its place and each pointer to file content survives edits to its target.
8. **Lint.** Run the linter per the `task` skill's `<lint>` step (`lint.py --quiet`) and resolve every blocking finding before reporting the file as created.

When this one task is derived from source material — a pasted note, a chat turn, a `todo.md`, a PDF, any pre-existing body of meaning — apply the `task` skill's `<lossless_conversion>` contract on your own before reporting done: confirm the single task carries every relevant unit of meaning from that source, propagate source-wide content into it, and leave the source's keep/drop disposition to the user. A single task does not exempt the check — one source can hold more meaning than it captures.

Keep this to one atomic task file. When the request actually carries several independent items, or a single item would run past 300 lines, hand the multi-task split to the `task` skill rather than expanding the work here. A request that fits the base skill's **Scope sizing** rule stays eligible for this single-file path even when it touches multiple related parts.
</workflow>

<output_contract>
Report the relative path of the one task file created and confirm the linter came back clean. Surface any assumption you made about scope, name, or body so the user can correct it. When the prior-art gate found a match, report the classification and evidence and reflect the user's decision instead of silently creating a duplicate.
</output_contract>

<family>
The `task_*` family — each sibling does one job, then points to the next; the base `task` skill is the hub that can do all of it:

- `task_create` — write one task file **(this skill)**
- `task_check` — readiness gate before building (read-only)
- `task_select` — choose and rank the next eligible task/action (read-only)
- `task_implement` — do the work
- `task_audit` — verify a believed-done task against the codebase (read-only)
- `task_finish` — close out: set status, bump `updated`, archive
- `task_fix` — audit and repair the whole tasks tree

These ship together as a family; any sibling may be absent if a deployment excluded it. The natural chain is create → check → select → implement → audit → finish, with fix maintaining the tree.
</family>

</task_create_skill>
