---
description: Add task_auto_check, an opt-in loop driving a task to readiness with task_check as the gate: reviewers debate solutions, the verifier keeps worthwhile intent-safe fixes, re-checked until ready.
scope: plugins/ai_dev
created: 2026-06-21T15:17:35
updated: 2026-06-24T22:06:11
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Autonomous readiness loop for tasks

## Goal

Add `task_auto_check`, an opt-in loop that drives one task to readiness automatically, **reusing `task_check` as the gate** so there is one definition of "ready," not two. When `task_check` reports a task not ready, the loop has reviewers debate solutions to the issues it raised, a verifier keeps only the fixes worth applying and faithful to the task's frozen intent, applies them, and re-runs `task_check` — stopping when `task_check` reports ready or no verified fix remains. It drives `open`/`checked` → `ready` and nothing further; the default single-agent `task_check` stays the simple manual gate.

## Context

The gate must not be re-defined. "Ready" lives once in the base `task` skill `<readiness_checklist>`; `task_check` applies it and stamps `ready` or `checked`. This loop reuses `task_check` verbatim as its gate and status writer rather than inventing a second readiness judgement — a second definition would drift from the first. The multi-stance machinery therefore sits on the **solution** side, not the gate: reviewers generate candidate fixes for the issues `task_check` raised (emergent stances, union for coverage), and an independent refute-by-default verifier keeps only the fixes that are real, worth applying, and intent-preserving (precision plus drift guard). On one model, agreement among reviewers reflects shared priors rather than truth, so the loop never counts agreement; coverage comes from diverse generation and precision from verification — the same technique and frozen-intent anchor the tree-level [`task_auto_shaper`](task-family_autonomous-tree-shaper.md) uses. One source governs each side: the gate cites the `<readiness_checklist>` defect axes, the standing reviewer stances cite the base skill `<body>` repair rules, and the emergent stances instantiate those same rules for the task's content type — so the solution side gains no second definition of "ready," it only supplies the repair moves that flip the defects the gate names.

The honest ceiling: the loop is only as good as `task_check`. If the single-agent gate misses an issue, the loop calls ready early; the fix is to deepen `task_check`'s application of the same checklist, never to add a rival assessor. The one residual no same-model arrangement closes is the correlated blind spot — an optional foreign-model stance via MCP, off by default, is the only hedge.

## Approach

Run the per-task loop:

