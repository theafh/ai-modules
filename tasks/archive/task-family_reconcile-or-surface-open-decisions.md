---
description: Lift a stage-agnostic reconcile-or-surface rule for open decisions into the base task skill; wire the check, auto_check, and implement siblings to apply it.
scope: plugins/ai_dev/skills
created: 2026-07-14T20:11:35
updated: 2026-07-15T19:27:39
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Centralize open-decision reconciliation and wire the task_* family to reconcile-or-surface before implementing

## Goal

Give the `task_*` family one authoritative rule for what to do with an open
decision in a task — an unresolved fork, a vague pointer, an either/or the task
leaves undecided — and have every stage that touches a task apply that one rule
at its own point in the lifecycle. The rule is **reconcile, else surface**: first
try to settle the decision to the single path that best fits the user's
intention — the *spirit* of the task — using a defined evidence base; adopt that
path when the evidence settles it, and when it does not, surface the decision to
the user with at least one suggested path rather than choosing arbitrarily.

The user-visible outcome:

- The base `task` skill carries the reconciliation rule once, stage-agnostic, and
  the front-end skills inherit it through their existing `<authority>` reference
  instead of each carrying a divergent copy.
- `task_create` already reconciles while writing — it settles what the authoring
  context safely determines, and surfaces the residual decision or asks the user
  when adopting a path would risk an unintended change not derivable from context
  alone. This behaviour already ships and needs no edit; it inherits the refined
  criterion from the central rule, so the offer it makes stays the same procedure
  the rest of the family now runs.
- `task_check` attempts the reconciliation while assessing an open decision, but
  only surfaces: when the evidence settles it, the readiness report recommends that
  resolution as the fix; when it does not, the report surfaces the decision with
  suggested options for the user. `task_check` stays read-only and writes no body
  content either way.
- `task_auto_check`, layered on top of `task_check`, auto-reconciles: it proposes
  an evidence-grounded reconciled decision through its verified-repair loop and
  writes it when the verifier approves; when no evidence reconciles the decision,
  it surfaces the task as stuck with suggested options rather than inventing a
  choice.
- `task_implement`, on reaching an open decision, reconciles it from the fully
  real codebase plus the same evidence base and proceeds on that path, recording
  the rationale in the shipped artifact; when the evidence does not settle it, it
  surfaces the decision to the user with suggested options and holds rather than
  making an arbitrary call.

The through-line is one clear path — avoid at creation, reconcile-or-surface at
check and auto-check, and reconcile-or-surface again as the implementation
backstop — so an open decision is settled against evidence or handed to the user
at every stage, and never resolved arbitrarily inside `task_implement`.

## Context

Four files change, all under `plugins/ai_dev/skills/`:

- `task/SKILL.md` — the base skill, where the rule is authored once.
- `task_check/SKILL.md`, `task_auto_check/SKILL.md`, `task_implement/SKILL.md` —
  the three siblings whose stage behaviour is wired to the rule.

`task_create/SKILL.md` is deliberately not in that set. Its `<authority>` already
follows the base rules without copying them, and its **Self-check the draft** and
**Offer open-decision reconciliation** steps already reconcile while writing and
carry the one unsettled decision forward to an interactive ask, so it inherits the
refined rule with no source edit.

**Why the base skill owns the rule.** The repo's `CHARTER.md` invariant
*"Skill-family rules live in the family base skill when they govern the whole
family; front-end skills inherit those rules instead of carrying divergent
copies"* applies the moment more than one sibling needs the reconciliation
procedure. So the rule is authored once in `task/SKILL.md` and inherited, not
copied into each front-end.

**What already exists and is reused, not rebuilt.** The base `<body>` already
carries the **Decide or label** rule — resolve every fork derivable from the
authoring material, and label at most one genuinely-open decision with its
options and a default — added by the finished
[single-statement-open-decision task](task-family_single-statement-open-decision.md).
The `<readiness_checklist>` **Ambiguity / under-specification** lens already
routes an unresolved either/or into a **Decide or label** finding.
`task_create` already surfaces that one residual decision after writing and
offers resolve-now or defer, shipped by the finished
[create-reconcile-open-questions task](task-family_create-reconcile-open-questions.md).
`task_auto_check` already runs a **Decide-or-label advocate** reviewer stance and
a verifier clause that preserves explicit human-input boundaries "unless
repository evidence supplies the missing decision." The guardrail-doc reads this
task's evidence base depends on already live in the base `<standing_doc_consumption>`
section. This task lifts and connects that existing machinery; it adds no new
detection rule and no new document reads.

