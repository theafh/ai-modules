---
description: Make Out of scope the task family's one canonical exclusion convention, authored once in the base skill, with body/boundary contradictions surfaced at check and the boundary honored at implement.
scope: plugins/ai_dev/skills
created: 2026-07-14T18:15:07
updated: 2026-07-14T19:32:19
status: open
reported-by: Andreas Hoffmann
---

# Make "Out of scope" the task family's one canonical exclusion convention, checked at readiness and honored at implementation

## Goal

Turn the task family's informal, three-names-for-one-thing exclusion prose
into one rule-governed **Out of scope** convention. "Out of scope" becomes the
single term everywhere in the family for declared exclusions, replacing the
incumbent "non-goals" and the scattered "out of scope" variants. A task that
declares exclusions does so in one canonical form, an explicit contradiction
between the body and that declared boundary surfaces as a readiness issue
instead of passing silently, and an implementer never silently crosses a
boundary the task declares. Presence stays optional and the machinery stays
out of sight: a task with nothing to exclude carries no Out of scope block,
task creation gains no new prompt, and in the majority of runs the convention
works in auto mode — normalized and repaired by the existing loops — rather
than surfacing questions.

The user-visible outcome:

- The base `task` skill carries the convention once — where declared
  exclusions live, what an entry looks like, and the two kinds an entry can
  be — and the front-end skills inherit it through their existing
  `<authority>` reference instead of each carrying a divergent copy.
- One vocabulary: every place the family names declared exclusions says
  "Out of scope." The incumbent "non-goals" wording in the base skill,
  `task_implement`, `task_audit`, and `task_fix` is renamed to it, so no
  competing term survives in the skills.
- `task_check` and `task_auto_check` surface a body element that requires,
  delivers, or proves work the task's own Out of scope block excludes, because
  the checklist lens they already apply names that contradiction; `task_check`
  needs no source edit for this.
- `task_auto_check` repairs boundary findings through its existing
  verified-repair loop — normalizing variant phrasings to the canonical form
  and reconciling contradictions when evidence settles which side wins — and
  surfaces the task as stuck when no evidence does.
- `task_implement` keeps building everything in scope and skipping declared
  out-of-scope work, and gains the backstop: when delivering the Goal or an
  Acceptance item would require crossing a declared boundary, it surfaces that
  contradiction and holds rather than silently crossing or silently
  under-delivering.

## Context

Five files change, all under `plugins/ai_dev/skills/`. Three carry behavioural
edits, two are terminology-only alignments:

- `task/SKILL.md` — the base skill: the convention and the lens extension are
  authored here, and its two incumbent "non-goals" usages are renamed.
- `task_implement/SKILL.md` — the crossing backstop, plus its read-step and
  honor-clause term rename.
- `task_auto_check/SKILL.md` — one standing reviewer-stance bullet.
- `task_audit/SKILL.md`, `task_fix/SKILL.md` — terminology-only: rename their
  incumbent "non-goals" wording to "Out of scope" so the family reads one term.

`task_check/SKILL.md` is deliberately not in that set: its `<assessment>`
applies the base `<readiness_checklist>` "from there rather than from a copy
here", so the lens extension reaches it with no source edit, and it carries no
"non-goals" wording to rename. `task_create` likewise inherits through its
**Self-check the draft** step and needs no edit.

**Why the base skill owns the convention.** The repo's `CHARTER.md` invariant
*"Skill-family rules live in the family base skill when they govern the whole
family; front-end skills inherit those rules instead of carrying divergent
copies"* applies the moment creation, checking, auto-repair, and
implementation all consume the same boundary rules.

