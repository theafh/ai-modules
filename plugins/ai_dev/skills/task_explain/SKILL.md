---
name: task_explain
description: Explain one project task in compact what/why/how prose without editing it. Use when the user asks to explain, summarize, walk through, or orient on a task file by path, partial name, or conversation context. If the task reference is missing or ambiguous, activate and ask which task to explain. Not for readiness, next-work selection, implementation, audit, finish, or repair.
version: 1.0.3
author: Andreas F. Hoffmann
license: MIT
---

# task_explain

<task_explain_skill>

<role>
task_explain is the read-only orientation helper for one project task file. It explains the task's intent and plan at a high level - what the task is about, why it is being done, and how it is meant to be achieved - so a reader can orient without reading the whole file. It is a thin front end over the base `task` skill: the base skill remains the authority for task discovery and file-format meaning, while task_explain owns only the explanation behavior. It explains intent and plan; it does not judge readiness, recommend next work, verify completion, or change task files.
</role>

<when_to_activate>
Activate when the user wants an explanation of exactly one task:

- "Explain this task."
- "What is this task about?"
- "Give me a high-level / compact description of this task."
- "What's the goal / why / how of `<task>`?"
- "Summarize this task."
- "Walk me through `<task>`."

Route to `task_check` when the user asks whether the task is ready to build. Route to `task_select` when the user asks what to work on next. Route to `task_audit` when the user asks whether completed work is genuinely done. Route to the base `task` skill, `task_create`, `task_auto_check`, `task_implement`, `task_finish`, or `task_fix` when the user asks for edits, status changes, implementation, close-out, or tree repair.
</when_to_activate>

<authority>
The base `task` skill's `SKILL.md` is the source of truth for shared task mechanics. Read that skill and apply:

- `<discover>` - locate the project `tasks/` directory.
- `<file_format>` - interpret task filenames, frontmatter, statuses, live-vs-archived location, and body sections.
- `<body>` - read Goal, Context, Approach, and Acceptance as the source material for the explanation.

Keep shared file-format and backlog-management rules in the base skill. This skill adds only the read-only explanation contract.
</authority>

<path_resolution>
The base `task` skill's `discover_tasks.sh` ships in `scripts/` next to that skill's `SKILL.md`, not next to this one. After reading the base `SKILL.md` per `<authority>`, resolve the script's absolute path by combining the directory you loaded it from with `scripts/discover_tasks.sh` and invoke that absolute path. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed.
</path_resolution>

<target_resolution>
Resolve exactly one task file before explaining it. Accept an explicit path, an exact filename or stem, a partial name, an H1 title, or "this task" from the current conversation context. Match across both live tasks under `tasks/*.md` and closed tasks under `tasks/archive/*.md`; explaining an archived task is in scope because orientation applies to closed work too.

When no file matches, report the unresolved reference and ask for a task path or name. When more than one file matches, list the candidate paths with their current status and ask one sharp disambiguating question before explaining. Do not choose among ambiguous candidates silently.
</target_resolution>

<workflow>
1. **Discover.** Read the base `task` skill and run its `<discover>` step using the resolved absolute `discover_tasks.sh` path.
2. **Resolve the target.** Use `<target_resolution>` to find exactly one task across `tasks/` and `tasks/archive/`.
3. **Read the task fully.** Read frontmatter, title, Goal, Context, Approach, Acceptance, and task-local links before synthesizing. Do not explain from filename, status, or description alone.
4. **Extract the orienting frame.** Capture the relative path, status, scope, short title or description, and any load-bearing dependencies or cross-linked tasks that change how the task should be understood.
5. **Synthesize the explanation.** Explain the task at altitude across the three beats: what it delivers, why it exists, and how the approach achieves it. Use the file's content as evidence, but synthesize rather than reproducing the task's sections verbatim.
6. **Return the readout.** Follow `<output_contract>` and preserve `<read_only_guarantee>`.
</workflow>

<output_contract>
Return a compact explanation, not a readiness verdict, recommendation, audit, or edit report:

- Lead with the bottom line in one short paragraph.
- Include an orienting frame naming the task path, status, scope, and any load-bearing dependencies or cross-linked tasks when present.
- Organize the core explanation along the three beats: **What**, **Why**, and **How**.
- Explain in flowing prose at a high level. Preserve the task's meaning while avoiding section-by-section echoing, long quotations, or implementation-level detail that the user did not ask for.
- On ambiguity, list candidate task paths and ask one disambiguating question instead of explaining a guessed target.
</output_contract>

<read_only_guarantee>
Make no file edits, status changes, timestamp changes, lint or fix mutations, or archive moves. Reading a task to explain it leaves the task body, frontmatter, bytes, status, timestamps, and location unchanged.
</read_only_guarantee>

<family>
The `task_*` family - each sibling does one job, then points to the next; the base `task` skill is the hub that can do all of it:

- `task_create` - write one task file
- `task_check` - readiness gate before building (read-only)
- `task_auto_check` - autonomously repair one task until `task_check` reports ready
- `task_explain` - explain one task at a high level (read-only) **(this skill)**
- `task_select` - choose and rank the next eligible task/action (read-only)
- `task_implement` - do the work
- `task_audit` - verify a believed-done task against the codebase (read-only)
- `task_finish` - close out: set status, bump `updated`, archive
- `task_fix` - audit and repair the whole tasks tree

These ship together as a family; any sibling may be absent if a deployment excluded it. The default manual chain is create → check → implement → audit → finish, with `task_auto_check` as an opt-in readiness repair loop, `task_select` a read-only chooser for what to work on next, and `task_fix` maintaining the tree.
</family>

</task_explain_skill>
