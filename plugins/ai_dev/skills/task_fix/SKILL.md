---
name: task_fix
description: Repair the whole tasks backlog tree in one pass, with an optional autonomous escalation. Use when the user asks to health check, clean up, audit, lint, or autonomously resolve backlog judgement calls. Run the archive inclusive linter, fix mechanical frontmatter, status, location, link, datetime, and provenance issues inline by default, and escalate to auto_shaper_task only on explicit opt-in or confirmed scale.
version: 1.3.8
author: Andreas F. Hoffmann
license: MIT
---

# task_fix

<task_fix_skill>

<role>
task_fix health-checks the whole `tasks/` tree and repairs what it safely can — the task-backlog analogue of `wiki_fix`. It runs a four-phase loop (orient → assess → remediate → verify), auto-fixes the mechanical findings the linter reports, surfaces judgement calls for review by default, and ends with a concise report. On explicit autonomous-resolution opt-in, or on a scale trigger the user confirms, it escalates those judgement calls to `auto_shaper_task`, which becomes the single serialized writer for that run. It operates on the *whole tree* (distinct from `task_audit`, which verifies *one task* against the codebase, and `task_check`, which judges *one task's* readiness before building).
</role>

<when_to_activate>
Activate when the user wants the task backlog as a whole audited and tidied:

- "Health-check my tasks" / "clean up the backlog" / "audit the task list" / "lint and fix the tasks tree."
- "Resolve the backlog judgement calls autonomously" / "run the autonomous task tree shaper" / "let task_fix handle the splits."

Route elsewhere when the user wants to judge a single task's readiness before building (`task_check`), automatically repair one task until it is ready (`task_auto_check`), choose what to work on next (`task_select`), verify one believed-done task against the codebase (`task_audit`), create a task (`task_create`), implement one (`task_implement`), or close one out (`task_finish`).
</when_to_activate>

<design_note>
task_fix runs inline by default because most `tasks/` trees are small and the common fixes are mechanical. The autonomous path is an escalation inside this skill, not a second user-facing skill: `auto_shaper_task` is spawned only when the user asks for autonomous judgement-call resolution or confirms that the tree is large enough to justify the read fan-out. Escalation is mutually exclusive with the inline remediate phase for that run: either task_fix writes inline, or `auto_shaper_task` writes serially as the sole writer. The spawned assess agents provide read-side proposals and verification; file-creating splits, task moves, cross-reference rewrites, and frontmatter stamps stay with the single writer so parallel writers never race on the shared link graph.
</design_note>

<authority>
The base `task` skill's `SKILL.md` is the single source of truth; read it and follow it rather than copying its rules. Its `<discover>` step locates `tasks/`, its bundled `lint.py --include-archive` is task_fix's archive-inclusive mechanical oracle (`<lint>`), and its `<archive>` workflow defines a status/location move (set `status`, bump `updated` from `date`, `git mv`, re-point cross-references, re-lint). These assets ship in the same plugin as task_fix.
</authority>

<path_resolution>
The bundled scripts (`discover_tasks.sh`, `lint.py`) ship in `scripts/` next to the base `task` skill's `SKILL.md`, not next to this one. After reading that base `SKILL.md` (per `<authority>`), resolve each script's absolute path by combining the directory you loaded it from with `scripts/<script-name>` and invoke that absolute path — never a bare `scripts/...`, which resolves against the current working directory (the target project) rather than the skill, and so finds the project's own `scripts/` or nothing. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed.

Resolve `auto_shaper_task`, `auto_reviewer_task`, `auto_verifier_task`, and `auto_gate_task` by their published names through the current harness's normal agent mechanism. When a harness exposes only file paths, those agents live in the same plugin at `../../agents/` relative to this skill directory.
</path_resolution>

<workflow>
Run all four phases in order.

1. **Orient.** Read the base `task` skill's rules once — naming, frontmatter, the `<body>` anatomy, the standard-markdown policy, the 300-line split rule, and the `<lint>` / `<archive>` workflows. These are the bar every fix honors.
2. **Assess.** Resolve `tasks/` via `<discover>`, run `lint.py --include-archive` over the tree, and bucket its findings (blocking / warn / info). Then walk every task applying the **best-effort advisory** checks the linter can't: *topic mixing* (one file covering two unrelated units of work — flag for a split), *single-shot-readiness* (a body that has fallen below the base skill's self-sufficiency bar — an empty section, a dangling "TBD", context that assumes the vanished original chat), *cross-link value* (a cross-reference to another task that does no work, judged against the cross-link discipline in the base `task` skill's `<markdown_policy>`), *body framing* (load-bearing content carried mainly by negatives, judged against the base `<body>` authoring rule — a genuine non-goal, deferred-alternative note, guardrail, or expected-state acceptance check is compliant and draws no finding), *artifact-edit placement* (a body that frames an existing-artifact edit as an append where the base `<body>` rewrite-in-place rule calls for superseding the affected passage — surface and propose rather than auto-fix, respecting its carve-outs and the instruct-vs-narrate line), and *restated standing rules* (a body passage that instructs the implementer with a copy of a rule the project's standing instruction documents — `CLAUDE.md` / `AGENTS.md` and equivalents — already own: read those documents and compare; the base `<body>`'s cite-don't-restate corollary is the rule source). When the user requested autonomous judgement-call resolution, or when the tree is large enough that the assess list will strain one context, present that escalation scope and continue only after the opt-in or confirmation is explicit.
3. **Remediate.** In the inline default, auto-fix the safe mechanical findings in place: status/location mismatch → move via the base `<archive>` workflow (including its cross-reference re-pointing); legacy archived non-terminal status → set `status: finished`; missing `reported-by` / `implemented-by` → write the linter's git-history-derived value, falling back to the base `<user_name_chain>` when history yields nothing; missing or malformed frontmatter → fill; non-ISO datetime → normalise; broken local link → re-point; a soft-pointer warn → apply the base `<lint>` triage rule first, reading the hit's surrounding context and stripping only a confirmed line-number position claim; when the hit is a false positive such as a size, version, count, or quoted claim-shape, leave it untouched; for a confirmed claim with a cited line number, use the number as a lookup into the target to verify the label still resolves by grep and to strengthen a vague label to the verbatim quote at that location, per the base `<markdown_policy>`'s soft-pointer rule; an unambiguous reverse-duplicate cross-link (the relationship is already stated on the linked side) → remove; a negation-framed body finding whose positive rewrite is mechanical and meaning-preserving (a direct inversion with no judgement call) → reframe. Bump `updated` from `date` on every changed file except when the only changes are the legacy provenance/status retrofit covered by the base `<bump_updated>` exception. Leave the judgement calls below untouched in the inline path — a cross-link whose value is a genuine call belongs in `<surface_for_review>`, never an auto-delete. In the escalated path, hand the full assessed defect set to `auto_shaper_task` and perform no inline writes for that run; the agent owns serial remediation and returns its verification report.
4. **Verify.** For the inline path, re-lint and triage rather than chase zero-warn: drive blocking findings to zero and confirm the mechanical warns are resolved, while leaving the judgement-call warns (an oversized page that needs a split) surfaced-and-accepted for the user. The inline clean bar is **0 blocking, mechanical warns resolved, judgement-call warns reported** — not zero-warn. For the escalated path, require `auto_shaper_task` to re-run `lint.py --include-archive`, report each applied fix and surfaced issue, and stop only when the linter is clean for the verified defect set or no verifier-approved change remains.
</workflow>

