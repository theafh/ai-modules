---
description: Add a `task_health` sibling skill that audits and fixes the tasks tree (naming, frontmatter, status/location, links, size, drift) inline, repairing mechanical findings and surfacing judgement calls.
scope: plugins/ai_dev
created: 2026-05-28T20:25:06
updated: 2026-05-31T00:20:09
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Add the `task_health` sibling skill

## Goal

A skill that health-checks the whole `tasks/` tree and fixes what it can —
the task-backlog analogue of `wiki_fix`. The user says "health-check my
tasks" / "clean up the backlog" / "audit the task list" and gets the linter
run plus autonomous repair of the mechanical issues, with judgement-call
findings surfaced for the user.

(Named `task_health`, not `task_check`, deliberately:
[task_check](task-family_check-sibling-skill.md) checks a *single* task for
readiness before `task_implement` runs. This skill is whole-tree health.)

## Context

Depends on [the rename](task-family_rename-tasks-to-task.md). The oracle
already exists: `plugins/ai_dev/skills/task/scripts/lint.py` reports
blocking/warn/info findings for naming, frontmatter, status/location
consistency, datetime format, the `created`-vs-birth-time drift check,
standard-markdown violations, broken local links, page size (>300 lines),
and collisions. `task_health` wraps that into an audit-and-repair loop.

Reference patterns, read end-to-end (not just their one-liners):

- `plugins/knowledge_management/skills/wiki_fix/SKILL.md` is a deliberately
  **thin front end**: it does no orientation or lint itself — it invokes the
  `auto_shaper_wiki` agent, forwards any narrower user scope, and surfaces
  the agent's final report **verbatim**. Its whole output contract is "the
  agent's own final report".
- `plugins/knowledge_management/agents/auto_shaper_wiki.md` is where the
  work lives, structured as **four named phases run in order**:
  - **orient** — read the rules once at the start (the agent reads
    `$WIKI/SCHEMA.md` + index + log + canonical references). Task analogue:
    read the base `task` `SKILL.md` rules once — naming, frontmatter, body
    anatomy, standard-markdown policy, the 300-line split rule.
  - **assess** — run the linter *and* walk every page applying every
    applicable check.
  - **remediate** — fix every finding in place.
  - **verify** — re-lint until clean (the agent's bar: `lint.py` exits 0
    with no blocking or warn findings, only acceptable info-level ones
    remain) and record the audit.
  - **contested protocol** — contradictions between pages are **surfaced,
    not auto-resolved**: the agent marks both sides and lists them for human
    review, ending with a report line like `audit complete — N issues
    resolved, K contested pages flagged`.
- The base skill's `<lint>` and `<archive>` workflows for what a fix looks
  like (bump `updated` from `date`, move on status change, re-point links).

**Design decision — inline (settled).** `task_health` folds the four phases
directly into the skill, with **no** dedicated agent. Rationale: the `tasks/`
tree is small and the fixes are mechanical (rename, bump `updated`, move a
file to match status, re-point a link, re-stamp a drifted `created` after
confirming with the user), so the agent indirection `wiki_fix` →
`auto_shaper_wiki` uses for a large wiki is not warranted here — and it would
add an agent definition to maintain plus the read-token cost flagged in
[wiki_auto-shaper-read-token-cost](wiki_auto-shaper-read-token-cost.md). A
dedicated `task_auto_shaper` agent is **out of scope** for this task; revisit
it as separate future work only if the tree grows enough that inline
iteration strains a single context.

Keep the wiki precedent's shape: orient once, assess fully, remediate in
place, verify (triaged as below — 0 blocking and mechanical warns resolved,
judgement-call warns reported), and end with a concise report.

## Approach

1. Build inline per the settled decision above — one `task_health` skill, no
   agent. Record the inline rationale briefly in the shipped `SKILL.md`, and
   note the agent variant as deferred future work.
2. New skill dir `plugins/ai_dev/skills/task_health/` with `SKILL.md`
   (pseudo-XML, positive language), no agent. Structure the work as the wiki
   agent's four phases:
   - **orient** — read the base `task` skill's rules once.
   - **assess** — `discover_tasks.sh` → run `lint.py` → bucket findings →
     walk every task applying the **best-effort advisory** checks the linter
     can't: *topic mixing* (one task file covering two unrelated units of
     work — flag for a split) and *single-shot-readiness* (a body that no
     longer reads as something an implementer could act on from the file
     alone — an empty section, a dangling "TBD", context that assumes the
     original chat). Surface these; do not auto-rewrite.
   - **remediate** — auto-fix the safe mechanical findings (status/location
     mismatch → move; missing/malformed frontmatter → fill; non-ISO
     datetime → normalise; broken link → re-point).
   - **verify** — re-lint and triage rather than chase zero-warn: drive
     blocking findings to zero and fix the mechanical warns, while leaving
     birth-time drift and other judgement-call warns surfaced-and-accepted
     (the live tree carries birth-time warns a clone or in-place rewrite
     resets — expected, not failures). The clean bar is **0 blocking,
     mechanical warns resolved, judgement-call warns reported** — not
     zero-warn. Then report.
3. Surface, do not silently change, the judgement calls: oversized pages
   needing a split, scope ambiguity, birth-time drift that may be a
   legitimate checkout, and **contradictions between tasks** (mirror
   `wiki_fix`'s contested protocol — flag both sides for human review,
   never auto-resolve).
4. End with a concise final report (issues resolved, items flagged),
   echoing the wiki agent's report line.
5. Register in the plugin/repo metas; ship at 1.0.0; bump plugin lockstep.

## Acceptance

- `task_health` triggers on audit/lint/clean-up/health-check phrasings for
  the task backlog and, on a deliberately-broken fixture tree, runs orient →
  assess → remediate → verify and re-lints to **0 blocking with the
  mechanical warns resolved**; birth-time and other judgement-call warns are
  surfaced-and-accepted, not driven to zero.
- Judgement-call findings (splits, drift, cross-task contradictions) are
  surfaced for human review, not silently changed.
- It ends with a concise report of what was fixed and what was flagged.
- The shipped `SKILL.md` is inline (no agent) and records that rationale
  briefly, noting the agent variant as deferred future work.
- Trigger evals: `task_health` owns audit/fix verbs without the base `task`
  skill stealing them (mirror the wiki/wiki_fix split).
- `make lint` and deploy dry-run pass; plugin meta bumped lockstep.
- Ships the shared `task_*` `<family>` map block (all six siblings, marking itself), matching the block in `task_create` / `task_implement`.

## Related

- Base: [the rename](task-family_rename-tasks-to-task.md).
- Peer boundary to keep crisp: [task_audit](task-family_audit-sibling-skill.md)
  verifies a single task against the codebase; `task_health` audits the
  tree's internal health.
- Source patterns: `plugins/knowledge_management/skills/wiki_fix/SKILL.md` +
  `plugins/knowledge_management/agents/auto_shaper_wiki.md`.
- Tests tracked in
  [task-family_testing-new-features](task-family_testing-new-features.md).
