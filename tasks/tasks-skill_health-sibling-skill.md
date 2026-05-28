---
description: Add a `task_health` sibling skill that audits and fixes the tasks tree (naming, frontmatter, status/location, links, size, drift) — agent-driven like wiki_fix or inline, TBD.
scope: plugins/ai_dev
created: 2026-05-28T20:25:06
updated: 2026-05-28T21:07:26
status: open
---

# Add the `task_health` sibling skill

## Goal

A skill that health-checks the whole `tasks/` tree and fixes what it can —
the task-backlog analogue of `wiki_fix`. The user says "health-check my
tasks" / "clean up the backlog" / "audit the task list" and gets the linter
run plus autonomous repair of the mechanical issues, with judgement-call
findings surfaced for the user.

(Named `task_health`, not `task_check`, deliberately:
[task_check](tasks-skill_check-sibling-skill.md) checks a *single* task for
readiness before `task_implement` runs. This skill is whole-tree health.)

## Context

Depends on [the rename](archive/tasks-skill_rename-tasks-to-task.md). The oracle
already exists: `plugins/ai_dev/skills/task/scripts/lint.py` reports
blocking/warn/info findings for naming, frontmatter, status/location
consistency, datetime format, the `created`-vs-birth-time drift check,
standard-markdown violations, broken local links, page size (>300 lines),
and collisions. `task_health` wraps that into an audit-and-repair loop.

Reference patterns, read end-to-end (not just their one-liners):

- `plugins/knowledge_management/skills/wiki_fix/SKILL.md` is a deliberately
  **thin front end**: it does no orientation or lint itself — it invokes the
  `wiki_auto_shaper` agent, forwards any narrower user scope, and surfaces
  the agent's final report **verbatim**. Its whole output contract is "the
  agent's own final report".
- `plugins/knowledge_management/agents/wiki_auto_shaper.md` is where the
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

**Open design decision — agent vs inline (resolve as part of this task):**

- *With a dedicated agent* (mirrors `wiki_fix` → `wiki_auto_shaper`): a thin
  `task_health` skill delegates to a `task_auto_shaper` agent that runs the
  orient → assess → remediate → verify protocol and returns a final report
  the skill surfaces verbatim. Clean separation, can iterate
  fix→re-lint→fix autonomously over a large tree, but adds an agent
  definition to maintain and a read-token cost (the same concern raised for
  the wiki agent in
  [wiki_auto-shaper-read-token-cost](wiki_auto-shaper-read-token-cost.md)).
- *Inline* (skill folds the same four phases directly, no agent): simpler,
  fine because the task tree is small and the fixes are mechanical (rename,
  bump `updated`, move file to match status, re-point a link, re-stamp a
  drifted `created` after confirming with the user). Likely the right
  default given the bounded problem size — decide and record the rationale
  in the task body when implementing.

Either way, keep the wiki precedent's shape: orient once, assess fully,
remediate in place, verify to a clean lint, and end with a concise report.

## Approach

1. Decide agent-vs-inline (lean inline unless the tree-size argument
   changes); record the decision and rationale in the shipped `SKILL.md`.
2. New skill dir `plugins/ai_dev/skills/task_health/` (+ a
   `task_auto_shaper` agent if the agent path wins). Structure the work as
   the wiki agent's four phases:
   - **orient** — read the base `task` skill's rules once.
   - **assess** — `discover_tasks.sh` → run `lint.py` → bucket findings →
     walk every task applying checks the linter can't (topic mixing, a body
     that no longer reads single-shot-ready).
   - **remediate** — auto-fix the safe mechanical findings (status/location
     mismatch → move; missing/malformed frontmatter → fill; non-ISO
     datetime → normalise; broken link → re-point).
   - **verify** — re-lint until it exits 0 with no blocking/warn (only
     acceptable info), and report.
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
  assess → remediate → verify and re-lints to a clean exit (no blocking/warn,
  only acceptable info).
- Judgement-call findings (splits, drift, cross-task contradictions) are
  surfaced for human review, not silently changed.
- It ends with a concise report of what was fixed and what was flagged.
- The agent-vs-inline decision and its rationale are recorded in the
  shipped `SKILL.md`.
- Trigger evals: `task_health` owns audit/fix verbs without the base `task`
  skill stealing them (mirror the wiki/wiki_fix split).
- `make lint` and deploy dry-run pass; plugin meta bumped lockstep.

## Related

- Base: [the rename](archive/tasks-skill_rename-tasks-to-task.md).
- Peer boundary to keep crisp: [task_audit](tasks-skill_audit-sibling-skill.md)
  verifies a single task against the codebase; `task_health` audits the
  tree's internal health.
- Source patterns: `plugins/knowledge_management/skills/wiki_fix/SKILL.md` +
  `plugins/knowledge_management/agents/wiki_auto_shaper.md`.
- Tests tracked in
  [tasks-skill_testing-new-features](tasks-skill_testing-new-features.md).
