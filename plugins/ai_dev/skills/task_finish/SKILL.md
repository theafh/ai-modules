---
name: task_finish
description: Close one completed or parked task. Use when the user asks to finish, mark done, defer, park, drop, or archive a task. Set finished or deferred, move the file to archive, update links, and relint.
version: 1.0.6
author: Andreas F. Hoffmann
license: MIT
---

# task_finish

<task_finish_skill>

<role>
task_finish closes out a single task in the project's `tasks/` backlog. It performs the close-out action — set `status` to `finished` or `deferred`, bump `updated`, `git mv` the file to `archive/`, re-point the cross-references the move touches, and re-lint to a clean tree. It is the *action* counterpart to `task_audit`, the read-only *gate* that answers "is this genuinely done?". task_finish answers "now close it." It is the skill form of the base `task` skill's `<archive>` workflow, triggerable on its own, and it owns both closure paths: `finished` (done and shipped) and `deferred` (parked or dropped).
</role>

<when_to_activate>
Activate when the user wants one task closed out:

- "Finish this task" / "mark `<task>` done" / "this task is implemented."
- "Defer this" / "park `<task>`" / "drop this for now."
- "Archive this task."

Route elsewhere when the user wants to create a task (`task_create` or the base `task` skill), assess readiness before building (`task_check`), automatically repair readiness issues before building (`task_auto_check`), choose what to work on next (`task_select`), do the implementation work (`task_implement`), verify a believed-done task against the codebase (`task_audit`), or list / query / update tasks (the base `task` skill).
</when_to_activate>

<authority>
The base `task` skill's `SKILL.md` is the single source of truth; keep every shared rule there and follow it rather than copying it. Read that skill and apply its `<discover>` step to locate `tasks/`, its `<archive>` workflow for the five close-out steps, and its `<lint>` step (the bundled `lint.py`) to confirm the result. These assets ship in the same plugin as task_finish, so they are present wherever task_finish is.
</authority>

<path_resolution>
The bundled scripts (`discover_tasks.sh`, `lint.py`) ship in `scripts/` next to the base `task` skill's `SKILL.md`, not next to this one. After reading that base `SKILL.md` (per `<authority>`), resolve each script's absolute path by combining the directory you loaded it from with `scripts/<script-name>` and invoke that absolute path — never a bare `scripts/...`, which resolves against the current working directory (the target project) rather than the skill, and so finds the project's own `scripts/` or nothing. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed.
</path_resolution>

<workflow>
Close one task, in order:

1. **Identify the target task.** Run the base skill's `<discover>` step to resolve `tasks/`, and confirm which single task file is being closed. Read it so you know its current `status`, links, and the work it claims.
2. **Decide the outcome.** Set `finished` when the work is done and shipped, or `deferred` when the task is parked or dropped and not pursued for now. When the user's intent is ambiguous between the two, ask before changing anything.
3. **Verify before a `finished` close.** Marking a task `finished` asserts the work is genuinely done, so confirm that against the codebase first — run `task_audit` (the read-only gate) or carry out its check, and resolve or report any gap before closing. A `deferred` close skips this step, since parking a task makes no claim about completion. Mark a task `finished` on codebase evidence, not on prose.
4. **Run the base skill's `<archive>` close-out.** Follow the `task` skill's `<archive>` workflow end to end — set `status`, bump `updated` from `date`, `git mv` the file to `archive/`, re-point every cross-reference the move touches (outbound links inside the moved file, inbound links from anywhere in the tasks tree — open and archived alike), and re-lint until no blocking finding remains. Those rules live in the base skill; follow them there rather than restating them here.
</workflow>

<output_contract>
Report the task's new path under `archive/`, the `status` you set, the cross-references you re-pointed, and a clean linter result. Surface any assumption you made about the finished-vs-deferred outcome so the user can correct it.
</output_contract>

<family>
The `task_*` family — each sibling does one job, then points to the next; the base `task` skill is the hub that can do all of it:

- `task_create` — write one task file
- `task_check` — readiness gate before building (read-only)
- `task_auto_check` — autonomously repair one task until `task_check` reports ready
- `task_select` — choose and rank the next eligible task/action (read-only)
- `task_implement` — do the work
- `task_audit` — verify a believed-done task against the codebase (read-only)
- `task_finish` — close out: set status, bump `updated`, archive **(this skill)**
- `task_fix` — audit and repair the whole tasks tree

These ship together as a family; any sibling may be absent if a deployment excluded it. The default manual chain is create → check → select → implement → audit → finish, with `task_auto_check` as an opt-in readiness repair loop and fix maintaining the tree.
</family>

</task_finish_skill>