**Provenance and the term choice.** This ports the strict out-of-scope
discipline of the StagedSpec framework — this family's predecessor, which named
the section **Out of scope** — scaled down to backlog reality: there, a
dedicated Out of scope section was the only home for forward-looking
references, every deferred-but-buildable item was relocated to the planned file
that owns it (detail in the target, a pointer in the source), drops were never
silent, the implementer built inside the boundary and skipped outside it, and an
irreconcilable conflict was flagged rather than silently resolved. The
task-family port keeps those behaviours and drops the spec-specific machinery
(stage files, version tiers, the bidirectional target audit) that has no backlog
counterpart. "Out of scope" is chosen over the incumbent "non-goals" because it
is the accurate umbrella for both entry kinds below — a rejection and a deferral
are both out of *this* task's scope, while "non-goal" fits only the rejection —
and matches the predecessor and the repo's `## Out of Scope` guardrail-doc
section. The rules below stand alone; reading
the predecessor framework is not required to implement this task.

**What exists today and is renamed or built on, not rebuilt.** The base
`<body>` **Approach** bullet ends "plus any constraints or non-goals", and the
positive-authoring rule already grants exclusions the right to state themselves
directly ("a genuine non-goal, a guardrail"). The `<readiness_checklist>`
**Contradictions** lens checks internal consistency but never names the declared
boundary, and the **Focus** lens relocates scope creep to a sibling without any
contract that the trimmed work lands anywhere. `task_implement` already reads
"the scope / non-goals" and skips "everything the task marks a non-goal" — the
skip half of the port ships; the contradiction backstop does not. `task_audit`
reads "the scope / non-goals" and `task_fix` lists "a genuine non-goal" as
compliant framing — both are term-rename sites.

"Non-goals" is the incumbent this replaces, not a minority: roughly 15 live
tasks use it against about 3 using "out of scope", and the skills lean on it at
the five sites above. The corpus converges toward the newly-canonical "Out of
scope" through the normal update, check, and auto-repair flows; the convention
mandates no migration sweep, and the direction of drift simply reverses.

**Two-tier validation — why the linter stays out.** The family validates in two
tiers: mechanical `lint.py` for deterministic, portable format mechanics
(filename, frontmatter, status/location, datetime, size, links, collisions),
and the LLM-applied `<readiness_checklist>` for semantic body structure — even
the required Goal/Context/Approach/Acceptance sections are checklist-checked,
not linted. The Out of scope convention is semantic body structure, so it lands
in the checklist tier. A lint check would gate an *optional* sub-block while the
*required* sections stay unlinted, and normalizing a variant into the canonical
block is a content *move* outside the mechanically-fixable set — surfacing a
judgement call at every lint run, the opposite of the stay-out-of-sight goal.
Convergence belongs to `task_auto_check`'s Boundary stance, which
proposes-and-verifies the move silently.

**Disposition reuses the reconcile-or-surface rule.** A surfaced boundary
contradiction is handled by the family rule from
[the open-decision reconciliation task](task-family_reconcile-or-surface-open-decisions.md):
reconcile against the evidence when it settles which side wins, otherwise
surface with suggested options. This task supplies the detection and the form;
that rule supplies the disposition. That task should land first so the lens and
the backstop can cite its rule; if it has not, they still surface findings and
name the disposition inline.

**Co-edit coordination.** The three open siblings —
[the reconciliation task](task-family_reconcile-or-surface-open-decisions.md),
[the honor-task-dependencies task](task-family_honor-task-dependencies.md), and
[the code-interaction task](task-family_unattended-code-interaction-check.md) —
also edit `task/SKILL.md`, `task_implement/SKILL.md`, and the `task_check` /
`task_auto_check` surfaces; `task_audit` and `task_fix` here are touched by this
task alone. Whichever task lands later re-reads the shared files and anchors its
edits to the target passages by verbatim label, not position, so the changes
compose. One interaction is settled here by design: a deferral pointer marks
ownership of excluded work, never ordering, so the dependency-signal taxonomy the
honor-task-dependencies task authors reads it as a soft companion reference, not
a prerequisite.

## Approach

Edit the five `SKILL.md` files in positive, action-oriented language and their
existing pseudo-XML structure. Author the convention once in the base skill; the
siblings cite it rather than restating it. Use "Out of scope" (unhyphenated,
matching the predecessor and the guardrail-doc section) as the one term.

**Base `task` skill — author the convention once, rename its incumbents:**

