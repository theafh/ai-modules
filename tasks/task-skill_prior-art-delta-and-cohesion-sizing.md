---
description: "Sharpen create-path scoping: re-derive the genuinely-new delta against shipped and open tasks, route or extend instead of duplicating, and size tasks by cohesion rather than reflexive splitting."
scope: "task_* family skills"
created: 2026-06-15T16:21:22
updated: 2026-06-18T21:39:29
status: ready
reported-by: Andreas Hoffmann
---

# Re-derive the genuinely-new delta and size by cohesion in the create path

## Goal

Two judgment gates in the create path become explicit, so an agent turning a rich request or source into tasks emits the right task(s) at the right size:

- **Delta gate.** When a proposed task overlaps work that already shipped — an archived `finished` task, or code already in place — the agent reads that overlap as evidence the proposal is partly redundant, re-derives the genuinely-new delta against both shipped and open tasks, and surfaces that delta with its routing options for the user instead of writing a competing file: fold the fitting part into an open task, file a follow-up that extends and cross-links the shipped one, create a fresh task only for the genuinely-new remainder, or drop the proposal when the overlap is total.
- **Sizing gate.** A single coherent change across many parts of one system — for example a skill family's shared surface — stays one task even when it is larger; the agent sizes by cohesion (shared rationale and a shared edit surface) rather than by part count, so it does not force-split a unified change into fragments that each re-derive the same rationale. The 300-line hard ceiling stays the upper bound.

Both gates sharpen rules that already exist; this task supplies the operator move the agent currently has to infer.

## Context

This edits the base `task` skill's create-decision surface; `task_create` inherits the prior-art and sizing rules through its `<authority>` and carries its own one-task framing in its `<workflow>`. Files under `plugins/ai_dev/skills/`.

- The delta gate lands in the base `task` skill's `<prior_art>` step — its Tier-2 classifications and its "Surface, never auto-resolve." disposition list. That list today names moves for an *open* match (fold the delta in, narrow to the new part) and a *deferred* match (reopen), but treats a shipped/`finished` match as the classification "Already implemented" with no follow-up move: re-derive against it, then extend it.
- The sizing gate lands beside the base `<body>` rule "Keep each task scoped to **one** atomic item.", the `<split_at_300>` pitfall, and the `<readiness_checklist>`'s **Scope sizing** item — which today flags too-large and too-small but names no cohesion counter-weight to the splitting pressure.
- `task_create`'s `<workflow>` closes with "Keep this to one atomic task file ... hand the multi-task split to the `task` skill" — the sizing gate adds that a coherent multi-part change is not automatically a multi-task split.
- Motivating episode: an agent mined a multi-session work episode into tasks for one skill family. It proposed several "new" rules, two of which had already shipped; the user named the overlap an analysis failure — *you suggested something that should exist* — and directed the moves the delta gate encodes: compare against what shipped, then drop, file a follow-up that extends the shipped task, or route the fitting part into an open task, and create new only for what is genuinely open. In the same correction the user set the sizing principle: a slightly larger task touching many parts of a complex system is fine, and force-splitting one coherent change into many files is over-engineering — the trade is one-shot simplicity against over-engineering-by-force-split.
- This task is itself an instance of the delta gate: the same episode's lessons about how a body is *written* extend already-shipped body rules and ride a sibling task, [task-skill_decided-general-positive-body.md](archive/task-skill_decided-general-positive-body.md); this file carries only the two create-decision gates that no shipped task covers.

## Approach

- **Delta gate, in `<prior_art>`.** Extend the Tier-2 handling so a match against shipped/`finished` work — or against code already in place — reads as a prompt to re-derive the genuinely-new delta before writing. Keep the "Surface, never auto-resolve." stance (report the overlap and the proposed split; the user picks). Add the one shipped-match move with no existing counterpart: filing a follow-up task that extends and cross-links the shipped/`finished` task, for the part that genuinely extends it. Reuse the existing dispositions in place for the other shipped-match behaviours: generalize "fold the delta into the existing task" so the fitting part can route into an open task, use "narrow this task to only the genuinely-new part" for the remainder, and annotate "skip creation" for total overlap.
- **Sizing gate, beside the atomicity and split rules.** State the cohesion counter-weight: one coherent change across many parts of one system is one task, sized by shared rationale and a shared edit surface rather than by part count, and force-splitting such a change into rationale-duplicating fragments is the over-engineering failure. Keep the 300-line hard split as the ceiling and "one atomic item" as the default; the counter-weight resolves only the case where atomicity and cohesion pull apart, so it reads as *when cohesion and the urge to split conflict, cohesion decides* — not as a licence to grow a task past the ceiling.
- **`task_create` workflow.** In `task_create`'s `<workflow>` one-task paragraph, add a brief qualifier that points at the base skill's cohesion rule rather than restating its wording, so its single-file default does not read as *always split a multi-part change* — it still hands genuine multi-item work to the base skill, but a single coherent multi-part change stays one task.
- **Readiness item.** Name the cohesion criterion in the `<readiness_checklist>`'s **Scope sizing** item alongside its too-large / too-small flags, so `task_check` judges by it too.
- Author each rule once in the base skill and let the siblings inherit by reference, per the family's single-source convention.

## Acceptance

- The base `task` skill's `<prior_art>` step states that overlap with shipped/`finished` work, or with code already in place, prompts the agent to re-derive the genuinely-new delta before writing (false today: the shipped-match classification "Already implemented" carries no re-derive step).
- The `<prior_art>` disposition set adds the one shipped/`finished`-match move with no existing counterpart — filing a follow-up that extends and cross-links the shipped task — while reusing the existing fold, narrow, and skip dispositions in place (false today: no disposition lets the agent extend a shipped/`finished` match).
- The shipped-match routing leaves one canonical disposition set: "fold the delta into the existing task" is generalized from the matched task to *an* open task, "narrow this task to only the genuinely-new part" covers the remainder, and "skip creation" is annotated for total overlap (false today: fold names only the matched task, and neither narrow nor skip is annotated for a shipped match).
- The base skill states the cohesion sizing rule beside its atomicity and `<split_at_300>` material: one coherent change across many parts of one system is one task, sized by shared rationale and edit surface rather than part count (false today: the atomicity and split rules carry no cohesion counter-weight).
- That sizing rule keeps the 300-line ceiling and the one-atomic-item default intact, framed so cohesion decides only the atomicity-vs-cohesion conflict rather than licensing growth past the ceiling (false today: nothing states the conflict resolution).
- `task_create`'s `<workflow>` one-task paragraph notes that a coherent multi-part change is not automatically a multi-task split, as a qualifier that points at the base cohesion rule rather than restating its distinctive wording (false today: it routes any multi-item work to the `task` skill without that qualifier).
- The `<readiness_checklist>`'s **Scope sizing** item names the cohesion criterion (false today: it flags only too-large and too-small).
- A distinctive phrase from each new rule resolves to exactly one SKILL.md among the family — the base one — confirming single-source authoring with sibling inheritance by reference.
