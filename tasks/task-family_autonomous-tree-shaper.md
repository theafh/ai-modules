---
description: Build the deferred task_auto_shaper as a skill (delta over task_fix): an invokable orchestrator spawning read-only auto_*_task assessors and serially writing the tree-health fixes it surfaces.
scope: plugins/ai_dev
created: 2026-06-21T15:17:35
updated: 2026-06-22T22:41:09
status: open
reported-by: Andreas Hoffmann
---

# Autonomous tree-shaper skill — the delta over inline task_fix

## Goal

Build `task_auto_shaper`, the invokable **skill** that `task_fix` defers, scoped as the genuine delta over what `task_fix` already does inline. The skill earns its existence by adding three things `task_fix` lacks: it runs at a scale a single inline context cannot, it autonomously resolves the tree-health judgement calls `task_fix` only surfaces, and it does both by spawning a read-only assess fan-out of modular `auto_*_task` agent-functions while the skill itself is the single serialized writer — parallel assessment that is better than the single-agent shapers either the task or the knowledge families ship today. Its refinement is bounded to converge on the original tasks made sound, never a mutation of them. It stays opt-in and manually invokable; `task_fix` remains the simple inline default for the common small-tree case.

## Context

`task_fix` already owns the mechanical core: a four-phase inline pass (orient → assess → remediate → verify) that runs the archive-inclusive linter, auto-fixes the mechanical findings (status/location, provenance, datetime, links, soft-pointers, reverse-duplicate links, meaning-preserving reframes), and **surfaces** the judgement calls (300-line splits, body-framing past the mechanical case, scope ambiguity, restated standing rules, cross-task contradictions) for a human. Its own design note defers "a task_auto_shaper" and names the safe shape: "a read-only assess fan-out feeding a single remediation writer, never per-file write agents (they would race on the shared link graph)." This task builds exactly that **as a skill that spawns agents**: the invokable `task_auto_shaper` skill orchestrates and is the single serialized writer, and it spawns modular read-only `auto_*_task` agent-functions (`auto_reviewer_task` per stance, `auto_verifier_task`) for the parallel assess fan-out — agents the skill calls and never manually invokes, named per the repo's [agent-naming convention](archive/cross-repo_convention-and-wiki-rename.md). It reuses `task_fix`'s remediation and the base `task` skill's `<lint>`, `<archive>`, `<readiness_checklist>`, and `<backward_move_guard>` by citation, and updates `task_fix`'s deferred note to point at this skill-plus-agents shape.

The gate is `task_fix`/the linter (whole-tree health), not `task_check` (per-task readiness): this skill repairs the backlog's structural soundness, while driving a single task to `ready` is the job of [`task_auto_check`](task-family_autonomous-readiness-loop.md), which spawns the same `auto_*_task` functions. The two share one technique — generate-then-verify with a frozen-intent anchor — and the shaper may invoke `task_auto_check` per task when a tree pass also wants the readiness dimension.

## Approach

Model the skill on the proven `wiki_fix` → shaper-agent pattern (the wiki agent is being renamed to the `auto_`-prefixed agent scheme — `auto_shaper_wiki` — in the housekeeping task): the same four named phases, task-first iteration that evaluates each task cold to break the confirmation-bias cascade, the re-Read-after-`git mv` discipline before inbound-link edits, the contested protocol that marks and surfaces contradictions without picking a winner, and the confirm-before-bulk gate for changes spanning many files. The two improvements over that single-agent pattern are the heart of the delta:

- **Parallel assess fan-out.** The skill runs `task_fix`'s linter and advisory checks over the tree as its health gate, then spawns `auto_*_task` agent-functions to apply generate-then-verify to the judgement calls `task_fix` surfaces — emergent same-model stances proposing fixes (unioned for coverage), then an independent refute-default verify (precision) — with zero writers among the spawned agents so the shared link graph is untouched during assessment.
- **Autonomous resolution of judgement calls, safely gated.** Where `task_fix` can only surface a split, a body-framing reframe, or a scope relocation, the skill resolves it — but only when the generate-then-verify pass returns a verified fix and the change clears the drift guards below. Genuine contradictions and contested calls are still surfaced, never auto-resolved.

