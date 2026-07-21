---
description: Refine the base task skill's Out-of-scope rule: state what it records (work not done), the exclusion-vs-requirement test, and what never belongs there; add the matching readiness-checklist finding.
scope: plugins/ai_dev/skills/task
created: 2026-07-21T16:30:11
updated: 2026-07-21T16:30:11
status: open
reported-by: Andreas Hoffmann
---

# Clarify the Out-of-scope rule: exclusions are work the task does not do, never in-scope requirements

## Goal

The base `task` skill's **Declare exclusions as an Out of scope boundary** rule reads as a self-contained block that states what the `**Out of scope:**` block records, the test that separates an exclusion from a requirement, and the two cases an author never writes there — so an in-scope requirement or a bare "this is not excluded" note never lands in the block again. The readiness checklist gains the matching finding, so `task_check` catches the miscategorization when it slips past authoring.

## Context

The rule exists today in [SKILL.md](../plugins/ai_dev/skills/task/SKILL.md) as **Declare exclusions as an Out of scope boundary**, shipped via [task-family_out-of-scope-boundary-convention.md](archive/task-family_out-of-scope-boundary-convention.md). It defines the two entry kinds well — a **rejection** (work the task never does) and a **deferral** (work owned by a named sibling) — but it states only what the block *is*, never what it is *not for*, so nothing steers an author away from filing an in-scope item there.

That gap produced a concrete slip while shaping a task: a runtime guardrail the task actively builds — "the agent never fabricates a value; it never silently resolves a conflict" — was written into the `**Out of scope:**` block, when a guardrail the task delivers is an in-scope requirement that belongs in Goal, Approach, or Acceptance. A follow-up "fix" then added a meta line noting the guardrail "is not an exclusion", which is itself noise: a block for work-not-done never explains what is not excluded. Both slips trace to the rule omitting its not-for side and a distinguishing test. The episode is the illustration; the deliverable is the general rule.

The readiness checklist's **Contradictions** lens already guards the boundary in one direction — it flags a Goal, Approach, or Acceptance element that delivers work the block excludes, and an entry ambiguous between rejection and deferral. It does not yet flag the reverse: an in-scope requirement miscategorized as an exclusion, or a meta not-an-exclusion note.

Standing repo rules this task follows: author the refined rule in positive, action-oriented language per `ai_instruction_writing`; keep it a family rule in the base skill so the front-end siblings inherit it through their `<authority>` reference rather than each carrying a copy.

Edit surface: [SKILL.md](../plugins/ai_dev/skills/task/SKILL.md) — the **Declare exclusions as an Out of scope boundary** rule and the readiness checklist **Contradictions** lens. Check that the nearby "Negatives earn their place … a guardrail" sentence stays consistent, since a guardrail earns its place as a positive requirement rather than as an out-of-scope entry.

## Approach

1. **Rewrite the rule in place into a self-contained block.** Lead with its purpose — the `**Out of scope:**` block records the work this task does not do — keep the rejection and deferral kinds as they stand, and add the not-for side:
   - **State the test that separates an exclusion from a requirement:** when the task does work to make a statement true, that statement is a requirement and belongs in Goal, Approach, or Acceptance; the block holds only statements of work the task does not do.
   - **Name the two cases to keep out:** a requirement, guardrail, invariant, or feature behavior the task builds (state it as a positive requirement in its own section); and a note asserting that something is not excluded (state the in-scope item where it belongs and leave the block to exclusions alone).

   Keep the block compact and positive-voiced per `ai_instruction_writing`, and keep it in the base skill as the single family source.
2. **Pair the enforcement in the readiness checklist.** Extend the **Contradictions** lens so an `**Out of scope:**` entry stating an in-scope requirement, guardrail, or feature behavior the task builds, and a meta note asserting that something is not excluded, are contradiction-rank findings, routed through **Decide or label** like the existing boundary findings — relocate the item to its proper section, or drop the meta note.

**Out of scope:**

- Migrating or re-editing existing task files onto the clarified rule — the convention converges opportunistically through update, check, and auto-repair, so this task ships the rule and its check rather than a backlog sweep.

## Acceptance

1. `rg` over [SKILL.md](../plugins/ai_dev/skills/task/SKILL.md) confirms the **Declare exclusions as an Out of scope boundary** rule states the block's purpose (work the task does not do), retains the rejection and deferral kinds, states the exclusion-versus-requirement test, and names the two never-write cases (an in-scope requirement, guardrail, or feature behavior; a meta not-an-exclusion note).
2. `rg` confirms the readiness checklist **Contradictions** lens names, as contradiction-rank findings routed through **Decide or label**, an in-scope requirement or guardrail written into the `**Out of scope:**` block and a meta not-an-exclusion note.
3. `rg` across the front-end sibling skills confirms the rule stays authored once in the base `task` skill, with no sibling carrying its own copy.
4. A static read confirms the rewritten rule uses positive, action-oriented voice per `ai_instruction_writing` and stays a compact single block rather than a multi-paragraph digression.
5. A `task_check` behavior eval proves the enforcement: a staged fixture task that files an in-scope guardrail (for example "the agent never fabricates a value") in its `**Out of scope:**` block is flagged as a miscategorized-exclusion contradiction, while a task whose block holds only genuine work-not-done exclusions is not. The scenario lands in the task-family eval harness and passes against the refined rule and checklist.
