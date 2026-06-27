---
description: Add the optional root CHARTER.md project-identity contract and reusable template, plus a branch-gated hook that hard-blocks edits to it; consumption is owned by the standing-doc framework.
scope: plugins/ai_dev
created: 2026-06-21T15:17:35
updated: 2026-06-27T13:33:12
status: ready
reported-by: Andreas Hoffmann
---

# Charter contract and protect hook for the task family

## Goal

Give the task family the artifact half of its charter guardrail: a falsifiable root `CHARTER.md` project-identity contract — Core Purpose, DOES / DOES NOT domain boundaries, Key Invariants, Intentional Constraints — a reusable starter template for other projects, and a branch-gated protect hook that hard-blocks edits to `CHARTER.md` itself so an autonomous agent cannot quietly rewrite the contract to license its own drift. The hook is the one guard that reading-and-respecting the document cannot provide; how skills and agents actually consult the charter and validate their proposed work against it is the consumption half, owned by the standing-doc framework. The guardrail is coupled to autonomy and fully opt-in: with no `CHARTER.md` present the hook is inert and the task family behaves exactly as it does today.

## Context

By the filing rule that task-system material lives in `tasks/` while project-wide material lives in a root `UPPERCASE.md` doc (see [standing-doc framework](task-family_optional-standing-doc-conventions.md)), the charter is project identity beyond the task system, so it lives at repo root as `CHARTER.md`, a peer of the standing repo rules — not under `tasks/`, which the agents must be free to write. The base `task` skill already treats standing project instructions as a substrate that tasks cite rather than copy, and `CHARTER.md` is exactly such a standing doc.

This task ships only the charter's artifact and its tamper-protection. The consumption — how task_check, the auto_gate_task gate, and the autonomous writing agents validate their proposed work against the charter and stop on a violation — is the standing-doc framework's unified, presence-gated doc-consumption model, not a bespoke validator here. That split is deliberate: charter validation is an agent reading the contract and refusing to violate it, the same mechanism by which it applies any standing rule, so the only thing this task adds beyond the document is the hard fence that reading cannot enforce — a hook that blocks edits to `CHARTER.md` unless a human is on the dedicated guardrail branch.

## Approach

Create this repo's real, activating project contract at root path `CHARTER.md`, populated for `ai-modules` rather than left as a placeholder, with the falsifiable structure: Core Purpose, DOES / DOES NOT domain boundaries, Key Invariants, Intentional Constraints. Ship an inert reusable starter at `plugins/ai_dev/hooks/CHARTER.template.md` carrying the same structure for other projects to copy or adapt; the template never activates anything by itself.

Add the native Claude hook package at `plugins/ai_dev/hooks/hooks.json` and `plugins/ai_dev/hooks/charter_guardrail.sh`. `hooks.json` defines the Claude Code `PreToolUse` hook for `Edit|Write` and invokes the bundled script through `${CLAUDE_PLUGIN_ROOT}/hooks/charter_guardrail.sh` rather than a cwd-relative `./hooks` path. The script reads the hook JSON from stdin, extracts `.tool_input.file_path`, resolves the target repo root from the hook cwd, and exits 2 to block any edit to root `CHARTER.md` unless the current branch matches `guardrail/charter-*`. Do not add or change legacy symlink-deployment hook config such as `hooks/claude-code-hooks*.json`, and leave `deployment/deployment.conf`'s Claude `disallow:**` rule unchanged. Document that this hard block deploys for Claude Code only, since some harnesses (Codex) expose no pre-edit hook — there, autonomous agents rely on the framework's soft read-and-respect consumption alone.

Keep the `guardrail/charter-*` branch as the human-only path where the contract itself changes under review: the hook mechanically blocks contract mutation everywhere else. Register the hook package in the plugin metadata where hooks are declared; this task introduces no new skill, so there is no skill to register.

Non-goals: a separate `task_charter` validation skill or a wired-in validation step — the standing-doc framework owns consumption, with task_check, the auto_gate_task gate, and the autonomous writing agents reading and respecting the contract; and any charter requirement on the manual chain or on a project that has no `CHARTER.md`.

## Acceptance

- This repo has a real root `CHARTER.md` populated as the `ai-modules` project contract, and an inert reusable template ships at `plugins/ai_dev/hooks/CHARTER.template.md`; both carry falsifiable Core Purpose, DOES / DOES NOT, Key Invariants, and Intentional Constraints sections.
- The native Claude hook files exist at `plugins/ai_dev/hooks/hooks.json` and `plugins/ai_dev/hooks/charter_guardrail.sh`, with no `hooks/claude-code-hooks*.json` legacy deployment config added or changed and `deployment/deployment.conf`'s Claude `disallow:**` symlink rule unchanged; an implementer-runnable fixture invokes that packaged hook/config path and shows a staged edit to `CHARTER.md` exits blocked on a normal branch and allowed on a `guardrail/charter-*` branch.
- With no `CHARTER.md` present, the hook is inert and a staged `Edit`/`Write` anywhere proceeds normally, and a separate check confirms the manual create/check/implement chain gains no new requirement and emits no error.
- The hook's Claude-Code-only scope is documented alongside the framework's soft read-and-respect fallback for hookless harnesses; the hook package is registered in the plugin metadata, and a check confirms no `task_charter` skill was created.