1. Add a boundary-convention rule to the `<body>` rules list (the list carrying
   **State once** and its siblings), anchored by a verbatim label the
   front-ends can cite — for example **Declare exclusions as an Out of scope
   boundary.** The rule states: declaring exclusions is optional, and a task
   with nothing to exclude carries no block. When a task does declare them, they
   live in one place — a single block inside `## Approach` led by the verbatim
   bold label `**Out of scope:**` (the colon-anchored label stays greppable and
   distinct from incidental "out of scope" prose) — as one statement per
   exclusion. Each entry is one of two kinds. A **rejection** stands alone: work
   this task never does, stated directly under the positive-authoring rule's
   exclusion carve-out, optionally citing the standing rule or charter boundary
   that motivates it. A **deferral** names its owner: work recognized but pushed
   out of this task links the sibling task that owns it per the
   `<markdown_policy>` cross-link discipline, the implementable detail lives in
   that owner, and the entry stays a one-line pointer. A deferral pointer marks
   ownership, never ordering — it imposes no prerequisite on either side. Scope
   trimmed from a task at creation, update, or repair lands as a deferral naming
   its owner or as an explicit rejection — never as a silent drop. Existing
   tasks converge opportunistically as they pass through update, check, and
   auto-repair; the convention mandates no migration sweep.
2. Rewrite the `<body>` **Approach** section bullet in place so its "plus any
   constraints or non-goals" tail cites the new rule as the home of declared
   exclusions, leaving one canonical statement of where they live.
3. Rewrite the `<body>` positive-authoring carve-out in place so its "a genuine
   non-goal, a guardrail" and "a brief non-goal or guardrail stays" wording
   names the exclusion as an out-of-scope entry, keeping the sentence's meaning
   (legitimate negatives that carry their own content) while dropping the
   competing term.
4. Rewrite the `<readiness_checklist>` **Contradictions** lens entry in place to
   name the boundary case beside its existing internal-consistency scope: a
   Goal, Approach, or Acceptance element that requires, delivers, or proves work
   an Out of scope entry excludes is a contradiction finding, and an entry
   ambiguous between rejection and deferral — readable as either, so an
   implementer cannot tell whether the work is dropped or owned elsewhere — is a
   finding on the same rank. Route a confirmed finding's disposition through the
   family reconcile-or-surface rule rather than defining a new one, citing it
   per the dependency note in Context.

**`task_implement` — honor the boundary, surface the crossing, align the term:**

1. Rewrite the fourth workflow step's clause anchored at the verbatim text
   "skipping everything the task marks a non-goal" in place: rename it to skip
   everything the task marks out of scope, and extend the sentence with the
   backstop — when delivering the Goal or an Acceptance item would require
   crossing a declared boundary, surface that contradiction with the conflicting
   passages quoted, apply the reconcile-or-surface disposition, and hold rather
   than silently crossing or silently under-delivering. Rename the read step's
   "the scope / non-goals" (first workflow step) to "the scope and any Out of
   scope block" in the same pass. Anchor each edit to its verbatim text, not to
   a step number, so it composes with the co-editing siblings that renumber and
   rewrite other parts of the same workflow.

**`task_auto_check` — one standing stance:**

1. Append one bullet to the `<reviewer_stances>` standing stance set — a
   Boundary advocate citing the base `<body>` boundary-convention rule by its
   verbatim label — so a boundary finding from the gate maps to a stance
   deterministically: proposed repairs normalize a variant exclusion phrasing to
   the canonical form or reconcile a contradiction, the existing verifier keeps
   only evidence-grounded intent-preserving edits, and an unreconcilable finding
   surfaces through the existing stuck / human-routed channel. The loop
   machinery changes in no other way.

**`task_audit` and `task_fix` — terminology alignment only:**

1. Rewrite `task_audit`'s read-step "the scope / non-goals" and `task_fix`'s
   body-framing advisory "a genuine non-goal" in place so both name the
   exclusion as an out-of-scope entry, matching the base rule's term. These are
   term renames with no behavioural change — the audit still audits against the
   task's declared scope, and the `task_fix` advisory still treats a legitimate
   exclusion as compliant framing that draws no finding.

**Out of scope:**

