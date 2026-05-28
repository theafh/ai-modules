---
name: task_audit
description: Verify one task's claimed completion against the actual codebase — confirm every body item, acceptance check, and backing test, run the suite, and report a verdict (clean, or gaps with fixes). Read-only: it makes no change. Use when a task is believed done and you want it checked before closing, or to re-check an archived task for drift. For readiness before building use task_check; for doing the work use task_implement; for closing use task_finish.
version: 1.0.0
author: Andreas F. Hoffmann
license: MIT
---

# task_audit

<task_audit_skill>

<role>
task_audit verifies whether a task's *claimed* completion is *real*, by checking the codebase rather than the prose. It reads one task, reads the actual implemented code and tests, walks every body item and `## Acceptance` check, runs the suite the task names, and reports a verdict — clean, or a list of gaps with fixes. It is a **read-only gate**: it makes no state change. It answers "is this task genuinely done?"; `task_finish` answers "now close it." On a clean pass it hands the close-out to `task_finish`; on gaps it hands the remaining work to `task_implement`.
</role>

<when_to_activate>
Activate when the user wants a task's done-ness checked against reality:

- "Is `<task>` actually done?" / "audit this task" / "verify the work is really implemented."
- "Check `<task>` against the code before I close it."
- "Re-check this archived task — did the codebase drift from it?"

Audit only a task whose work is *claimed complete* — a believed-done task being closed, or an archived `implemented` task re-checked for drift. Decline a task whose body is still a plan.

Route elsewhere when the user wants to assess a task's readiness *before* building (`task_check`), do the implementation work (`task_implement`), close and archive a task (`task_finish`), or audit the whole tree's lint health (`task_health`).
</when_to_activate>

<authority>
The base `task` skill's `SKILL.md` is the source of truth for the task-file shape; read it and use its `<discover>` step to locate `tasks/` and its `<file_format>` / `<body>` sections to read the task under audit. The task being audited names its own checks in `## Acceptance`, and the repo's suite (`make lint`, the bundled `lint.py`, the matching `tests/<skill>/script_tests`) is the verification surface — run what the task and repo name.
</authority>

<workflow>
Run in order, read-only throughout — make no edit to the task or the code.

1. **Read the task end-to-end.** Understand the desired behaviour, the `## Approach`, the scope / non-goals, and every `## Acceptance` item. This is the contract you audit against.
2. **Understand what is actually built.** Read the implemented code and the existing tests around the work to establish what is really in place — not what the task claims.
3. **Verify each item against the code.** Walk every body item and every `## Acceptance` check and confirm the codebase covers it. Trust the code, not the prose.
4. **Audit the tests as first-class.** Confirm every acceptance check that names or implies a test has a corresponding, *passing* test. A missing or incomplete test is a gap, audited with the same rigour as the feature work — not waved through.
5. **Run the suite and attribute every failure.** Execute the verifications the task and repo name, recording each failure or warning as evidence. Attribute honestly: a failure your audited work would cause is a gap; a pre-existing failure unrelated to this task is context, named as such rather than counted against the task.
</workflow>

<output_contract>
Report a verdict, evidence-based — never on prose alone.

- On full compliance, output exactly: `Success: full task compliance confirmed.`
- Otherwise output `Gaps:` followed by a numbered list. For each gap give **requirement / expected behaviour / actual behaviour / minimum fix**, ordered by mismatch size (largest coverage or behaviour gap first).

Make no state change. On a clean pass, point at `task_finish` to perform the close-out. On gaps, hand the remaining work to `task_implement`. Surface any pre-existing, unrelated failure as context separate from the gap list.
</output_contract>

<family>
The `task_*` family — each sibling does one job, then points to the next; the base `task` skill is the hub that can do all of it:

- `task_create` — write one task file
- `task_check` — readiness gate before building (read-only)
- `task_implement` — do the work
- `task_audit` — verify a believed-done task against the codebase (read-only) **(this skill)**
- `task_finish` — close out: set status, bump `updated`, archive
- `task_health` — audit and repair the whole tasks tree

These ship together as a family; any sibling may be absent if a deployment excluded it. The natural chain is create → check → implement → audit → finish, with health maintaining the tree.
</family>

</task_audit_skill>
