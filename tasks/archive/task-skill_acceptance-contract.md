---
description: "Extend the base skill's Acceptance definition into a contract: deliverable items flip false-to-true and check mechanically; stochastic work records measurements with a fail branch."
scope: plugins/ai_dev/skills/task
created: 2026-06-09T12:29:51
updated: 2026-06-10T20:50:09
status: implemented
---

# Acceptance contract: items flip false to true and check mechanically

## Goal

The base `task` skill's `<body>` defines `## Acceptance` as a contract, so
every create path writes acceptance items an implementer can verify
mechanically and an audit can walk: deliverable items are false today and
flipped true by the work; generic project gates stay out, with a gate named
only when the task changes its outcome; every item is verifiable by the
implementer alone; empirical work is measured by a named protocol with the
recorded measurement as the deliverable and a stated branch for a failed
hypothesis; enumerated lists are the preferred shape.

## Context

- The current definition in `task/SKILL.md` `<body>` reads: "**Acceptance** —
  concrete checks that say the task is done (tests to pass, behaviour to
  verify, lint to come back clean)". It names concreteness but leaves item
  quality open — and its "lint to come back clean" example seeds generic
  gate items into every task written from it.
- Evidence from transcript analysis of ~24 `task_check` runs (2026-05/06):
  unverifiable acceptance was the single largest issue class — nine instances
  of items a one-shot implementer cannot verify, including soft targets
  ("rises clearly above" a sampled metric), hoped-for outcomes baked in as
  pass/fail gates with no branch for a failed prediction, and open-ended
  iterate-until-green against stochastic oracles. The user-gated `make
  deploy` step leaked into acceptance in four checks. "Acceptance already
  satisfied today" produced divergent-diff ambiguity twice. An enumerated
  acceptance list was the only thing that caught two real implementation gaps
  at audit, and the one failed implementation (eval regression, fully
  reverted) was recoverable precisely because its acceptance was measurable.
- Generic gate items are also a cost multiplier (decided 2026-06-10):
  `task_implement` runs every acceptance item, `task_audit` re-runs each
  independently, and a grounded `task_check` verifies them again — so a
  content-independent `make lint` / dry-run item executes three times per
  task lifecycle, while the project's standing instructions already run
  those gates at their standing moments (commit time, the skills' own
  workflow steps).
- This is a base-only edit: the create paths apply `<body>` when writing,
  `task_check` judges against it, and `task_audit` walks the items — all
  through existing authority, with no sibling SKILL.md changes.
- Ordering: builds on
  [task-skill_positive-task-body-rule.md](task-skill_positive-task-body-rule.md)
  — implement that task first. Its rule names "acceptance checks that assert
  an expected state" as a legitimate negative home; this contract defines the
  task-specific gate as the one expected-state item kind, so the gate clause
  becomes the single definition and the positive-body rule's mention points
  at it instead of wording it a second time.

## Approach

- Rewrite the `## Acceptance` bullet in `task/SKILL.md` `<body>` into a short
  contract with five clauses:
  1. **Deliverable items flip:** false today, true after the work, each
     verifiable mechanically — a command to run, a file state to inspect, a
     behaviour to observe.
  2. **Task-specific gates only:** every item's outcome changes with this
     task's work. Generic project gates — `make lint`, a deploy dry-run, the
     full test suite — stay out of acceptance: the project's standing
     instructions own them and they run at their standing moments. Name a
     gate only when the task changes what it verifies, such as a new lint
     rule proven on a staged fixture or a new scenario added to a suite.
  3. **Implementer-runnable:** every item verifies through steps the
     implementer runs alone; actions the project's standing instructions gate
     on the user stay out of acceptance.
  4. **Measured, with a fail branch:** stochastic or empirical work names its
     measurement protocol — run count, fixed denominator, baseline — and the
     recorded measurement is the deliverable; the item states what happens
     when the hypothesis fails instead of gating on the hoped-for direction.
  5. **Enumerate:** prefer a list of independently verifiable items over one
     compound check.
- Replace the bullet's example text: "(tests to pass, behaviour to verify,
  lint to come back clean)" gives way to task-specific examples — a staged
  fixture the new behaviour is proven on, a file state to inspect, a
  measurement to record.
- Keep the contract at authoring-rule altitude: general clauses, with
  specific cases as illustrations.
- Reconcile the positive-body rule's expected-state mention (same file) to
  point at the gate clause, keeping one wording.

## Acceptance

- The `## Acceptance` definition in `task/SKILL.md` `<body>` carries the five
  contract clauses: deliverable flip, task-specific gates only,
  implementer-runnable, measurement protocol with fail branch, enumerated
  preference.
- The section-definition example names task-specific checks; "lint to come
  back clean" no longer appears as the example.
- Expected-state gating is defined exactly once in `task/SKILL.md`, in the
  gate clause, with the positive-body rule's mention pointing at it.