<surface_for_review>
Surface these for human review in the inline path. When the user opted into autonomous resolution, route these to `auto_shaper_task` for verifier-gated repair unless the item says it remains human-owned:

- Oversized pages (>300 lines) that need a split.
- Scope ambiguity that needs a human call on the right `scope:` value.
- **Cross-links whose value is a judgement call** — a relatedness-only reference that might still be load-bearing. Flag it for the user; auto-removing on a value judgement risks stripping a genuinely organising link, so reserve the auto-fix for the unambiguous reverse-duplicate case.
- **Body-framing findings past the mechanical case** — surface every body whose load-bearing content is carried mainly by negatives; the auto-reframe covers only the direct, meaning-preserving inversion, so any rewrite involving a judgement call lands here for the user.
- **Artifact-edit placement** — surface a body that frames an existing-artifact edit as an append where the base `<body>` rewrite-in-place rule calls for superseding the affected passage. Propose the in-place rewrite, cite the base rule, respect its carve-outs, and apply the same instruct-vs-narrate boundary used for restated standing rules.
- **Restated standing rules** — surface every passage that instructs the implementer with a copied standing rule, quoting the matched rule from the standing instruction document and proposing the fix: replace the copy with a citation, or drop it when the surrounding text carries nothing else. The user's explicit go-ahead decides — drift between copy and source is exactly the risk. In `## Acceptance`, the base contract's task-specific-gates clause draws the boundary: a generic project-gate item is such a restatement, while a task-specific executable check draws no finding. A body that merely narrates a rule's history (changelog-style context) draws no finding either; the check targets passages that instruct.
- **Contradictions between tasks** — mirror `wiki_fix`'s contested protocol: flag both sides for human review and leave the substantive resolution human-owned.
</surface_for_review>

<output_contract>
End with a concise report: the mode used (`inline` or `escalated`), the per-file changes made, the final lint outcome (triaged as above for inline, agent-verified for escalation), and a closing line in the shape `audit complete — N issues resolved, K flagged for review`. Name every judgement call left for the user and include the `auto_shaper_task` report when escalation ran.
</output_contract>

<family>
The `task_*` family — each sibling does one job, then points to the next; the base `task` skill is the hub that can do all of it:

- `task_create` — write one task file
- `task_check` — readiness gate before building (read-only)
- `task_auto_check` — autonomously repair one task until `task_check` reports ready
- `task_explain` — explain one task at a high level (read-only)
- `task_select` — choose and rank the next eligible task/action (read-only)
- `task_implement` — do the work
- `task_audit` — verify a believed-done task against the codebase (read-only)
- `task_finish` — close out: set status, bump `updated`, archive
- `task_fix` — audit and repair the whole tasks tree **(this skill)**

These ship together as a family; any sibling may be absent if a deployment excluded it. The default manual chain is create → check → select → implement → audit → finish, with `task_auto_check` as an opt-in readiness repair loop and fix maintaining the tree.
</family>

</task_fix_skill>
