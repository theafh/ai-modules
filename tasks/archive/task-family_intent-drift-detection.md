---
description: Add a freeze-time auto_drift_task subagent to task_auto_check that, only on meaning-level Goal drift from git history, surfaces a one-time human intention check; task_check stays history-free.
scope: "task_* family: new auto_drift_task agent + task_auto_check (task_check unchanged)"
created: 2026-06-28T18:04:01
updated: 2026-07-01T19:58:13
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# task_auto_check: a freeze-time auto_drift_task agent that surfaces a one-time human intention check on meaning-level Goal drift

## Goal

`task_auto_check` freezes a task's `## Goal` at loop entry and defends it as the invariant every repair must preserve — but it never checks whether that frozen Goal has *already* drifted, in git history, from what the task originally meant. A Goal silently rewritten so that what the task is *about* changed — a narrowing, or a caveat that contradicts the original aim — gets frozen and then defended as if it were the true intent. Add a new `auto_drift_task` subagent that reconstructs the task's committed-intent origin from its file history and compares it to the at-entry Goal/title. Wire it into `task_auto_check`'s freeze step so it runs exactly once, before any gate or repair. It classifies on *meaning*, not text: meaning-preserving edits — a clean accretion, a resolved labeled open decision, an intent-preserving clarification — stay silent; only a change to what the Goal is about, or a contradiction with the original aim, qualifies. On a qualifying drift it surfaces a single human intention check — "this Goal appears to have already drifted from its original intent" — with the recovered-versus-current evidence, and human-routes the task instead of auto-repairing it. `task_check` is unchanged and stays history-free, because it is invoked standalone and inside other loops where per-call git archaeology would be wrong. The mechanism and its guardrails live in Approach.

## Context

The detection belongs in a dedicated agent owned by `task_auto_check`, not as a step inside `task_check`. `task_check` is read-only current-text grounding invoked standalone and inside other loops; folding git-history reconstruction and intent classification into it would broaden its job and re-run expensive archaeology on every gate call, including each round of this loop. So the work lives in a new `auto_drift_task` agent alongside the existing modular helpers (`auto_gate_task`, `auto_reviewer_task`, `auto_verifier_task`) under `plugins/ai_dev/agents/`, invoked by `task_auto_check` the way those are.

Run it once, at the freeze instant. `<freeze>` holds the at-entry working-tree Goal and precedes any loop edit, so drift is measured one time against the committed origin. Measuring later, or per round, would confuse the loop's own in-flight clarifications with human drift and pay for history reconstruction repeatedly. `<frozen_intent>` stays exactly as it is — the repair invariant — and the drift check is a one-time advisory beside it, never a replacement of the intent reference.

Keep the human in the loop. Reverting toward the recovered origin could revive deliberately-dropped scope and fight the frozen-Goal invariant `<frozen_intent>` sets; intended drift is legitimate, and only a human can separate intended from unintended. So `auto_drift_task` detects and surfaces, the loop human-routes, and neither reverts. The boundary already modeled by `<structural_split_boundary>` is the shape this needs: a class of finding the loop must not auto-fix, surfaced as stuck / human-routed.

`task_check` stays history-free. The complementary current-state concern — a title or `description` that under-names the body from the current file alone — remains the sibling [title/description coverage task](task-skill_title-body-coverage-check.md), a shared `<readiness_checklist>` item that needs no history. Keep them distinct: that one reads the current file; this one reads history for meaning drift. Neither restates the other.

Motivating instance: a task's uncommitted rewrite cleanly resolved a labeled open decision, introduced an unreconciled caveat (drift), and left the title naming two of five threads; an agent separated the legitimate resolution from the drift by reading history. That run was human-invoked — this task makes the *detection* a standing, freeze-time agent step while keeping the *reconciliation* human-owned.

## Approach

**1. New `auto_drift_task` agent** at `plugins/ai_dev/agents/auto_drift_task.md`, following the existing `auto_*_task` agent shape (frontmatter `name`/`description`/`version`/`model`/`background`/`effort`, then `<role>`/`<objective>`/`<inputs>`/`<policy>`/`<output_contract>`). It reconstructs the task's committed-intent baseline — its earliest committed `## Goal` and `# Title`, following renames (`git log --follow` or equivalent, since the base `<archive>` step and ordinary renames move files with `git mv`) — and compares the current at-entry Goal/title against that baseline. The baseline is the committed origin across the full history, not merely the last commit, so a Goal narrowed over several commits is still in scope. It is read-only: it reverts nothing and edits no file; it returns recovered-versus-current evidence and a classification.

