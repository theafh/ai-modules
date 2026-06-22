---
description: Add task_auto_check, an opt-in loop driving a task to readiness with task_check as the gate: reviewers debate solutions, the verifier keeps worthwhile intent-safe fixes, re-checked until ready.
scope: plugins/ai_dev
created: 2026-06-21T15:17:35
updated: 2026-06-22T22:41:09
status: open
reported-by: Andreas Hoffmann
---

# Autonomous readiness loop for tasks

## Goal

Add `task_auto_check`, an opt-in loop that drives one task to readiness automatically, **reusing `task_check` as the gate** so there is one definition of "ready," not two. When `task_check` reports a task not ready, the loop has reviewers debate solutions to the issues it raised, a verifier keeps only the fixes worth applying and faithful to the task's frozen intent, applies them, and re-runs `task_check` — stopping when `task_check` reports ready or no verified fix remains. It drives `open`/`checked` → `ready` and nothing further; the default single-agent `task_check` stays the simple manual gate.

## Context

The gate must not be re-defined. "Ready" lives once in the base `task` skill `<readiness_checklist>`; `task_check` applies it and stamps `ready` or `checked`. This loop reuses `task_check` verbatim as its gate and status writer rather than inventing a second readiness judgement — a second definition would drift from the first. The multi-stance machinery therefore sits on the **solution** side, not the gate: reviewers generate candidate fixes for the issues `task_check` raised (emergent stances, union for coverage), and an independent refute-by-default verifier keeps only the fixes that are real, worth applying, and intent-preserving (precision plus drift guard). On one model, agreement among reviewers reflects shared priors rather than truth, so the loop never counts agreement; coverage comes from diverse generation and precision from verification — the same technique and frozen-intent anchor the tree-level [`task_auto_shaper`](task-family_autonomous-tree-shaper.md) uses.

The honest ceiling: the loop is only as good as `task_check`. If the single-agent gate misses an issue, the loop calls ready early; the fix is to deepen `task_check`'s application of the same checklist, never to add a rival assessor. The one residual no same-model arrangement closes is the correlated blind spot — an optional foreign-model stance via MCP, off by default, is the only hedge.

## Approach

Run the per-task loop:

1. **Freeze the original intent.** Snapshot the task's `## Goal` — plus the user's request when the loop runs at creation time — as immutable for the loop's duration. The loop may sharpen *how* the task is expressed but never change *what* it is for.
2. **Gate (reused `task_check`).** Run `task_check`; it applies the `<readiness_checklist>`, stamps `ready` (clean) or `checked` (blocking issues), and returns the issue list. If `ready`, stop.
3. **Debate solutions (coverage).** For the issues `task_check` raised, a planner emits emergent task-specific stances — an exit-code skeptic for a script task, an overcompression skeptic for prose — alongside the standing skeptics, each proposing fixes; union the proposals so a fix only one stance saw survives.
4. **Verify (precision plus drift).** An independent refute-by-default pass keeps only proposals that are real, resolve the cited issue, are the minimum change, and preserve the frozen intent — defaulting to reject when unsure; a dedicated fidelity check vetoes or narrows any proposal that drifts the task from its frozen `Goal`.
5. **Apply** the surviving fixes (minimum change, one cohesive group at a time), then loop to step 2.

The loop **stops** when `task_check` reports `ready` (the task stays `ready`) or a round yields no verified fix (the task stays `checked`, surfaced as stuck for a human), with a hard iteration cap as a backstop. Because the gate is `task_check` and the intent is frozen, the fixed point is the original task made ready, not a mutation of it. `task_auto_check` is an invokable **skill** that spawns the reviewer stances and the verifier as modular `auto_*_task` agent-functions — `auto_reviewer_task` per stance and `auto_verifier_task` — which it calls and never manually invokes, named per the repo's [agent-naming convention](cross-repo_convention-and-wiki-rename.md). All stances share one model, so the skill deploys on any harness with no per-reviewer model pin; the one optional foreign-model stance stays off by default. Reuse `task_check` (gate plus status writes), the base skill `<readiness_checklist>`, and `<backward_move_guard>` by citation, never reimplementing them.

Non-goals: defining a second readiness criterion or a separate "ready" bar — the gate is `task_check`, full stop; counting agreement or majority voting among reviewers; implementing the work the task describes (`task_implement`) or closing it (`task_finish`), which stay separate skills; and whole-tree health repair (lint, splits, cross-links, contradictions), which is `task_auto_shaper`'s job.

## Acceptance

- `task_auto_check` uses `task_check` as its gate verbatim: a grep confirms it calls or cites `task_check` and the base `<readiness_checklist>` rather than defining its own readiness criterion, and `task_check`'s `ready`/`checked` stamping is what the loop reads to decide whether to stop or iterate.
- On a staged not-ready task, the loop debates solutions to `task_check`'s issues (emergent stances, union), an independent verify pass keeps only the worth-applying, intent-preserving fixes, applies them, and re-runs `task_check`; the task reaches `ready` and the loop stops.
- The loop freezes the task's original `## Goal` and gates every applied fix on fidelity to it: on a staged task where a candidate fix would alter the objective, the fidelity check rejects or narrows it and the original objective is preserved.
- The loop stops correctly: a staged already-ready task applies zero fixes and stops in one gate call; a staged task whose remaining issues yield no verified fix stops as `checked` and is surfaced as stuck, within a hard iteration cap.
- No step computes or gates on agreement among reviewers; `task_auto_check` runs with no per-reviewer model pin on at least one non-Cursor harness, with one optional foreign-model stance off by default; the default single-agent `task_check` path is unchanged.
- `task_auto_check` ships as an invokable skill whose spawned reviewer and verifier agents carry the `auto_*_task` name (a grep confirms it), and `make lint` passes with the skill and its agents registered in the plugin README, metadata, and both marketplaces.
