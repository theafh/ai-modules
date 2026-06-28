---
description: Give task_check a step that flags a task whose Goal or title drifted from its committed-intent origin, and a task_auto_check boundary that human-routes the finding instead of auto-repairing it.
scope: "task_* family: task_check and task_auto_check"
created: 2026-06-28T18:04:01
updated: 2026-06-28T18:08:27
status: open
reported-by: Andreas Hoffmann
---

# task_check: detect a task drifted from its committed intent and human-route it in auto_check

## Goal

`task_check` grounds every finding against the current file and the repository; it never compares a task against its own committed history. So a task whose `## Goal` or title was edited away from what it originally meant — a silent narrowing, or an ambiguity a later rewrite introduced that left no internal inconsistency — passes the gate clean. An agent can make this call from the file's git history: reconstruct the committed intent, separate a clean accretion or a resolved open decision from unintended drift, and report it. Give `task_check` a standing detection step that does this and raises an intent-drift finding, and pair it with a `task_auto_check` boundary that routes such a finding to a human. Outcome: drift the current-text lens cannot see surfaces as a normal readiness finding, while the loop never silently reverts it toward old intent. The mechanism and its guardrails live in Approach.

## Context

`task_check` is read-only detect-and-report: per its `<assessment>` it grounds each issue against the repository and changes only the status / `updated` stamp, moving no file and editing no body. The drift step fits that shape — it detects and reports, it never reverts.

The detection is `task_check`-specific, not a shared `<readiness_checklist>` item, because it needs the task's commit history. `task_create` self-checks a *draft* against the shared checklist, and a draft has no committed history to compare against, so this step lives in `task_check`'s own `<assessment>`, not in the base checklist.

The complementary current-state half — flagging a title or `description` that under-names the body from the current file alone — is the sibling [title/description coverage task](task-skill_title-body-coverage-check.md), a shared checklist item that needs no history. This task is the history half: it catches a Goal silently rewritten with no internal inconsistency, which the current-text check cannot see. Keep them distinct; neither restates the other. When the current-state coverage check already flags an under-naming title, this step does not re-raise the same title divergence — its title contribution is limited to drift invisible from the current file alone, such as a re-narrowing the current-text check reads as consistent.

`task_auto_check` runs `task_check` verbatim through `auto_gate_task` as its only gate, then freezes the task's `## Goal` as the invariant every repair must preserve (`<frozen_intent>` calls it the "original" Goal, meaning the at-entry, working-tree version). If that frozen Goal is itself drifted, the loop defends it and the verifier rejects re-widening. The existing `<structural_split_boundary>` already models the shape this needs: `task_check` detects a class of issue the loop must not auto-fix, and the loop surfaces it as human-routed / stuck rather than editing the body.

Motivating instance (this session, a sibling repo): a task's uncommitted rewrite cleanly resolved a labeled open decision, introduced an unreconciled caveat (drift), and left the title naming two of five threads; an agent separated the legitimate resolution from the drift by reading history. That run was human-invoked — this task makes the *detection* standing while keeping the *repair* human-owned.

## Approach

**1. Detection step in `task_check`** (its `<assessment>`). Add a standing, best-effort step that reconstructs the task's committed-intent baseline — its earliest committed `## Goal` and `# Title`, following renames (the base `<archive>` step and ordinary renames move files with `git mv`, so reconstruction must follow history across the rename, e.g. `git log --follow`) — and compares the current working-tree Goal/title against that baseline. The baseline is the committed origin across the full history, not merely the last commit, so a Goal narrowed and then committed earlier is still in scope. Cost-gate it: skip when there is no committed baseline (a genuine fresh draft) or when the current Goal/title still matches the baseline; classify only on a real divergence.

Classify by whether *intent* changed, not whether text changed. A clean accretion, a resolved labeled open decision (per **Decide or label**), or an intent-preserving clarification — including `task_auto_check`'s own in-loop edits already verified against `<frozen_intent>` — all classify as clean and raise nothing. Raise an intent-drift finding only for an unintended change of what the task is for, grounded in the recovered-versus-current diff and ranked among the other issues.

Keep it read-only and advisory: report the divergence and that a human should reconcile it; state the fix as "a human reconciles the divergence," never "revert to the original Goal" (which could revive deliberately-dropped scope), and revert nothing. Degrade gracefully: where history is squashed or the baseline is otherwise unrecoverable — including a file that clearly predates its current path but yields no followed-rename history — note low confidence and flag only on clean evidence, rather than guessing or falsely skipping as a fresh draft.

**2. Human-routing boundary in `task_auto_check`** (its `<loop_policy>`), modeled on `<structural_split_boundary>`. When the gate raises an intent-drift finding, stop the auto-edit path for that issue: do not auto-repair it toward the recovered original intent — reverting to a superseded Goal can revive deliberately-dropped scope and fights the frozen-Goal invariant `<frozen_intent>` sets. Surface it as human-routed / stuck with the recovered-versus-current evidence, and leave the body unchanged for that issue. State it as a sibling boundary to `<structural_split_boundary>`, and note it composes with the verifier's existing "preserve human-input boundaries" rule (`<verification_standard>`) rather than competing with it. The boundary fires only on genuine unintended drift: the loop's own intent-preserving clarifications classify as clean at the gate per step 1, so the loop never flags or stalls on its own verified edits.

**3. `auto_gate_task` needs no change.** It forms no independent assessment and only condenses `task_check`'s verdict, so the drift finding rides its issue list into the loop untouched.

Non-goal: changing the `<freeze>` snapshot itself. The frozen-Goal invariant stays as is; the drift finding is a flag beside it, not a replacement of the intent reference.

This edits shipped skill content under `plugins/ai_dev/`, so the standing plugin-version-bump and validation gates apply.

## Acceptance

- `task_check`'s `<assessment>` carries a standing, best-effort intent-drift step; grepping `task_check` finds it.
- The step's baseline is the task's earliest committed Goal/title across its full history and follows renames (`git log --follow` or equivalent), not merely the last commit, so drift committed earlier is in scope.
- The step is cost-gated: it skips when there is no committed baseline (fresh draft) or the current Goal/title matches the baseline, and classifies only on a real divergence.
- Classification keys on intent, not text: a clean accretion, a resolved labeled open decision, and an intent-preserving clarification — including `task_auto_check`'s own in-loop edits verified against `<frozen_intent>` — raise nothing; only an unintended change of what the task is for raises a finding.
- The finding is read-only and advisory: `task_check` still changes only the status / `updated` stamp and reverts nothing, and the finding's stated fix is "a human reconciles the divergence," never "revert to the original Goal."
- On squashed or unrecoverable history — including a file predating its current path with no followed-rename baseline — the step degrades to a low-confidence note and flags only on clean evidence, rather than guessing or skipping as a fresh draft.
- The step lives in `task_check`'s `<assessment>`, not the base shared `<readiness_checklist>`; grepping the base checklist finds no drift item.
- When the sibling current-state coverage check already flags an under-naming title, this step does not re-raise the same title divergence; its title contribution is limited to drift invisible from the current file alone.
- `task_auto_check`'s `<loop_policy>` carries a drift boundary, a sibling to `<structural_split_boundary>`, that human-routes an intent-drift finding, forbids auto-repair toward the recovered original intent, leaves the body unchanged, and cites `<frozen_intent>`; it does not fire on the loop's own intent-preserving clarifications.
- `auto_gate_task` is unchanged — it forms no independent assessment and relays the drift finding as part of `task_check`'s issue list.