Classify on *meaning*, not text. A clean accretion, a resolved labeled open decision (per the base **Decide or label**), or an intent-preserving clarification all classify as clean and raise nothing. Raise a drift finding only when what the Goal is *about* changed, or when the current Goal contradicts the original aim. Degrade gracefully: where history is squashed or the baseline is otherwise unrecoverable — including a file that clearly predates its current path but yields no followed-rename history — return a low-confidence note and flag only on clean evidence, rather than guessing or falsely reporting a fresh draft as drift. When there is no committed baseline (a genuine fresh draft) or the current Goal/title still matches the baseline, return clean.

The agent ships at version 1.0.0; the plugin meta and marketplace registrations bump per the standing versioning rules.

**2. Wire it into `task_auto_check`'s `<freeze>`** so it runs exactly once, before the first `<gate>` call and any repair. On a clean or meaning-preserving result, the loop proceeds without surfacing anything. On a qualifying drift, `task_auto_check` surfaces a single human intention check to the user — an "Attention: this Goal appears to have already drifted from its original intent" message carrying the recovered-versus-current evidence — and human-routes the task: it halts the auto-repair path for this run rather than repairing toward the recovered origin, leaves the body unchanged, and keeps `<frozen_intent>` intact. The check is surfaced once per run, matching the single freeze-time invocation.

**3. Loop-policy boundary in `task_auto_check`** (`<loop_policy>`), a sibling to `<structural_split_boundary>`: state that a freeze-time `auto_drift_task` finding is human-routed, forbid auto-repair toward the recovered original intent, leave the body unchanged for that finding, and cite `<frozen_intent>`. Compose it with the existing stuck / human-routed channel that `<structural_split_boundary>` and `<mechanical_lint_boundary>` already use, keeping each boundary's rule text in its own tag. The boundary fires only on genuine meaning-level drift: meaning-preserving changes classify as clean at step 1, so the loop never stalls on its own verified edits.

**4. `task_check` is unchanged.** It gains no drift step and stays current-text, read-only history-free grounding, because it is invoked standalone and inside other loops where per-call git archaeology would be wrong. This reverses the earlier plan that placed a detection step in `task_check`'s `<assessment>`.

**5. `auto_gate_task` needs no change.** It forms no independent assessment and only condenses `task_check`'s verdict; the drift check runs beside it at freeze, not through it.

Non-goal: changing the `<freeze>` snapshot itself. The frozen-Goal invariant stays as is; the drift finding is a one-time advisory beside it, not a replacement of the intent reference.

This edits shipped skill content under `plugins/ai_dev/` and adds a new agent, so the standing plugin-version-bump and validation gates apply.

## Acceptance

- A new `auto_drift_task` agent exists at `plugins/ai_dev/agents/auto_drift_task.md`, follows the existing `auto_*_task` agent shape, and ships at version 1.0.0; grepping the agents directory finds it.
- The agent reconstructs the task's earliest committed Goal/title across its full history and follows renames (`git log --follow` or equivalent), not merely the last commit, so drift committed over several commits is in scope.
- The agent classifies on meaning, not text: a clean accretion, a resolved labeled open decision, and an intent-preserving clarification raise nothing; only a change to what the Goal is about, or a contradiction with the original aim, raises a finding.
- The agent is read-only and reverts nothing; it returns recovered-versus-current evidence plus a classification.
- On squashed or unrecoverable history — including a file predating its current path with no followed-rename baseline — the agent returns a low-confidence note and flags only on clean evidence; with no committed baseline or a current Goal/title matching the baseline, it returns clean.
- `task_auto_check` invokes `auto_drift_task` exactly once, at `<freeze>`, before the first gate call and any repair — not per round.
- On a qualifying drift, `task_auto_check` surfaces a single human intention check to the user with the recovered-versus-current evidence, human-routes the task, never auto-repairs toward the recovered original intent, leaves the body unchanged, and keeps `<frozen_intent>` intact.
- On a clean or meaning-preserving result, the loop proceeds without surfacing the intention check.
- `task_auto_check`'s `<loop_policy>` carries a drift boundary, a sibling to `<structural_split_boundary>`, that human-routes the finding, forbids auto-repair toward the recovered intent, leaves the body unchanged, cites `<frozen_intent>`, and composes with the existing stuck / human-routed channel.
- `task_check` is unchanged — grepping `task_check` finds no drift or git-history step; it remains current-text, read-only.
- `auto_gate_task` is unchanged — it forms no independent assessment and the drift check runs beside it at freeze, not through it.
- Plugin meta (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`) and both marketplace registrations are bumped in lockstep per the standing versioning rules.
