---
description: Add an optional intent guardrail for autonomous task writes: a root INTENT.md contract, a branch-gated protect hook, and an intent-check wired into the autonomous writers.
scope: plugins/ai_dev
created: 2026-06-21T15:17:35
updated: 2026-06-21T17:36:50
status: open
reported-by: Andreas Hoffmann
---

# Intent guardrail for autonomous task operation

## Goal

Give the task family an optional intent guardrail that keeps autonomous AI writes from drifting a project away from its stated intention, and couple that guardrail to the autonomy features so its complexity is only paid for when it buys something. A project that turns on autonomous agents gains a falsifiable identity contract those agents are checked against; a project using the manual task chain takes on nothing new. The deliverable is a root `INTENT.md` contract, a branch-gated hook that hard-blocks edits to it, an intent-validation step wired into the autonomous writers, and a helper that derives and checks the contract.

## Context

The guardrail exists specifically to bound autonomous operation, so it is the safety floor the autonomous loops — including the [autonomous tree-shaper](task-family_autonomous-tree-shaper.md) — stand on. When no `INTENT.md` is present, the guardrail is inert and the task family behaves exactly as it does today — autonomy and its guardrail switch on together.

Two design questions are settled here. First, where the contract lives: by the filing rule that task-system material lives in `tasks/` while project-wide material lives in a root `UPPERCASE.md` doc, the intent contract is project identity (beyond the task system), so it lives at repo root as `INTENT.md`, a peer of the standing repo rules — not under `tasks/`, which the agents must be free to write. The base `task` skill already treats standing project instructions as a substrate tasks cite rather than copy, and `INTENT.md` is exactly such a standing doc. Second, the mechanism shape follows the wiki skill's schema approach — a base layer shipped with the skills plus a project-extensible layer that the skills read and enforce — but the artifact is a root contract, not a `tasks/` schema, because its content is project identity, not task-authoring convention. A separate task-authoring schema is deliberately not introduced: the base task rules already live in the skills, and a required schema doc would be the kind of tedious ceremony this family avoids.

## Approach

Ship `INTENT.md` as a root contract with a falsifiable template — Core Purpose, DOES / DOES NOT domain boundaries, Key Invariants, Intentional Constraints — where every item yields a binary consistency verdict against a diff. The base structure ships with the guardrail helper; the project fills and extends the content.

Wire a required pre-write step into the autonomous writer skills: before applying, validate the proposed change against `INTENT.md` when it exists, proceed only on a pass, and surface a conflict (leaving the work untouched) otherwise. This validation is read-only and advisory — it reports drift but never blocks; the hook is the only hard block.

Add a branch-gated `PreToolUse` hook on `Edit|Write`, bundled in the plugin's `hooks/` directory, that blocks any edit to `INTENT.md` unless the branch name marks a deliberate guardrail change (a `guardrail/intent-*` branch). Keep it provider-neutral (stdin `file_path`, exit-2 block, repo-root resolution). Document that this hard block deploys for Claude Code only, since some harnesses (Codex) expose no pre-edit hook — there, autonomous agents rely on the soft validation alone.

Add a maintenance helper that derives a draft `INTENT.md` from the codebase for human ratification on the guardrail branch, and validates supplied context (a task body, an edit batch, or the whole backlog) against the contract into a pass line or a damage-ordered conflict list. Keep three layers distinct: the hard hook mechanically blocks contract mutation, the soft validation checks content against the contract, and the `guardrail/intent-*` branch is the human-only path where the contract itself changes under review.

## Acceptance

- A root `INTENT.md` template/example exists with falsifiable Core Purpose, DOES / DOES NOT, Invariants, and Intentional Constraints sections.
- A `PreToolUse` hook and its config deploy via `make deploy`; a staged edit to `INTENT.md` exits blocked on a normal branch and exits allowed on a `guardrail/intent-*` branch.
- An intent-validation step is wired into the autonomous writer skill(s) and, on a staged task carrying a planted boundary violation, returns a conflict and leaves the task untouched; on a clean task it returns a pass.
- With no `INTENT.md` present, the task family behaves exactly as before: a check confirms the manual create/check/implement chain gains no new requirement and emits no error.
- The hook's Claude-Code-only scope is documented alongside the soft-validation fallback for hookless harnesses; `make lint` passes and the hook, helper, and template are registered in the plugin README, metadata, and both marketplaces.