1. **Freeze the original intent.** Snapshot the task's `## Goal` — plus the user's request when the loop runs at creation time — as immutable for the loop's duration. The loop may sharpen *how* the task is expressed but never change *what* it is for.
2. **Gate (reused `task_check`).** Run `task_check` through a thin spawned gate agent (`auto_gate_task`) that invokes the skill and returns only its structured verdict — the issue list plus the `ready` (clean) / `checked` (blocking issues) stamp `task_check` itself wrote. The orchestrating loop consumes that verdict rather than `task_check`'s full assessment transcript, so the main loop's context stays bounded across iterations. If `ready`, stop.
3. **Debate solutions (coverage).** For the issues `task_check` raised, a planner spawns reviewer stances that propose fixes. The gate names *what is wrong* by citing the `<readiness_checklist>` defect axes; the reviewers name *what a good fix is* by citing the base `task` skill `<body>` **repair rules** (cited, never copied) — a different list, since a fix's quality is an edit property the gate never raises. A fixed **standing set**, spawned lazily for only the concerns the gate raised this round, runs one stance per repair rule:
   - **Self-sufficiency advocate** — adds exactly the missing material so the file-plus-project is implementable cold; when a standing project instruction already owns the content it proposes a citation rather than inlining the rule (the `task_check` `<assessment>` false-positive guard).
   - **Minimum-change advocate** — the tightest diff that resolves the cited issue and nothing more (`<body>` *Compact only to the implementable floor*); generation authors the minimal edit, the verifier later rejects bloated ones.
   - **State-once advocate** — pairs any one-section fix with its Goal/Context/Approach/Acceptance match so one canonical statement remains.
   - **Decide-or-label advocate** — proposes the decision derivable from cited material, or an explicit `Open decision:` with a named default (one is the ceiling).
   - **Acceptance-contract advocate** — makes a fix touching "done" land as flippable, implementer-runnable, task-specific, measured-with-a-fail-branch checks whose edit-items supersede the stale passage.
   - **Rewrite-in-place advocate** — reframes an append-style edit of an existing passage as a supersede, honoring the genuine-addition carve-outs.
   - **Positive-reframe advocate** — rewrites a negation-framed "not X" into the positive action it implies, preserving the technical detail.
   - **Redact-by-generalizing advocate** — generalizes an embedded sensitive or user-specific specific, or surfaces the include/drop choice when the work genuinely needs it.

   On top of the standing set the planner emits **emergent task-specific** stances as domain instantiations of the same rules — an exit-code skeptic for a script task, an overcompression skeptic for prose. Scope-sizing, focus, and complexity defects get no standing repair stance: their fix is a structural split that creates a new file, so the loop proposes the split and surfaces it as stuck rather than auto-performing it (that tree-level job is `task_auto_shaper`'s). Union all proposals so a fix only one stance saw survives.
4. **Verify (precision plus drift).** An independent refute-by-default pass keeps only proposals that are real, resolve the cited issue, are the minimum change, and preserve the frozen intent — defaulting to reject when unsure; a dedicated fidelity check vetoes or narrows any proposal that drifts the task from its frozen `Goal`.
5. **Apply** the surviving fixes (minimum change, one cohesive group at a time), then loop to step 2.

The loop **stops** when `task_check` reports `ready` (the task stays `ready`) or a round yields no verified fix (the task stays `checked`, surfaced as stuck for a human), with a hard iteration cap of 5 rounds as a backstop, overridable up or down by the user prompt. Because the gate is `task_check` and the intent is frozen, the fixed point is the original task made ready, not a mutation of it. `task_auto_check` is an invokable **skill** that spawns the gate, the reviewer stances, and the verifier as modular `auto_*_task` agent-functions — `auto_gate_task` wrapping `task_check`, `auto_reviewer_task` per stance, and `auto_verifier_task` — which it calls and never manually invokes, named per the repo's [agent-naming convention](cross-repo_convention-and-wiki-rename.md). All stances share one model, so the skill deploys on any harness with no per-reviewer model pin; the one optional foreign-model stance stays off by default. Reuse `task_check` (gate plus status writes), the base skill `<readiness_checklist>`, and `<backward_move_guard>` by citation, never reimplementing them.

Non-goals: defining a second readiness criterion or a separate "ready" bar — the gate is `task_check`, full stop; counting agreement or majority voting among reviewers; implementing the work the task describes (`task_implement`) or closing it (`task_finish`), which stay separate skills; and whole-tree health repair (lint, splits, cross-links, contradictions), which is `task_auto_shaper`'s job.

## Acceptance

- `task_auto_check` uses `task_check` as its gate verbatim: a grep confirms it calls or cites `task_check` and the base `<readiness_checklist>` rather than defining its own readiness criterion, and `task_check`'s `ready`/`checked` stamping is what the loop reads to decide whether to stop or iterate.
- On a staged not-ready task, the loop debates solutions to `task_check`'s issues (standing stances plus emergent ones, union), an independent verify pass keeps only the worth-applying, intent-preserving fixes, applies them, and re-runs `task_check`; the task reaches `ready` and the loop stops. A grep confirms the standing reviewer stances cite the base `<body>` repair rules rather than restating them.
- On a staged task whose only issue is scope-sizing, focus, or complexity, the loop proposes a split and surfaces it as stuck rather than auto-performing the file-creating split (that mandate is `task_auto_shaper`'s).
- The loop freezes the task's original `## Goal` and gates every applied fix on fidelity to it: on a staged task where a candidate fix would alter the objective, the fidelity check rejects or narrows it and the original objective is preserved.
- The loop stops correctly: a staged already-ready task applies zero fixes and stops in one gate call; a staged task whose remaining issues yield no verified fix stops as `checked` and is surfaced as stuck. The hard iteration cap defaults to 5 rounds and is overridable by the user prompt: a staged pathological task that never converges halts at the cap and surfaces stuck, and a staged run whose prompt overrides the cap honors the new bound.
- No step computes or gates on agreement among reviewers; `task_auto_check` uses no harness- or agent-specific features — no per-reviewer model pin, no provider-only capability — so it deploys on any single-model harness, with one optional foreign-model stance off by default; the default single-agent `task_check` path is unchanged.
- `task_auto_check` ships as an invokable skill whose spawned gate, reviewer, and verifier agents carry the `auto_*_task` name (a grep confirms it), the base `task` skill's `<family>` roster and the sibling front-ends' family lists gain `task_auto_check`, and `make lint` passes with the skill and its agents registered in the plugin README, metadata, and both marketplaces.
