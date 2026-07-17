---
description: "Settle incident-shaped requests' altitude at gather: point-fix or behaviour definition, decided from evidence with point-fix default, recorded in the Goal, surfaced to the user."
scope: plugins/ai_dev/skills/task
created: 2026-06-09T14:03:33
updated: 2026-06-10T20:50:09
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Gather altitude probe: point-fix or behaviour definition, decided at capture

## Goal

Incident-shaped requests — a failure case, an error, a "when X happens it
breaks" — get their altitude settled at capture time: the gather step decides
from evidence whether the deliverable is the point-fix for the reported case
or the general behaviour whose absence caused it, defaults to the point-fix,
records the choice in the task's `## Goal`, and surfaces it with the create
report's assumptions. The flow stays question-free: same turns, same one-shot
create, with the altitude visible for correction in the user's reply instead
of in a pre-implementation rewrite after the incident context has gone cold.

## Context

- Motivating pattern: tasks filed from incidents at point-fix altitude
  repeatedly turned out to mean a behaviour definition, and the mismatch
  surfaced only at implementation time as a substantial rewrite. One
  illustration: the archived wiki-discovery task was filed as a
  working-directory edge-case fix and rewritten into a detection-predicate
  design just before shipping. Deciding and recording the altitude at capture
  moves that correction to the cheapest moment — the create report.
- Edit site: the base `task` skill's `<gather>` step inside `<create>`. The
  existing "ask one sharp clarifying question" sentence stays untouched —
  this rule adds a decision, never a question.
- Delivery: `task_create` inherits `<gather>` through its `<authority>`, and
  its output contract already surfaces scope assumptions — the altitude rides
  that existing reporting path.

## Approach

- Add the altitude rule to `<gather>`: for an incident-shaped request, decide
  from the request and the surrounding code whether the task delivers the
  point-fix or the general behaviour; default to the point-fix when the
  evidence supports nothing more.
- Record the decision as an explicit clause in the task's `## Goal` — the
  point-fix for the named case, or the behaviour definition with the incident
  as its motivating case.
- Name the altitude among the assumptions the create report surfaces, riding
  the existing surface-assumptions language rather than adding a reporting
  mechanism.

## Acceptance

- Base `<gather>` carries the incident-altitude rule: evidence-based
  decision, point-fix default, recorded in the `## Goal`.
- The rule names the create report's assumption surfacing as the correction
  path.
- The clarifying-question sentence in `<gather>` remains unchanged by this
  task's edit.
