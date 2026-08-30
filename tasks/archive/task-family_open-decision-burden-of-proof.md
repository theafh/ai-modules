---
description: Tighten Decide-or-label: reconcile every fork the evidence settles; a genuinely open decision is written into the task and surfaced to the user, guardrail conflicts always qualifying.
scope: plugins/ai_dev/skills
created: 2026-08-22T22:08:25
updated: 2026-08-30T13:03:07
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Put the burden of proof on surfacing an open decision

## Goal

The base `task` skill's **Decide or label** rule already orders reconcile before
surface, but the Surface branch's trigger is asserted by the author and the
assertion is never tested or recorded. Nothing forces the evidence walk to
happen, and no trace of it lands in the task file where `task_check` could
judge it. Tighten the rule and its two authoring-side consumers so the rule
reads: settle silently every fork the available evidence can settle, and treat
a decision as genuinely open only when that evidence is insufficient to decide
it or when the paths in play would cross a guardrail boundary. A genuinely open
decision is then handled twice over, and both halves are mandatory: it is
written into the task as the labeled "Open decision:" carrying its options, a
suggested default, and the reason it is open, and it is surfaced to the user.
Surfacing what the evidence settles is the nitpicking this rule ends; silently
deciding what the evidence cannot settle stays the violation it always was.

The user-visible outcome: authoring yields tasks with no open decision whenever
the evidence settles the fork, and when a task does carry one, the label itself
shows the evidence walk happened, so `task_check` can judge the claim instead
of taking it on faith.

## Context

The rule lives in `plugins/ai_dev/skills/task/SKILL.md`, in the `<body>` bullet
with the bold lead-in "**Decide or label.**". Its Surface branch reads
"**Surface** when the evidence leaves the path underdetermined, so adopting one
would risk an unintended change not derivable from context alone", and its
ceiling sentence reads "one labeled open decision is the authoring ceiling
because every other fork was reconciled from the material available while
writing". Two gaps follow. The trigger is self-asserted: the author declares
underdetermination without having to show the tiers were consulted, and the
declaration leaves no trace in the artifact. And the required default invites
masquerade: the rule asks the label to name "the default an implementer takes
without further input", so an evidence-settled default reads as a legitimate
open decision instead of as the reconciliation it already is.

The same file's `<readiness_checklist>` carries the **Ambiguity /
under-specification** entry, whose clause "an unresolved either/or is a
**Decide or label** finding" routes forks through the rule. It has no explicit
flag for a labeled open decision that masquerades: one missing the reason it is
open, or one whose named default already rests on decisive evidence.

Two further gaps sit beside those. The rule's authoring-time sentence,
"At authoring time this surface is one labeled \"Open decision:\"", lets the
written label count as the surfacing, so a decision can sit in a file the user
never saw. And the ordered evidence base is incomplete: it names the guardrail
docs but neither the harness-loaded rule files that complete the standing repo
rules, nor the working session's own context, nor the project's in-repo wiki,
three sources the family already has available.

`plugins/ai_dev/skills/task_create/SKILL.md` consumes the rule twice. Its
**Self-check the draft** step carries forward "the single labeled \"Open
decision:\" permitted by the base **Decide or label** rule", a permitted-slot
framing that reads as a quota rather than a ceiling. Its **Offer open-decision
reconciliation** step surfaces the carried decision after writing with "a
concrete reconciliation suggestion", and today draws no conclusion when that
suggestion turns out to rest on evidence that settles the fork.

Design lineage, each linked because reading it changes the edit:
[the reconcile-or-surface task](task-family_reconcile-or-surface-open-decisions.md)
authored the stage-agnostic rule, the ordered evidence base, and the
cite-don't-copy wiring the edits must preserve;
[the create-reconcile task](task-family_create-reconcile-open-questions.md)
built the two `task_create` steps being reworded;
[the single-statement task](task-family_single-statement-open-decision.md)
introduced the ceiling being reframed, and shows its intent was an anti-fork
bound, never an expected slot.

