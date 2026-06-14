---
description: Add a rule to the task skills that task file bodies read as what to do (positive, action-oriented), with negatives kept for genuine non-goals or deferred scope.
scope: "task_* family skills"
created: 2026-06-02T19:16:33
updated: 2026-06-10T20:50:09
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Make positive, action-oriented task bodies a rule in the task skills

## Goal

Codify, in the base `task` skill, that a task file body reads as **what the
work should do**, with its primary carrier positive and action-oriented — the
same `ai_instruction_writing` principle the repo already applies to skill
prose, now applied to the task files the skill produces. After this change,
every create path writes bodies that lead with the action (inherited from the
base rule), and `task_fix` surfaces bodies that violate it, auto-reframing
only the mechanical cases. Negatives stay welcome where they earn their
place: a `## Non-goals` section, deferred/explored-alternatives notes,
guardrails, and acceptance checks that name an expected state.

## Context

The rule lives in the base `task` skill, the single source of truth the front
ends defer to. Files in play, all under `plugins/ai_dev/skills/`:

- `task/SKILL.md` — `<body>` defines the Goal / Context / Approach /
  Acceptance sections. This is where the authoring rule lands, and the only
  file that needs an edit for the rule itself.
- `task_create/SKILL.md` — already consumes `<body>` through its
  `<authority>` section, so it inherits the rule with no diff of its own.
- `task_fix/SKILL.md` — the whole-tree repair pass gains the body-framing
  check described in the Approach.

The rubric to reuse is `plugins/ai_dev/skills/ai_instruction_writing/SKILL.md`
(`<core_rule>`, `<self_check>`): lead with the positive carrier; keep a
negative only when it names a long tail no positive could enumerate. For a
task body the catch-all equivalents are the legitimate negative homes listed
in the Goal.

Motivating example: the `tasks/deployment_relocate-state-to-home.md` body was
first written around "two problems" and "non-goals / what this does not do,"
then reworked to lead with the actions ("Handle the two files according to
what each one is", a "Guardrails" section, deferred alternatives kept brief).
That rewrite is the behavior this rule should make routine.

Ordering and neighbours:

- [task-skill_shared-readiness-checklist.md](task-skill_shared-readiness-checklist.md)
  follows this task: its relocated negation-framed-behaviour item then points
  at the rule this task lands instead of restating it — implement this task
  first.
- The [family-wide prose sweep](task-skill_ai-instruction-writing-sweep.md)
  reframes SKILL.md prose itself and changes no skill behavior; this task
  instead adds an authoring rule the skills enforce on their output.

## Approach

- In `task/SKILL.md` `<body>`, add a short authoring rule: a task body's
  primary carrier is positive and action-oriented — Goal, Approach, and
  Acceptance lead with what the work does and what "done" looks like. Keep
  negatives for genuine non-goals, deferred or explored-alternatives notes,
  guardrails, and acceptance checks that assert an expected state. Phrase it
  positively and keep it consistent with the `ai_instruction_writing`
  `<self_check>`.
- `task_create` inherits the rule through `<authority>` — it already applies
  `<body>` when writing, so this task makes no edit there.
- In `task_fix/SKILL.md`, add a body-framing check to the repair pass with
  one deliverable, stated here once: **task_fix surfaces every body whose
  load-bearing content is carried mainly by negatives, and reframes a finding
  itself only when the rewrite is mechanical and meaning-preserving (a direct
  inversion with no judgement call); every other finding stays a surfaced
  judgement call for the user.** A legitimate non-goals or deferred section
  is compliant and draws no finding.

Keep the rule a prose authoring convention. A mechanical lint rule for
negation in `lint.py` stays out of scope — the same line the sweep task
draws — because negative-vs-positive framing needs judgement the linter
cannot apply.

## Acceptance

- `task/SKILL.md` `<body>` states the positive, action-oriented body rule,
  with the legitimate negative homes (non-goals, deferred notes, guardrails,
  expected-state acceptance) named as compliant.- `task_fix/SKILL.md` carries the body-framing check exactly as stated in the
  Approach: surface always, auto-reframe only the mechanical cases.
- The rule reads as positive guidance and passes the `ai_instruction_writing`
  `<self_check>` itself.
