---
description: Make the close-out ARCHITECTURE.md refresh executable: drop task_finish's divergent step list, add a report slot, carry the design signal upstream-to-finish, and define the trigger test.
scope: plugins/ai_dev
created: 2026-08-05T19:29:15
updated: 2026-08-05T19:39:41
status: open
reported-by: Andreas Hoffmann
---

# Make the close-out ARCHITECTURE.md refresh executable and observable

## Goal

The family assigns one guardrail-doc write to close-out: refresh `ARCHITECTURE.md`
when the finished work extended the system's design. That rule ships today and is
not reliably executable — the front-end skill that owns the write presents a
step list that omits it, has nowhere in its report to mention it, obtains no
signal from the stages that read the code, and applies a trigger with no test.
The likely real-world outcome is that the step never fires and nobody notices,
because no stage reports on it either way.

After this work the refresh is executable and observable end to end: `task_finish`
inherits the close-out steps as one list rather than a diverging copy, reports
what it did about `ARCHITECTURE.md` in every case, receives the design-extension
signal from the stage that actually read the code instead of re-deriving a
code-level judgement from a task file, and applies a stated test for whether the
work extended the design. An operator closing a task can tell from the report
whether the doc was refreshed, deliberately left alone, or absent.

## Context

- The rule has two statements in the base `task` skill, and both stay the single
  source the front ends inherit: the `<standing_doc_consumption>` sentence
  "`ARCHITECTURE.md` is refreshed during finish when completed work extends the
  design", and the `<archive>` workflow's fifth step, opening "When closing as
  `finished`, `ARCHITECTURE.md` exists at the project root, and the completed work
  extended the system's design".
- [The standing-doc framework task](archive/task-family_optional-standing-doc-conventions.md)
  shipped that rule, placing it in the archive pass and describing
  `ARCHITECTURE.md` as the descriptive tier of the drift-prevention spectrum. This
  task repairs the operability of what that task established and changes none of
  its intent: the doc stays optional, presence-gated, and descriptive.
- **The divergent copy.** `task_finish`'s `<workflow>` step "**Run the base
  skill's `<archive>` close-out.**" re-states the archive steps inline — "set
  `status`, bump `updated` from `date`, `git mv` the file to `archive/`", then
  cross-references, then re-lint. That is five of the six steps the base
  `<archive>` introduces with "run all six steps"; the `ARCHITECTURE.md` step is
  the one absent. The same sentence carries both "end to end" and "Those rules
  live in the base skill; follow them there rather than restating them here", so
  it restates while disclaiming restatement, and the step it drops is the only one
  that is not a mechanical file operation — the one that most needed the prompt.
- **No report slot.** `task_finish`'s `<output_contract>` requires the archived
  path, the status, the re-pointed cross-references, a clean linter result, and any
  reliance on an `audited` stamp. A guardrail-doc edit has no slot, so it would be
  made silently while a far more mechanical cross-reference rewrite is mandated
  reading. The omission is unobservable in both directions: a finish report cannot
  distinguish "refreshed", "considered and declined", and "never looked".
- **No hand-off carrier.** The write sits at the stage with the least code
  context. `task_implement`'s "**Update docs and versions.**" step is scoped to
  "whatever documentation the task names", and a task rarely names
  `ARCHITECTURE.md`, so the write is outside implement's remit by construction.
  `task_audit` reads the built code most thoroughly of any stage at
  "**Understand what is actually built.**", and is read-only with a verdict-plus-gap
  output contract — a design-extension observation is not a gap against the task's
  acceptance, so it has no structured channel and no mention of the doc anywhere.
  `task_finish` reads the task file, and on an `audited` task its
  "**Verify before a `finished` close when needed.**" step closes without reading
  the code at all, then has to judge whether the work extended the design.
- [The trust-the-stamp task](archive/task-family_finish-trusts-audited-status.md)
  introduced that shortcut, and it is right for verification: the audit is standing
  evidence. It is the wrong instrument for authoring, because a prior run cannot
  stand in for an artifact it never produced. The charter invariant opening "An
  autonomous component keeps its audit, detection, and coverage scope intact when
  it optimizes for cost or speed" is the authority for closing this: a cheaper path
  that narrows what a step can see surfaces the tradeoff rather than taking it
  silently.
- **No trigger test.** "the completed work extended the system's design" has no
  applicable test. The base `<family>` sentence "`ARCHITECTURE.md` describes goals,
  stack, and design decisions; it is distinct from the charter's falsifiable
  boundary role and from any status-board, stage-index, or build-order view" is a
  scope definition, not a trigger. The motivating case: a startup reachability
  probe added to both entry modes of a scheduler is arguably a new pre-dispatch
  design step and arguably an operational behaviour belonging in an operator
  procedure, and nothing in the family settles which.