The failure mode this closes was observed in a downstream project's backlog. An
authoring session labeled "how the test suite reaches the pure functions past
module-scope heavy imports" as its open decision, with a default and a
confident rationale, while every evidence tier settled on that same default:
the task's own Goal required the standing gate, the project's TESTING.md (a
guardrail doc) requires that gate to run on a machine without built artifacts,
and precedent and code agreed. The correct output was reconciling to the
default; instead the user had to resolve it by hand and asked why the skill had
not. Three affordances invited the miss: the self-asserted trigger, the
permitted-slot framing, and archived tasks carrying the same labeled-default
pattern as copyable precedent.

Propagation needs no sibling edits beyond `task_create`: `task_check`,
`task_auto_check`, and `task_implement` cite **Decide or label** by its label
under the `CHARTER.md` family-rule invariant, so the strengthened rule reaches
every stage through the citation.

Co-edit coordination: the finished
[gate-evidence task](task-family_gate-evidence-and-refutation.md) and
[illustration task](task-family_illustration-needs-a-rule.md) edited
`task/SKILL.md` in other passages and are closed. This task alone owns the
**Decide or label** edits; at implement time re-read the file and anchor
those edits to the target passages by their verbatim labels.

## Approach

Rewrite the **Decide or label** bullet's Surface branch, ceiling, and
authoring-time sentence in place, keeping the bold lead-in verbatim as the
greppable anchor and keeping the options-plus-default shape of the label. The
additions below land inside the rewritten rule:

- The extended evidence base. The rewrite states the ordered evidence base as:
  (a) the task's own stated intent across its Goal, Approach, Acceptance, and
  description; (b) the standing repo rules, comprising the harness-loaded rule
  files and the guardrail docs where present — CHARTER.md as the hard boundary
  with ARCHITECTURE.md, FEATURES.md, and TESTING.md subordinate — consulted
  through the existing `<standing_doc_consumption>` mechanism, absorbing the
  rule's current guardrail-doc tier so one canonical rules tier remains; (c)
  the working session's own context at stages that run inside one; (d) related
  and older tasks, both linked live siblings and archived precedent; (e) the
  project's in-repo wiki where present; (f) the already-implemented codebase.
  A fork any tier settles is reconciled silently rather than surfaced.
- The why-open clause. Surfacing requires the labeled "Open decision:" to
  state, in one clause, why the fork is genuinely open. Exactly two grounds
  qualify: the evidence is insufficient, meaning the tiers are silent or in a
  conflict none of them resolves, which includes a call resting on user
  preference the evidence cannot reach, such as taste, priority, cost, or
  risk appetite; or the fork is guardrail-bound, meaning the paths in play
  would cross a guardrail boundary, which the family's standing hierarchy
  never auto-resolves. The settling test: when that clause cannot be written
  truthfully, the decision is reconcilable, and the rule's Reconcile branch
  applies.
- The dual obligation. A qualifying decision is both written into the body as
  the labeled "Open decision:" and surfaced to the user: the create path's
  reconciliation step carries the surface at authoring time, and
  `task_auto_check`'s "human-routed stuck channel" and `task_implement`'s
  "surface the decision to the user with its options and at least one
  suggested path and hold" carry it at the non-interactive stages. A label the
  user never saw and an ask that left no trace in the file each violate the
  rule. This supersedes the sentence that lets the written label count as the
  surfacing.
- The decisive-default test. A default the author can name and justify from
  the evidence base, with no tier against it, is a reconciliation: adopt it
  and record the resolution in the body. The open-decision form's default is a
  suggestion among evidence-equal options, or a starting point for a
  user-owned call.
- Zero as the norm. Keep the one-open-decision ceiling and state that zero is
  the expected authoring outcome; reaching the ceiling is the exception that
  the why-open clause justifies.

Extend the `<readiness_checklist>` **Ambiguity / under-specification** entry by
one clause that points at the rule rather than restating it: a labeled open
decision missing the why-open clause, or one whose named default carries an
evidence-decisive rationale, is a reconcile finding that carries that default
as its fix.

