---
name: task_health
description: Audit and repair the whole tasks/ backlog tree in one pass — run the linter, walk every task, auto-fix the mechanical findings (naming, frontmatter, status/location, links, datetimes), and surface judgement calls (splits, drift, cross-task contradictions) for review. Inline, no agent. Use to health-check, clean up, audit, or lint the task backlog. For a single task's readiness use task_check; to verify one believed-done task against the codebase use task_audit.
version: 1.0.0
author: Andreas F. Hoffmann
license: MIT
---

# task_health

<task_health_skill>

<role>
task_health health-checks the whole `tasks/` tree and repairs what it safely can — the task-backlog analogue of `wiki_fix`. It runs a four-phase loop (orient → assess → remediate → verify), auto-fixes the mechanical findings the linter reports, surfaces the judgement calls for human review, and ends with a concise report. It operates on the *whole tree* (distinct from `task_audit`, which verifies *one task* against the codebase, and `task_check`, which judges *one task's* readiness before building).
</role>

<when_to_activate>
Activate when the user wants the task backlog as a whole audited and tidied:

- "Health-check my tasks" / "clean up the backlog" / "audit the task list" / "lint and fix the tasks tree."

Route elsewhere when the user wants to judge a single task's readiness before building (`task_check`), verify one believed-done task against the codebase (`task_audit`), create a task (`task_create`), implement one (`task_implement`), or close one out (`task_finish`).
</when_to_activate>

<design_note>
task_health runs **inline — no dedicated agent.** The `tasks/` tree is small and the fixes are mechanical, so the agent indirection `wiki_fix` → `wiki_auto_shaper` uses for a large wiki is not warranted here, and it would add an agent to maintain plus a read-token cost. A `task_auto_shaper` agent is deferred future work, to revisit only if the tree grows enough that inline iteration strains a single context — and if so, the safe shape is a read-only assess fan-out feeding a single remediation writer, never per-file write agents (they would race on the shared link graph).
</design_note>

<authority>
The base `task` skill's `SKILL.md` is the single source of truth; read it and follow it rather than copying its rules. Its `<discover>` step locates `tasks/`, its bundled `lint.py` is the mechanical oracle (`<lint>`), and its `<archive>` workflow defines a status/location move (set `status`, bump `updated` from `date`, `git mv`, re-point cross-references, re-lint). These assets ship in the same plugin as task_health.
</authority>

<workflow>
Run all four phases in order.

1. **Orient.** Read the base `task` skill's rules once — naming, frontmatter, the `<body>` anatomy, the standard-markdown policy, the 300-line split rule, and the `<lint>` / `<archive>` workflows. These are the bar every fix honors.
2. **Assess.** Resolve `tasks/` via `<discover>`, run `lint.py` over the tree, and bucket its findings (blocking / warn / info). Then walk every task applying the **best-effort advisory** checks the linter can't: *topic mixing* (one file covering two unrelated units of work — flag for a split) and *single-shot-readiness* (a body that no longer reads as something an implementer could act on from the file alone — an empty section, a dangling "TBD", context that assumes the original chat).
3. **Remediate.** Auto-fix the safe mechanical findings in place: status/location mismatch → move via the base `<archive>` workflow (including its cross-reference re-pointing); missing or malformed frontmatter → fill; non-ISO datetime → normalise; broken local link → re-point. Bump `updated` from `date` on every file you change. Leave the judgement calls below untouched.
4. **Verify.** Re-lint and triage rather than chase zero-warn: drive blocking findings to zero and confirm the mechanical warns are resolved, while leaving birth-time drift and other judgement-call warns surfaced-and-accepted (a clone or in-place rewrite resets birth time — expected, not a failure). The clean bar is **0 blocking, mechanical warns resolved, judgement-call warns reported** — not zero-warn.
</workflow>

<surface_for_review>
Surface these for human review; do not silently change them:

- Oversized pages (>300 lines) that need a split.
- Scope ambiguity, and birth-time drift that may be a legitimate clone/checkout (re-stamp `created` only after confirming with the user).
- **Contradictions between tasks** — mirror `wiki_fix`'s contested protocol: flag both sides for human review, never auto-resolve.
</surface_for_review>

<output_contract>
End with a concise report: the per-file changes made, the final lint outcome (triaged as above), and a closing line in the shape `audit complete — N issues resolved, K flagged for review`. Name every judgement call left for the user.
</output_contract>

<family>
The `task_*` family — each sibling does one job, then points to the next; the base `task` skill is the hub that can do all of it:

- `task_create` — write one task file
- `task_check` — readiness gate before building (read-only)
- `task_implement` — do the work
- `task_audit` — verify a believed-done task against the codebase (read-only)
- `task_finish` — close out: set status, bump `updated`, archive
- `task_health` — audit and repair the whole tasks tree **(this skill)**

These ship together as a family; any sibling may be absent if a deployment excluded it. The natural chain is create → check → implement → audit → finish, with health maintaining the tree.
</family>

</task_health_skill>
