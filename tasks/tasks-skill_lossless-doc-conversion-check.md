---
description: Add a built-in lossless-conversion step to the create workflow so splitting an existing document into tasks verifies no unit of meaning was dropped, without the user having to ask.
scope: plugins/ai_dev/skills/task
created: 2026-05-28T19:49:23
updated: 2026-05-28T21:05:01
status: open
---

# Verify lossless conversion when splitting an existing doc into tasks

## Goal

When the create flow ingests an **existing document** (a `todo.md`, a spec, a
notes file) and splits it into multiple task files, the skill should verify on
its own that every unit of meaning in the source landed in at least one task —
before offering to drop the source. Today nothing in the workflow does this, so
the quality depends on the user noticing and asking for a re-check.

Building the check in is a turns/tokens win: a real `todo.md`→tasks session
shipped a "done" set, the user had to explicitly ask "double check no
information got lost," and the resulting audit found **four** real drops. That
is a whole extra round-trip the skill should have closed itself.

## Context

The relevant flow is the `<create>` workflow in `SKILL.md` (and its
`<batch_creation>` step). It covers writing atomic task files from fresh intent
but has no notion of *deriving* tasks from a pre-existing source document, and
no fidelity gate for that case. The single-source-of-truth and "write for a
single-shot implementer" pitfalls assume content originates in chat, not in a
file being decomposed.

This task generalizes several source-specific drops seen in practice (a shared
top-of-file preamble vanishing, a rationale clause and a list item dropped, a
carve-out silently widened) into one reusable rule rather than encoding each as
its own fix.

## Approach

Add a short sub-step to the `<create>` workflow (or a sibling `<convert>` block
referenced from it) that fires **when the task set is derived from an existing
document**. It states a lossless-conversion contract:

- **Every unit of meaning in the source maps to at least one task.** Rewriting,
  merging, expanding, or restructuring source content is fine; dropping meaning
  is not.
- **Source-wide content propagates, it does not evaporate.** Content that scopes
  the *whole* source rather than one section (a shared preamble, a global
  caveat) must be carried into each derived task that it governs, not left
  behind in the source.
- **Run a coverage pass before declaring done.** Walk the source unit by unit
  (section, bullet, rule) and confirm each is represented; report rewrites,
  merges, and intentional expansions explicitly, and surface anything not yet
  covered for the user to decide.
- **Confirm the source's disposition only after coverage is verified.** Do not
  delete or move the source document until the coverage pass is clean and the
  user has chosen what happens to it.

Keep it positive and action-oriented per repo authoring conventions, and keep it
proportional — this is a few sentences of policy in the workflow, not a new
heavyweight procedure. Make clear it applies to the *derive-from-a-document*
case, not to ordinary from-chat task creation.

Non-goal: no script enforces "no meaning lost" — semantic coverage is a
behavioural check the agent performs, not something `lint.py` can mechanically
verify. Do not add a lint rule for it.

## Acceptance

- `SKILL.md` describes the lossless-conversion contract for the
  derive-from-an-existing-document case, including source-wide-content
  propagation, the unit-by-unit coverage pass, and confirming source disposition
  only after coverage is clean.
- The policy is written to fire without the user prompting for it.
- Covered by an eval in `tests/tasks/evals/`: given a multi-section source doc
  with a shared preamble, the agent produces tasks that preserve every section's
  meaning, carries the preamble into each governed task, and reports coverage
  before offering to drop the source. Grow the eval suite in its own commit per
  repo convention.
- `make lint` stays clean (prose-only change).
