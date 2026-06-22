---
name: task_fix
description: Repair the whole tasks backlog tree in one pass. Use when the user asks to health check, clean up, audit, or lint the backlog. Run the archive inclusive linter, fix mechanical frontmatter, status, location, link, datetime, and provenance issues, and surface judgement calls.
version: 1.3.5
author: Andreas F. Hoffmann
license: MIT
---

# task_fix

<task_fix_skill>

<role>
task_fix health-checks the whole `tasks/` tree and repairs what it safely can — the task-backlog analogue of `wiki_fix`. It runs a four-phase loop (orient → assess → remediate → verify), auto-fixes the mechanical findings the linter reports, surfaces the judgement calls for human review, and ends with a concise report. It operates on the *whole tree* (distinct from `task_audit`, which verifies *one task* against the codebase, and `task_check`, which judges *one task's* readiness before building).
</role>

<when_to_activate>
Activate when the user wants the task backlog as a whole audited and tidied:

- "Health-check my tasks" / "clean up the backlog" / "audit the task list" / "lint and fix the tasks tree."

Route elsewhere when the user wants to judge a single task's readiness before building (`task_check`), choose what to work on next (`task_select`), verify one believed-done task against the codebase (`task_audit`), create a task (`task_create`), implement one (`task_implement`), or close one out (`task_finish`).
</when_to_activate>

<design_note>
task_fix runs **inline — no dedicated agent.** The `tasks/` tree is small and the fixes are mechanical, so the agent indirection `wiki_fix` → `auto_shaper_wiki` uses for a large wiki is not warranted here, and it would add an agent to maintain plus a read-token cost. A `task_auto_shaper` agent is deferred future work, to revisit only if the tree grows enough that inline iteration strains a single context — and if so, the safe shape is a read-only assess fan-out feeding a single remediation writer, never per-file write agents (they would race on the shared link graph).
</design_note>

<authority>
The base `task` skill's `SKILL.md` is the single source of truth; read it and follow it rather than copying its rules. Its `<discover>` step locates `tasks/`, its bundled `lint.py --include-archive` is task_fix's archive-inclusive mechanical oracle (`<lint>`), and its `<archive>` workflow defines a status/location move (set `status`, bump `updated` from `date`, `git mv`, re-point cross-references, re-lint). These assets ship in the same plugin as task_fix.
</authority>

<path_resolution>
The bundled scripts (`discover_tasks.sh`, `lint.py`) ship in `scripts/` next to the base `task` skill's `SKILL.md`, not next to this one. After reading that base `SKILL.md` (per `<authority>`), resolve each script's absolute path by combining the directory you loaded it from with `scripts/<script-name>` and invoke that absolute path — never a bare `scripts/...`, which resolves against the current working directory (the target project) rather than the skill, and so finds the project's own `scripts/` or nothing. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed.
</path_resolution>

<workflow>
Run all four phases in order.

1. **Orient.** Read the base `task` skill's rules once — naming, frontmatter, the `<body>` anatomy, the standard-markdown policy, the 300-line split rule, and the `<lint>` / `<archive>` workflows. These are the bar every fix honors.
2. **Assess.** Resolve `tasks/` via `<discover>`, run `lint.py --include-archive` over the tree, and bucket its findings (blocking / warn / info). Then walk every task applying the **best-effort advisory** checks the linter can't: *topic mixing* (one file covering two unrelated units of work — flag for a split), *single-shot-readiness* (a body that has fallen below the base skill's self-sufficiency bar — an empty section, a dangling "TBD", context that assumes the vanished original chat), *cross-link value* (a cross-reference to another task that does no work, judged against the cross-link discipline in the base `task` skill's `<markdown_policy>`), *body framing* (load-bearing content carried mainly by negatives, judged against the base `<body>` authoring rule — a genuine non-goal, deferred-alternative note, guardrail, or expected-state acceptance check is compliant and draws no finding), *artifact-edit placement* (a body that frames an existing-artifact edit as an append where the base `<body>` rewrite-in-place rule calls for superseding the affected passage — surface and propose rather than auto-fix, respecting its carve-outs and the instruct-vs-narrate line), and *restated standing rules* (a body passage that instructs the implementer with a copy of a rule the project's standing instruction documents — `CLAUDE.md` / `AGENTS.md` and equivalents — already own: read those documents and compare; the base `<body>`'s cite-don't-restate corollary is the rule source).
3. **Remediate.** Auto-fix the safe mechanical findings in place: status/location mismatch → move via the base `<archive>` workflow (including its cross-reference re-pointing); legacy archived non-terminal status → set `status: finished`; missing `reported-by` / `implemented-by` → write the linter's git-history-derived value, falling back to the base `<user_name_chain>` when history yields nothing; missing or malformed frontmatter → fill; non-ISO datetime → normalise; broken local link → re-point; a soft-pointer warn → apply the base `<lint>` triage rule first, reading the hit's surrounding context and stripping only a confirmed line-number position claim; when the hit is a false positive such as a size, version, count, or quoted claim-shape, leave it untouched; for a confirmed claim with a cited line number, use the number as a lookup into the target to verify the label still resolves by grep and to strengthen a vague label to the verbatim quote at that location, per the base `<markdown_policy>`'s soft-pointer rule; an unambiguous reverse-duplicate cross-link (the relationship is already stated on the linked side) → remove; a negation-framed body finding whose positive rewrite is mechanical and meaning-preserving (a direct inversion with no judgement call) → reframe. Bump `updated` from `date` on every changed file except when the only changes are the legacy provenance/status retrofit covered by the base `<bump_updated>` exception. Leave the judgement calls below untouched — a cross-link whose value is a genuine call belongs in `<surface_for_review>`, never an auto-delete.
4. **Verify.** Re-lint and triage rather than chase zero-warn: drive blocking findings to zero and confirm the mechanical warns are resolved, while leaving the judgement-call warns (an oversized page that needs a split) surfaced-and-accepted for the user. The clean bar is **0 blocking, mechanical warns resolved, judgement-call warns reported** — not zero-warn.
</workflow>

