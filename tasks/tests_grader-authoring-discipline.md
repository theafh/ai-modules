---
description: Make eval graders assert substance over surface form and split long conjunctions, with the durable rule in the versioned repo instructions and the mechanics in the tests tree.
scope: "local test harnesses"
created: 2026-08-15T14:08:10
updated: 2026-09-05T02:34:23
status: open
reported-by: Andreas Hoffmann
---

# Grader-authoring discipline for the local eval harnesses

## Goal

An eval grader fails only when the behaviour under test is genuinely wrong. The
rules that make that true are written where a future author reads them: the
durable authoring rule lands in the repo's own versioned instructions, and the
harness mechanics land in the tests tree beside the runners they govern. A grader
written against these rules distinguishes a real regression from a correct answer
phrased differently, and a failing eval names which behaviour broke rather than
only that something did.

Four rules carry the work:

- **Assert substance, not surface form.** A check names the property that must
  hold, and passes on every phrasing and placement that satisfies it. Where a
  rubric permits two repair shapes, the check accepts both.
- **Anchor a structured match to its subject.** A check reading a structured
  report field matches the record whose subject is the item under test, since a
  bare name match also hits that name inside another record's prose.
- **Read prose with wraps collapsed.** A check matching more than one word reads
  the text with hard wraps removed, since a wrap falling mid-phrase makes a
  line-based match miss text that is present.
- **Split a long conjunction.** An eval asserting many independent behaviours
  reports per-behaviour results, so one slip localises instead of failing the
  whole eval and hiding what still holds.

## Context

The rules come from building the behavioural evals for
[the backlog-coherence pass](archive/task-family_backlog-coherence-pass.md), where
grader defects outnumbered product defects and cost more runs than the feature
did. Five distinct grader bugs surfaced there, each of the shapes above: checks
that demanded one side of a valid two-sided repair, one that required a full
enumeration where the repo's own count-stable rule prefers a selector, one that
matched a task name inside a neighbouring record's evidence text, and one that
missed a phrase split across a hard wrap. Every one of them reported a working
behaviour as broken.

The conjunction rule comes from the same measurement. One eval carried its whole
scenario as a single pass/fail over many independent checks; individual checks
passed nearly always while the eval as a whole rarely did, and each run failed on
a different check. That signature reads as instability in the thing under test
when it is arithmetic.

Placement matters because of how each file is read. The repo's standing
instructions load at inference time, so an agent authoring a new grader meets the
rule there without going looking. The tests tree is committed and reaches every
clone, but it is not auto-loaded, so a file under it is read only by someone
already working on the harness. The durable authoring rule therefore lands in the
versioned standing instructions, where the next grader author encounters it, while
the tests tree keeps the runner-specific mechanics beside the runners they
govern.

A second surface carries the same defect, measured on 2026-09-05 while running
this repo's eval sweep. The `task_create` eval grader checks an "Open decision:"
label by matching needles over the label window, and across five recorded runs of
its two labelled evals every failure but one landed on a needle rather than on a
missing part of the label. One run's label carried its why-open clause as "This
is the user's call ...; the evidence base does not settle it" and failed the
why-open check, whose needle list matches "left for the user" and "user-owned"
but neither of those phrasings. Two other runs enumerated two options as
`**Option A ...**` / `**Option B ...**` bullets and as `(a) ... (b) ...` and
failed the two-options check. The label-presence check has the same shape: it counts the
literal string `Open decision:`, so a run on 2026-09-05 whose body carried
`**Open decision (guardrail-bound):**` scored zero labels and failed as though
the agent had never surfaced the fork, when it had surfaced it and named the
ground the governing rule asks for. The grader's own comments concede the
tradeoff, saying a conformant clause phrased without either subject marker would
false-fail. The effect is that these evals report roughly a one-in-five pass rate
that reads as an unstable skill and is mostly grader arithmetic, which is the
same signature the conjunction rule above describes.

[The wiki front-end eval task](tests_wiki-front-end-behavior-evals.md) is the
first consumer: it authors three harnesses from scratch and already carries the
per-scenario-verdict and deterministic-grading requirements these rules
generalise, so it is the natural place the rules are first applied rather than a
second statement of them.

## Approach

1. **State the durable rule in the versioned repo instructions.** Extend the
   regression-test harness section of the repo's standing instruction file with
   the four rules above, phrased as authoring requirements for a new grader.
   Keep them short enough to sit beside the existing harness conventions rather
   than displacing them.
2. **State the mechanics in the tests tree.** Record the harness-level detail
   where the runners live: the shared helper for wrap-collapsed matching, the
   subject-anchored form for structured-field checks, and the per-behaviour
   reporting shape. Point back at the versioned rule rather than restating it.
3. **Apply the rules to the graders with known instances.** Walk the checks in
   the task-family eval grader and in the `task_create` eval grader and bring
   each to the rules, since those two are the surfaces the rules were derived
   from and the ones carrying measured instances. In the `task_create` grader
   that means re-deriving the label-structure needles from the label forms the
   skill actually produces, so each check names the part of the label that must
   be present and passes on every phrasing and enumeration form that carries it.

**Out of scope:**

- Consolidating or relocating any harness directory, which
  [the harness consolidation task](archive/task-family_test-harness-consolidation.md)
  owns.
- Changing the trigger-eval runner or its harness, a separate surface this task
  does not touch.
- Authoring new scenarios or new coverage; this task changes how existing checks
  assert, not what is covered.

## Acceptance

1. The regression-test harness section of the repo's versioned standing
   instruction file states all four rules as grader-authoring requirements.
2. The tests tree records the mechanics for each rule and cites the versioned
   statement rather than repeating it, so the two do not drift.
3. The task-family and `task_create` eval graders each have a wrap-collapsing
   helper available to every check that matches more than one word, and each
   such check uses it.
4. Every structured-report-field check in those graders matches its record by
   subject, so a name appearing inside another record's prose cannot satisfy or
   defeat it.
5. Each check that encodes a repair shape accepts every shape the governing
   rubric permits, demonstrated by a check that passes on two different valid
   repairs of one planted defect and still fails when neither is present.
6. The longest eval in those graders reports per-behaviour results rather than one
   pass/fail over the whole set, so a run naming a single failed behaviour also
   shows which others held.
7. Each label-structure check in the `task_create` grader passes on the label
   forms already recorded under its run workspace, covering a why-open clause
   written about the evidence rather than about the fork, options enumerated as
   bold `Option A` / `Option B` bullets and as `(a)` / `(b)` inline
   alternatives, and a label whose lead-in qualifies the phrase, as in
   `**Open decision (guardrail-bound):**`. The label-presence check still
   reports zero labels for a body that surfaces no decision at all, so widening
   it costs no detection.
8. A recorded run of the task-family evals after the changes reports, per eval,
   which behaviours passed and which failed; the recorded result is the
   deliverable, and a behaviour that still fails is recorded with its reason
   rather than removed from the set.