**What is genuinely new.** Today **Decide or label** is authoring-time only ("before
the file is written"), names no ordered evidence base, and stops at *label* rather
than *reconcile*. `task_check` detects an open decision and reports it, but does
not attempt to settle it from evidence. `task_implement`'s workflow step that
begins *"Implement in order"* carries the sentence *"When the task explicitly
leaves a decision open, make the call and record the rationale in the shipped
artifact"* — an unqualified licence to decide, which is the arbitrary-choice risk
this task closes. The new work is the stage-agnostic reconciliation procedure with
its evidence base, plus the check/auto_check/implement wiring; `task_create`
already embodies the authoring-stage behaviour and inherits the refinement
unchanged.

**Guardrail authority.** `CHARTER.md` states the charter is the highest-order
guardrail and the softer docs stay subordinate to it. The reconciliation rule
adopts that same hierarchy: a guardrail doc is authoritative where it speaks —
`CHARTER.md` as a hard boundary whose conflict is surfaced and never auto-resolved,
`ARCHITECTURE.md` / `FEATURES.md` / `TESTING.md` as subordinate design, behaviour,
and test intent — and within the space the guardrails leave open, the decision is
fit to the task's spirit using related tasks and the existing code.

**Co-edit coordination.** The open
[honor-task-dependencies task](../task-family_honor-task-dependencies.md) also edits
`task/SKILL.md` and inserts a step into `task_implement/SKILL.md`'s `<workflow>`,
renumbering the steps that follow, and the open
[unattended-code-interaction task](../task-family_unattended-code-interaction-check.md)
adds a `<readiness_checklist>` lens whose findings route through this
reconcile-or-surface rule as their disposition. All three edit `task/SKILL.md`; beyond that base skill, this task shares the
`task_check` / `task_auto_check` family only with the unattended-code-interaction
task, and shares `task_implement/SKILL.md` only with the honor-task-dependencies
task. On each shared file, whichever task lands second re-reads it and anchors its
edits to the target passages by their verbatim labels rather than by position, so
the changes compose without clobbering each other.

## Approach

Edit the five `SKILL.md` files in positive, action-oriented language and their
existing pseudo-XML structure. Author the rule once in the base skill; the
siblings cite it rather than restating it.

**Base `task` skill — author the reconciliation rule once:**

1. Rewrite the `<body>` **Decide or label** rule in place so it becomes the
   family's stage-agnostic open-decision reconciliation procedure while keeping
   its authoring-time ceiling of one labeled open decision. Keep the
   **Decide or label** bold lead-in verbatim as the rule's greppable anchor and
   expand only its body into the reconciliation procedure, so the family's
   existing citations of that label stay valid — the `<readiness_checklist>`
   **Over-specification** entry and `task_create`'s **Self-check the draft** step,
   both outside this task's edit set, and the `task_auto_check`
   **Decide-or-label advocate** stance name — and the verbatim label the
   Acceptance has each sibling cite resolves to **Decide or label**. The rewritten rule
   states: on an open decision, first reconcile it to the single path that best
   fits the task's spirit using an ordered evidence base — (a) the task's own
   stated intent in its Goal, Approach, Acceptance, and description; (b) the
   project's guardrail docs where present, consulted through
   `<standing_doc_consumption>`, with `CHARTER.md` a hard boundary and the softer
   docs subordinate; (c) related and older tasks, both linked live siblings and
   archived precedent; (d) the already-implemented codebase. When the evidence
   settles the decision — the fitting path is determinable from that evidence
   without introducing a change the context cannot settle — adopt that path, the
   stage recording it where it can write and a read-only stage recommending it.
   When the evidence leaves the path underdetermined, so adopting one would risk an
   unintended change not derivable from context alone, surface the decision to the
   user with its options and at least one suggested path with rationale, rather than
   choosing arbitrarily. State the ceiling, the evidence base, and this
   reconcile-or-surface threshold once here; do not duplicate them into the
   checklist or the siblings.
2. Rewrite the `<readiness_checklist>` **Ambiguity / under-specification** lens
   entry in place so a surfaced open decision routes through the reconciliation
   rule: reconcilable from the evidence base means the finding carries the
   recommended resolution as its fix, and irreconcilable means the finding carries
   the labeled decision with suggested options. Keep the entry pointing at the
   rule rather than restating it.

**`task_create` — no edit needed; it already inherits the rule:**

`task_create` needs no source change. Its `<authority>` already follows the base
rules without copying them, and its **Self-check the draft** and **Offer
open-decision reconciliation** steps already reconcile while writing and carry the
one decision the authoring context cannot safely settle forward to an interactive
resolve-now / defer ask. That carry-forward-and-ask structure is the
reconcile-or-surface threshold at the authoring stage, so the refined central rule
reaches `task_create` unchanged; adding the procedure or threshold text here would
duplicate a base rule against its own "follow, don't copy" authority and
**State once**.

**`task_check` — reconcile while assessing, stay read-only:**

1. Extend `<assessment>` so that when the **Ambiguity / under-specification** lens
   surfaces an open decision, the skill applies the base reconciliation rule
   against the evidence base and either reports the reconciled resolution as the
   issue's minimum fix or surfaces the decision with suggested options when the
   evidence does not settle it. Preserve the read-only contract: `task_check`
   recommends and surfaces, and leaves writing the reconciled decision to the
   editing siblings and the user's apply-findings edit.

**`task_auto_check` — propose the reconciled decision, verify, or surface:**

1. Extend the **Decide-or-label advocate** reviewer stance and the verifier's
   human-input-boundary clause to cite the base reconciliation rule's evidence
   base, so a proposed decision is an evidence-grounded reconciliation the verifier
   keeps only when it is intent-preserving and evidence-supported. When no evidence
   reconciles the decision, surface it through the existing stuck / human-routed
   channel with suggested options, reusing that channel rather than adding a new one.

**`task_implement` — reconcile as the backstop, surface when unsettled:**

1. Rewrite the sentence in the *"Implement in order"* workflow step that today
   reads *"When the task explicitly leaves a decision open, make the call and
   record the rationale in the shipped artifact"* in place. The rewritten sentence
   applies the base reconciliation rule: reconcile the open decision from the
   evidence base — now including the fully real codebase — and when the evidence
   settles it, proceed on that path and record the rationale in the shipped
   artifact; when it does not, surface the decision to the user with suggested
   options and hold rather than making an arbitrary call. Anchor the edit to the
   sentence's verbatim text, not to a step number, so it composes with the
   co-editing honor-task-dependencies task.

Non-goals: keep `task_check` read-only — it surfaces and recommends only, and
writing a reconciled decision stays with `task_auto_check`, the user's
apply-findings edit, and `task_implement`, so `task_check`'s only mutation is the
status stamp. Author the rule once in the base skill and have siblings cite it — do
not copy the procedure or the evidence base into any front-end. Add no new task
detection rule, no new `<readiness_checklist>` lens, and no new guardrail-doc read
beyond the live `<standing_doc_consumption>` mechanism. Leave `task_select`,
`task_audit`, `task_finish`, and `task_fix` untouched: none consumes an open
decision on the path to implementation. Keep the change to the skill prose proven
on staged fixtures; broader eval-suite growth is a separate session per the
standing repo rule that keeps skill changes and harness expansion apart. This
edits shipped skill content, so the standing repo version-bump, plugin-lockstep,
and lint-clean-before-commit rules apply at commit time.

## Acceptance

- `task/SKILL.md` `<body>` carries one canonical open-decision reconciliation rule
  that names the reconcile-else-surface procedure, its reconcile-or-surface
  threshold (reconcile when the path is determinable from the evidence without
  risking an unintended change the context cannot settle, surface otherwise), and
  the ordered evidence base (task intent, guardrail docs with `CHARTER.md` as hard
  boundary, related and older tasks, existing code), and is stage-agnostic rather
  than authoring-only; the rewritten rule keeps its greppable **Decide or label**
  bold lead-in, its prior authoring-only wording no longer stands alone, and the
  one-labeled-open-decision ceiling is preserved inside the rewritten rule.
- The `<readiness_checklist>` **Ambiguity / under-specification** entry is rewritten
  in place to route a surfaced open decision through that rule — recommended
  resolution when reconcilable, labeled decision with suggested options when not —
  and points at the rule rather than restating the procedure.
- `task_create/SKILL.md` is unchanged: its shipped **Self-check the draft** and
  **Offer open-decision reconciliation** steps inherit the refined rule, and a grep
  confirms the procedure, evidence base, and threshold text live in the base skill
  and are not copied into `task_create`. A staged fixture confirms `task_create`
  still reconciles a safely-derivable decision while writing and carries an unsafe
  one forward to the interactive ask, with no source edit.
- `task_check/SKILL.md`'s `<assessment>` applies the base reconciliation rule to a
  surfaced open decision and either reports the reconciled resolution as the issue's
  minimum fix or surfaces the decision with suggested options; the read-only
  stamp-only contract is intact — `task_check` writes no body content.
- `task_auto_check/SKILL.md`'s **Decide-or-label advocate** stance and verifier
  human-input clause cite the base reconciliation rule's evidence base so a proposed
  decision is an evidence-grounded reconciliation, and an irreconcilable decision is
  surfaced through the existing stuck / human-routed channel with suggested options
  rather than a newly added channel.
- `task_implement/SKILL.md`'s *"Implement in order"* step no longer carries the
  unqualified *"make the call and record the rationale"* sentence; the superseding
  sentence reconciles the open decision from the evidence base including the real
  codebase, proceeds and records the rationale when the evidence settles it, and
  surfaces the decision with suggested options when it does not. The edit is
  anchored to the sentence's verbatim text so it composes with the co-editing
  honor-task-dependencies task.
- A grep over `task_check`, `task_auto_check`, and `task_implement` confirms each
  cites the base reconciliation rule by its verbatim label for the procedure and
  evidence base, and none restates them, satisfying the `CHARTER.md` family-rule
  invariant.
- Read end to end, the four changed files plus `task_create`'s inherited behaviour
  form one coherent avoid → reconcile-or-surface → reconcile-or-surface path with no
  contradiction: every stage that meets an open decision either settles it from
  evidence or surfaces it with suggestions, and no stage decides arbitrarily.
- Each edited skill's staged fixture proves its stage behaviour: a task carrying a
  labeled open decision reconcilable from a `CHARTER.md`/related-task/code cue has the reconciled
  path recommended by `task_check` and settled by `task_auto_check` and
  `task_implement`, and a task whose decision no evidence settles is surfaced with
  suggested options at each stage rather than resolved.