<surface_for_review>
Surface these for human review; do not silently change them:

- Oversized pages (>300 lines) that need a split.
- Scope ambiguity that needs a human call on the right `scope:` value.
- **Cross-links whose value is a judgement call** — a relatedness-only reference that might still be load-bearing. Flag it for the user; auto-removing on a value judgement risks stripping a genuinely organising link, so reserve the auto-fix for the unambiguous reverse-duplicate case.
- **Body-framing findings past the mechanical case** — surface every body whose load-bearing content is carried mainly by negatives; the auto-reframe covers only the direct, meaning-preserving inversion, so any rewrite involving a judgement call lands here for the user.
- **Artifact-edit placement** — surface a body that frames an existing-artifact edit as an append where the base `<body>` rewrite-in-place rule calls for superseding the affected passage. Propose the in-place rewrite, cite the base rule, respect its carve-outs, and apply the same instruct-vs-narrate boundary used for restated standing rules.
- **Restated standing rules** — surface every passage that instructs the implementer with a copied standing rule, quoting the matched rule from the standing instruction document and proposing the fix: replace the copy with a citation, or drop it when the surrounding text carries nothing else. The user's explicit go-ahead decides — drift between copy and source is exactly the risk. In `## Acceptance`, the base contract's task-specific-gates clause draws the boundary: a generic project-gate item is such a restatement, while a task-specific executable check draws no finding. A body that merely narrates a rule's history (changelog-style context) draws no finding either; the check targets passages that instruct.
- **Contradictions between tasks** — mirror `wiki_fix`'s contested protocol: flag both sides for human review, never auto-resolve.
</surface_for_review>

<output_contract>
End with a concise report: the per-file changes made, the final lint outcome (triaged as above), and a closing line in the shape `audit complete — N issues resolved, K flagged for review`. Name every judgement call left for the user.
</output_contract>

<family>
The `task_*` family — each sibling does one job, then points to the next; the base `task` skill is the hub that can do all of it:

- `task_create` — write one task file
- `task_check` — readiness gate before building (read-only)
- `task_select` — choose and rank the next eligible task/action (read-only)
- `task_implement` — do the work
- `task_audit` — verify a believed-done task against the codebase (read-only)
- `task_finish` — close out: set status, bump `updated`, archive
- `task_fix` — audit and repair the whole tasks tree **(this skill)**

These ship together as a family; any sibling may be absent if a deployment excluded it. The natural chain is create → check → select → implement → audit → finish, with fix maintaining the tree.
</family>

</task_fix_skill>
