---
description: Add a rule to the task skills that task file bodies read as what to do (positive, action-oriented), with negatives kept for genuine non-goals or deferred scope.
scope: "task_* family skills"
created: 2026-06-02T19:16:33
updated: 2026-06-02T21:12:48
status: open
---

# Make positive, action-oriented task bodies a rule in the task skills

## Goal

Codify, in the task skills, that a task file body reads as **what the work
should do**, with its primary carrier positive and action-oriented — the same
`ai_instruction_writing` principle the repo already applies to skill prose, now
applied to the task files the skill produces. After this change, `task_create`
writes bodies that lead with the action, and `task_fix` flags a body whose
load-bearing content is carried mainly by negatives so it can be reframed.
Negatives stay welcome where they earn their place: a `## Non-goals` section,
deferred/explored-alternatives notes, guardrails, and acceptance checks that name
an expected state.

## Context

The rule lives most naturally in the base `task` skill, which is the single
source of truth the front ends defer to (`task_create` and `task_fix` both cite
`task`'s `SKILL.md` as authority). Files in play, all under
`plugins/ai_dev/skills/`:

- `task/SKILL.md` — `<body>` (lines ~100–109) defines the Goal / Context /
  Approach / Acceptance sections. This is where the authoring rule belongs.
- `task_create/SKILL.md` — `<authority>` already points at `task`'s `<body>`;
  its `<workflow>` "Write" step is where the rule applies on creation.
- `task_fix/SKILL.md` — the whole-tree repair pass; this is where a body-framing
  finding gets surfaced or repaired.

The rubric to reuse is `plugins/ai_dev/skills/ai_instruction_writing/SKILL.md`
(`<core_rule>`, `<self_check>`): lead with the positive carrier; keep a negative
only when it names a long tail no positive could enumerate. For a task body the
catch-all equivalents are the legitimate negative homes listed in the Goal.

Motivating example: the `tasks/deployment_relocate-state-to-home.md` body was
first written around "two problems" and "non-goals / what this does not do," then
reworked to lead with the actions ("Handle the two files according to what each
one is", a "Guardrails" section, deferred alternatives kept brief). That rewrite
is the behavior this rule should make routine.

This is the body-authoring **rule addition**. It is distinct from
[the family-wide prose sweep](task-skill_ai-instruction-writing-sweep.md), which
reframes negative-only instructions inside the SKILL.md files themselves and
explicitly changes no skill behavior. This task instead adds a new authoring rule
the skills enforce on their output — a behavioral change.

## Approach

Apply the rule at the source of truth, then reference it from the front ends:

- In `task/SKILL.md` `<body>`, add a short authoring rule: a task body's primary
  carrier is positive and action-oriented — Goal, Approach, and Acceptance lead
  with what the work does and what "done" looks like. Keep negatives for genuine
  non-goals, deferred or explored-alternatives notes, guardrails, and
  acceptance checks that assert an expected state. Phrase it positively and keep
  it consistent with the `ai_instruction_writing` `<self_check>`.
- In `task_create/SKILL.md`, make the "Write" step apply this rule when filling
  the body, deferring to `task`'s `<body>` as authority rather than restating the
  rule in full.
- In `task_fix/SKILL.md`, add a body-framing check to the repair pass: a task
  whose load-bearing body is carried mainly by negatives is surfaced (and
  reframed where the fix is mechanical), treating a legitimate non-goals or
  deferred section as compliant.

Keep the rule a prose authoring convention. A mechanical lint rule for negation
in `lint.py` stays out of scope — the same line the sweep task draws — because
negative-vs-positive framing needs judgement the linter cannot apply.

## Acceptance

- `task/SKILL.md` `<body>` states the positive, action-oriented body rule, with
  the legitimate negative homes (non-goals, deferred notes, guardrails,
  expected-state acceptance) named as compliant.
- `task_create/SKILL.md` applies the rule on write by deferring to `task`'s
  `<body>`; `task_fix/SKILL.md` surfaces or repairs a body framed mainly by
  negatives.
- The rule reads as positive guidance and passes the `ai_instruction_writing`
  `<self_check>` itself.
- `make lint` and `./deployment/deployment.sh --global --dry-run` pass.