Align `task_create`. Reword the **Self-check the draft** step in place so the
carried-forward label requires the why-open clause and the "permitted by the
base **Decide or label** rule" framing is superseded by ceiling-as-exception
wording. Extend the **Offer open-decision reconciliation** step by one clause:
when the concrete reconciliation suggestion rests on evidence that settles the
fork, the step says so and recommends resolve-now, because the decision
belonged reconciled at the self-check. Name that step as the authoring-time
surface the dual obligation requires, so a carried-forward decision always
reaches the user there.

**Out of scope:**

- A migration sweep over existing backlogs. Existing tasks converge
  opportunistically through update, check, and repair, per the family's
  standing convergence stance.
- Weakening the Surface path. A fork the evidence cannot settle, and a
  user-owned call, must still be labeled rather than silently decided; this
  task raises the proof required to use the path and removes nothing from it.
- Edits to `task_check`, `task_auto_check`, or `task_implement`. They consume
  the rule by citation and inherit the tightening.

## Acceptance

1. The **Decide or label** bullet in `plugins/ai_dev/skills/task/SKILL.md`
   carries the why-open clause requirement with its two qualifying grounds
   (insufficient evidence, guardrail-bound), keeps the labeled "Open
   decision:" options-plus-default shape (options and a suggested default)
   that Approach retains while superseding the prior authoring-time sentence,
   the dual written-and-surfaced obligation (create-path **Offer open-decision
   reconciliation**; `task_auto_check`'s "human-routed stuck channel";
   `task_implement`'s "surface the decision to the user with its options and
   at least one suggested path and hold"), the decisive-default test, the
   zero-as-norm framing, and an ordered evidence base of (a) the task's own
   stated intent; (b) standing repo rules (harness-loaded rule files and
   guardrail docs CHARTER.md, ARCHITECTURE.md, FEATURES.md, TESTING.md,
   absorbing the prior separate guardrail-doc tier into one canonical rules
   tier); (c) the working session's own context at stages that run inside one;
   (d) related and older tasks; (e) the project's in-repo wiki where present;
   (f) the already-implemented codebase; the bold lead-in "**Decide or
   label.**" is unchanged; the prior Surface sentence, the prior ceiling
   sentence, and the prior authoring-time sentence that let the written label
   count as the surfacing are superseded in place, leaving one canonical
   statement of each.
2. `rg "permitted by the base" plugins/ai_dev/skills/task_create/SKILL.md`
   returns nothing; the **Self-check the draft** step requires the why-open
   clause on the carried-forward label; the **Offer open-decision
   reconciliation** step carries the decisive-evidence clause that recommends
   resolve-now and stands as the authoring-time surface the dual obligation
   names.
3. The **Ambiguity / under-specification** checklist entry flags a labeled
   open decision lacking the why-open clause, or one whose default rests on
   decisive evidence, as a reconcile finding carrying that default as its fix,
   and cites the rule rather than restating it.
4. A grep across the sibling `SKILL.md` files under `plugins/ai_dev/skills/`
   confirms the Surface trigger, the why-open clause, and the decisive-default
   test are stated only in the base rule, and every other occurrence is a
   citation by the **Decide or label** label.
5. Staged fixtures under `tests/task_create/evals/` (new Pattern A harness,
   `evals.json`, driven by `run.py` as stage → agent → grade, matching
   `tests/git_commit/evals/` and `tests/tasks/evals/`) prove three authoring
   shapes through the create path, and ship with the change per the standing
   repo rule on tests:
   `reconcile-recorded` — an input whose fork a guardrail-doc tier settles
   yields a task with no open decision and the resolution recorded in the
   body; `labeled-why-open` — an input whose fork no tier settles yields
   exactly one labeled open decision whose label carries its options, a
   suggested default, and why the evidence leaves it open, with the create
   path surfacing it to the user; and
   `guardrail-bound-surface` — an input whose fork is guardrail-bound yields
   the same labeled-and-surfaced handling rather than an auto-resolution.
   Each scenario grades the written task file and, where a surface is
   required, the **Offer open-decision reconciliation** user-facing turn.
   `reconcile-recorded` mirrors the observed failure's shape, so the old
   behavior fails it and the tightened rule passes.
