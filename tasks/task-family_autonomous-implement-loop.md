---
description: Low-priority convenience loop task_auto_implement: implement then audit, re-implement on findings until the audit is clean, then auto-finish; off by default, single-shot readiness remains the aim.
scope: plugins/ai_dev
created: 2026-06-21T17:17:45
updated: 2026-06-27T17:13:36
status: open
reported-by: Andreas Hoffmann
---

# Autonomous implement-to-done loop for tasks

## Goal

Add `task_auto_implement`, an opt-in convenience loop that carries a `ready` task from implementation to closed without manual hand-offs: run `task_implement`, then `task_audit`; if the audit finds gaps, re-run `task_implement` to resolve exactly those findings and re-audit; when the audit is clean with no findings, run `task_finish`. This is **convenience automation, low priority** — the family aims at single-shot implementation readiness, so a one-shot `task_implement` followed by `task_audit` is usually enough, and this loop only saves the manual hand-offs and the re-implement-on-findings cycle. It is off by default; the manual implement → audit → finish chain stays the simple path.

## Context

This sits alongside the other opt-in autonomy tiers: [`task_auto_check`](archive/task-family_autonomous-readiness-loop.md) uses `task_check` as its gate, and [`task_fix`](task-family_autonomous-tree-shaper.md) can escalate whole-tree judgement calls to `auto_shaper_task` with `task_fix` / the linter as its gate. Here the gate is `task_audit` — the loop closes a task only when the audit confirms the built work matches the task with no findings, so the audit, not the loop, is what prevents finishing work that drifted from the task.

It is low priority because single-shot readiness is the goal: a well-shaped `ready` task should implement correctly in one pass, so the re-implement cycle is a safety net for the occasional miss, not the expected path. It is also the highest-autonomy tier — it writes code and closes work — so it ships off by default and behind the core tiers. `task_auto_implement` is an invokable **skill** that orchestrates the existing `task_implement` / `task_audit` / `task_finish` skills and may spawn a worktree-isolated `auto_implementer_task` agent-function for the build step; spawned agents follow the repo's [agent-naming convention](archive/cross-repo_convention-and-wiki-rename.md) and are never manually invoked. Reuse `task_implement`, `task_audit`, `task_finish`, and the base `task` skill `<backward_move_guard>` by citation, never reimplementing them, and build it on the loop shape proven by the autonomous readiness loop.

## Approach

Run the per-task loop on a `ready` task:

1. Run `task_implement` to build the work (it stamps `implemented`).
2. Run `task_audit`; it verifies the implementation against the task and its tests. On a clean verdict with no findings, the task is `audited`.
3. If the audit returns findings, re-run `task_implement` scoped to resolve exactly those findings, then re-audit. Repeat until the audit is clean or a hard iteration cap is hit.
4. On a clean audit, run `task_finish` to close and archive the task (`finished`).

The loop **stops** on a clean audit (→ `finished`) or at the iteration cap (→ leave the task in its current non-finished status and surface it for a human). Gate the whole loop behind an explicit opt-in and a `ready` precondition, and respect `<backward_move_guard>` on every status write. Keep it convenience-only: it adds no verification of its own — `task_audit` is the sole correctness gate, and the loop never lowers the audit bar to make work pass.

Non-goals: replacing single-shot implementation as the aim (this is a convenience net, not the expected path); inventing a correctness check separate from `task_audit`; running on a task that is not `ready`; and unbounded re-implementation (the iteration cap is mandatory). Keep the manual implement → audit → finish chain as the default.

## Acceptance

- `task_auto_implement` runs only on a `ready` task and behind an explicit opt-in; on a staged ready task it runs `task_implement`, then `task_audit`, and on a clean audit runs `task_finish`, leaving the task `finished`.
- On a staged task whose first implementation has a planted gap, the audit returns findings and the loop re-runs `task_implement` scoped to those findings and re-audits, converging to a clean audit and then finishing — within a hard iteration cap.
- The iteration cap is enforced: a staged task whose audit never clears stops at the cap, leaves the task in its current non-finished status, and surfaces it for a human rather than finishing on an audit with findings.
- `task_audit` is the sole correctness gate: a grep confirms the loop cites `task_implement` / `task_audit` / `task_finish` and `<backward_move_guard>` rather than reimplementing them, and the loop never finishes a task on an audit with findings.
- The skill ships off by default and the manual implement → audit → finish chain is unchanged (a check confirms it still runs without the loop). `make lint` passes and the skill is registered in the plugin README, metadata, and both marketplaces.