The remediate phase is the **skill itself as a single serialized writer**: it applies one fix (or one cohesive fix group) at a time, re-lints, and moves on, so two writes never touch overlapping cross-references at once — the spawned agents only ever read.

The refine loop is bounded so it converges on the original tasks refined, never a mutation of them. **Freeze the original intent** of each task it edits — that task's `## Goal` — as an immutable snapshot at loop start, and gate every applied change on fidelity to that snapshot, so the loop may sharpen *how* a task is expressed but never change *what* it is for. This is the task-scoped twin of the project-level [intent guardrail](task-family_intent-guardrail-for-autonomy.md): the project intent gate guards against drifting the project, the frozen-`Goal` snapshot guards against drifting an individual task from its own objective, and both run before any write. The mandate is bounded to resolving the **defects** `task_fix` surfaces, not open-ended optimization, which is the engine of drift. Each applied fix also passes an **adversarial fidelity gate** — a devil's-advocate pass charged solely with whether the change drifts a task from its frozen intent, able to veto or narrow it — and is a minimum change applied only when verified, so no lone reviewer's reinterpretation mutates a task. The loop **stops** when a full round produces no change that survives verification — the generate-then-verify pass, across all its stances, cannot put forward a single grounded fix — with a hard iteration cap as a backstop. Because the mandate is defect-resolution and the intent is frozen, the fixed point is the original backlog made sound, not something mutated beyond recognition.

The skill ships off by default and bundled in the plugin.

Non-goals: per-task `open` → `ready` readiness promotion, which is `task_auto_check`'s job (the shaper may invoke it per task but does not redefine it); autonomous code implementation (`task_auto_implement` / a separate later follow-up); and any spawned agent writing to the shared link graph — only the skill writes, and serially. Keep `task_fix` unchanged as the inline default.

## Acceptance

- A `task_auto_shaper` **skill** exists (invokable, not a bare agent), modeled on the four-phase shaper protocol with task-first iteration and the re-Read-after-`git mv` discipline, shipping off by default, and `task_fix`'s deferred note is updated to describe this skill-plus-agents shape.
- The skill spawns read-only `auto_*_task` agent-functions for the assess fan-out (a grep confirms the spawned agents carry the `auto_*_task` name and that none writes), and the skill is the single serialized writer, proven to drive the linter to zero on a staged messy backlog with no cross-reference corruption across fixes that touch overlapping links.
- On a staged backlog, the skill autonomously resolves at least the split, body-framing-reframe, and scope-relocation classes that `task_fix` surfaces, applying each only when the generate-then-verify pass returns a verified fix and both the project intent gate and the frozen-`Goal` fidelity gate pass; a planted project-intent violation blocks the corresponding write and the task is left untouched and surfaced.
- The loop freezes each edited task's original `## Goal` and gates every applied change on fidelity to it: on a staged task where a candidate "fix" would alter the task's objective, the adversarial fidelity gate rejects or narrows it and the original objective is preserved.
- The loop stops when a round surfaces no verified change, with a hard iteration cap as backstop: a staged already-clean tree produces zero applied changes and terminates in one round, and a staged defected tree converges and then stops once no verified defect remains.
- Genuine cross-task contradictions are marked and surfaced via the contested protocol, never auto-resolved, on a staged contradicting-pair fixture.
- `task_fix`'s inline behavior is unchanged: a check confirms the small-tree health-check still runs inline with no agent, and a grep over the new skill and its agents confirms they cite the base `task` skill and `task_fix` rather than copying their rules. `make lint` passes and the skill and its agents are registered in the plugin README, metadata, and both marketplaces.