- The body's required section set stays Goal / Context / Approach / Acceptance —
  the Out of scope block is a labeled block inside `## Approach`, not a new
  section (the Option-A shape confirmed with the user; a promoted `## Out of
  scope` section with a linter check was weighed and rejected).
- The linter and lint schema stay unchanged, for the two-tier reason in Context;
  boundary findings are checklist judgement calls, not mechanical lint.
- No migration sweep of the existing corpus — it converges opportunistically
  toward the canonical term through the normal editing flows.
- `task_check`, `task_create`, `task_explain`, `task_select`, and `task_finish`
  take no source edit: the first two inherit, the last three consume no declared
  exclusion on the path this task governs.
- The predecessor framework's multi-reviewer consensus chain stays unported —
  the family's union-of-stances-plus-verifier loop already fills that role.
- Broader eval-suite growth beyond the staged fixtures below is a separate
  session, deferred to the standing repo rule that keeps skill changes and
  harness expansion apart.

This edits shipped skill content, so the standing repo version-bump,
plugin-lockstep, and lint-clean-before-commit rules apply at commit time.

## Acceptance

- `task/SKILL.md`'s `<body>` rules list carries one boundary-convention rule
  under a verbatim-greppable label, defining: optional presence, the single
  `**Out of scope:**` block inside `## Approach` as the canonical carrier, the
  rejection and deferral entry kinds, the deferral owner-pointer contract (link
  per `<markdown_policy>`, detail lives in the owner, entry stays a one-line
  pointer, ownership never ordering), and the no-silent-drop rule for scope
  trimmed at creation, update, or repair, with opportunistic convergence and no
  migration sweep.
- The `<body>` **Approach** bullet's "plus any constraints or non-goals" tail
  and the positive-authoring carve-out's "non-goal" wording are both superseded
  in place to name the Out of scope entry, leaving one canonical term and one
  canonical statement of where declared exclusions live.
- The `<readiness_checklist>` **Contradictions** lens names the
  body-versus-boundary contradiction and the rejection/deferral-ambiguous entry
  as findings, and routes disposition through the family reconcile-or-surface
  rule — cited when that task has landed, named inline otherwise.
- `task_implement/SKILL.md`'s clause at "skipping everything the task marks a
  non-goal" is renamed to "out of scope" and extended in place with the crossing
  backstop (on a required crossing it surfaces the contradiction with the
  conflicting passages quoted and holds), and its first-step "the scope /
  non-goals" read is renamed to match; no other workflow step changes for this
  task.
- `task_auto_check/SKILL.md`'s `<reviewer_stances>` standing set carries one new
  Boundary-advocate bullet citing the base rule by its verbatim label, and the
  loop machinery is otherwise unchanged.
- `task_audit/SKILL.md` and `task_fix/SKILL.md` name the exclusion as an Out of
  scope entry where they previously said "non-goal", with no behavioural change
  to the audit contract or the `task_fix` advisory.
- `task_check/SKILL.md` is byte-identical before and after this task; a grep for
  "non-goal" across the `task_*` skills returns no remaining usage as the name
  of the exclusion concept (the family names it "Out of scope" throughout); and
  a grep confirms the convention's rule text lives only in the base skill while
  the front-ends cite its label, satisfying the `CHARTER.md` family-rule
  invariant.
- A staged fixture task whose Acceptance proves work its own `**Out of scope:**`
  block excludes is reported by `task_check` with the contradiction as a
  numbered issue, and `task_auto_check` either applies a verifier-approved
  minimum repair or surfaces the task as stuck with options.
- Running `task_implement` against a staged fixture task whose Approach requires
  crossing a declared boundary surfaces the contradiction and holds before the
  crossing edit; against a staged task whose boundary and body agree, it
  proceeds with no boundary interruption.
- A staged fixture task carrying no Out of scope block raises no boundary
  finding at check time, confirming presence stays optional and the convention
  invisible when there is nothing to exclude.
- A staged `task_create` run that trims scope while authoring lands the trimmed
  work as a deferral naming its owner or an explicit rejection in the written
  file's `**Out of scope:**` block, with no prompt added beyond the existing
  create flow.