- The charter invariant "Skill-family rules live in the family base skill when they
  govern the whole family; front-end skills inherit those rules instead of carrying
  divergent copies" governs the first fix, and the standing repo rule on authoring
  a skill-family rule once in the family's base skill says the same at the harness
  baseline. [The shared readiness checklist](archive/task-family_shared-readiness-checklist.md)
  is the precedent for the shape: one canonical statement in the base, siblings
  assessing by reference rather than by copy.
- [The autonomous implement-to-done loop](task-family_autonomous-implement-loop.md)
  orchestrates `task_implement` → `task_audit` → `task_finish` and reuses them by
  citation, so whatever carrier this task defines is what that loop passes along.
  Neither task blocks the other; the loop inherits the hand-off if this lands
  first, and adopts it by citation if it lands first.

## Approach

**1. End the divergent step list.** Rewrite `task_finish`'s `<workflow>` step
"**Run the base skill's `<archive>` close-out.**" so it points at the base
`<archive>` as the one list and stops enumerating its steps, keeping the
inheritance the charter invariant requires. Where the step needs emphasis, name
what the close-out must not skip by pointing at the base step rather than by
reproducing the sequence.

**2. Give the refresh a report slot.** Extend `task_finish`'s `<output_contract>`
so the `ARCHITECTURE.md` disposition is reported in every case: refreshed, with
what changed; considered and declined, with the reason; or the doc absent. This
makes the step's execution observable, which is what lets a reader tell a
deliberate decline from a silent skip.

**3. Carry the design signal from the stage that read the code.** `task_implement`
carries the detection mandate: when the work lands, it assesses whether that work
extended the design, judged by the test fix 4 defines, and records the assessment
in the task file. Implement is the recording stage because it already writes the
task's frontmatter at exactly that moment and is the stage that knows what it
built, and the task file is the carrier because it is the one artifact
`task_finish` always reads and the only one that survives a session boundary.
Recording the assessment is a mandate of its own rather than a case of
`task_implement`'s existing "**Update docs and versions.**" step, which stays
scoped to the documentation a task names. `task_audit` confirms the record is
present and matches the built work as part of the walk it already performs, which
keeps the assessment verified without making audit originate it — a directly
finished task that never passed through audit still carries implement's record.
Then extend `task_finish`'s "**Verify before a `finished` close when needed.**"
step so its trust-the-stamp path names how it obtains the signal: reading that
recorded assessment, rather than re-reading the code the shortcut deliberately
skips.

**4. Define the trigger test.** State in the base skill, beside the `<archive>`
step that carries the rule, a test an implementer can apply to "extended the
system's design", building on the existing `<family>` scope sentence rather than
restating it: what kind of change earns a refresh, and what belongs instead in the
project's own docs, a procedure page, or nothing. Keep the two statements of the
rule — `<standing_doc_consumption>` and the `<archive>` step — in agreement about
who detects, who records, and who writes.

**Out of scope:**

- Making `ARCHITECTURE.md` required, or adding one to this repository. The doc
  stays optional and presence-gated, as the standing-doc framework defines it.
- Re-adding a code read to `task_finish`'s trust-the-stamp path. The gate stays as
  it is, and fix 3 supplies the signal it lacks instead.
- An equivalent write path for the `FEATURES.md` behaviour ledger. This task
  repairs the one guardrail-doc write the family already assigns.

## Acceptance

- `task_finish`'s `<workflow>` close-out step carries no copy of the archive
  sequence: the verbatim fragment "set `status`, bump `updated` from `date`,
  `git mv` the file to `archive/`" no longer appears in its `SKILL.md`, and the
  step resolves the close-out through the base `<archive>` alone.
- `task_finish`'s `<output_contract>` names the `ARCHITECTURE.md` disposition as a
  reported outcome and covers all three states — refreshed with what changed,
  considered and declined with the reason, and doc absent.
- The base skill states an applicable test for "extended the system's design"
  beside the `<archive>` step that carries the rule, and the existing `<family>`
  scope sentence remains the only statement of what the doc is, un-duplicated.
- `task_implement`'s workflow carries the design-extension assessment as a mandate
  of its own, distinct from its "**Update docs and versions.**" step, and records
  that assessment in the task file when the work lands.
- `task_audit`'s walk confirms the record is present and consistent with the built
  work without becoming the stage that originates it, so a task closed as
  `finished` without passing through audit still carries implement's record.
- `task_finish`'s trust-the-stamp path names reading that record as how it obtains
  the design signal, so no stage is asked to judge a code-level question with
  neither code nor record in hand.
- The two base statements of the rule, `<standing_doc_consumption>` and the
  `<archive>` step, agree on who detects, who records, and who writes, with each
  fact stated once.
- Walked on a staged fixture project carrying an `ARCHITECTURE.md`: closing a task
  whose record says the work extended the design produces both a doc edit and the
  matching report line, and closing one whose record says it did not produces the
  declined line with its reason and leaves the doc byte-identical.
- Walked on a staged fixture project with no `ARCHITECTURE.md`: the close-out runs
  unchanged and reports the absent state, so the presence gate still makes the doc
  optional.
