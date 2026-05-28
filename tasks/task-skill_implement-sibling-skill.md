---
description: Add a `task_implement` sibling skill that implements one task file end-to-end (code, tests, verification) via a strict read-understand-implement-verify flow, adapted from spec_implement.
scope: plugins/ai_dev
created: 2026-05-28T20:25:06
updated: 2026-05-28T21:28:43
status: open
---

# Add the `task_implement` sibling skill

## Goal

A skill that takes one task file and carries it all the way to done:
reads and fully understands the task, loads the project's guardrails, builds
on the existing codebase, implements the code, writes the tests, runs the
full suite until clean, and confirms every `## Acceptance` item holds. It is
the "do this task now, properly" counterpart to `task_create` (which only
writes the file) — turning the single-shot-implementable task body that the
base skill is designed to produce into actual shipped work.

## Context

Depends on [the rename](archive/task-skill_rename-tasks-to-task.md). The template
is `staged-spec/skills/spec_implement/SKILL.md` — the "Spec Implementer" —
whose strict ordered workflow is the thing worth porting, not just the
one-line "read-understand-implement-verify" summary. Its actual steps,
mapped from a `/specs` stage to a single `tasks/<scope>_<name>.md` file:

- **Read the task thoroughly before writing code** — desired behaviour,
  approach, context pointers, and scope/non-goals. The base `task` skill
  writes bodies "so a single-shot AI coder could pick it up with no further
  context", which is exactly spec_implement's input contract.
- **Load the guardrails.** spec_implement reads `specs/security.md` and
  `specs/testing.md` and holds them as project-wide defaults. The task-repo
  analogue: read the governing `CLAUDE.md` (root + repo + nearest) for
  conventions that shape every edit — pseudo-XML + positive-language
  authoring, Make+shell+markdown toolchain, snake_case naming,
  deployment-agnostic cross-references, the versioning/lockstep rules — plus
  any constraints the task's own `## Approach` states.
- **Understand the existing codebase.** Read the code and tests already in
  place; extend the patterns, conventions, and architecture in use rather
  than inventing new shapes.
- **Implement in order, respect the scope boundary.** Follow `## Approach`
  step by step; build everything in scope, skip everything the task marks a
  non-goal.
- **Name artifacts after behaviour.** Files, functions, tests read as what
  they deliver — matching the repo's existing naming, not task labels.
- **Tests are required deliverables.** Map each acceptance check that
  implies a test to a real test; align level/framework/structure with the
  repo's testing conventions (e.g. the `tests/<skill>/` Pattern A layout).
- **Cross-check, then run the whole suite.** Walk every `## Acceptance`
  item and confirm coverage; resolve gaps before proceeding; run the full
  suite (`make lint`, `scripts/lint.py`, relevant `script_tests`) and fix
  until it passes with no errors or warnings.
- **Update documentation / version metadata.** spec_implement syncs
  `features.md`/`architecture.md`; the task analogue is whatever docs the
  task names plus the repo's one-bump-per-commit version + plugin-lockstep
  rules.

Drop the `/specs`-only machinery (architecture.md index, stage status
tracking, `features.md`).

Relationship to `task_audit`: `task_audit` *verifies and closes* an
already-(believed-)done task; `task_implement` *does the work*. A natural
chain is implement → audit (verify + archive). Decide whether
`task_implement` also archives on success or leaves closing to
`task_audit`.

## Approach

1. New skill dir `plugins/ai_dev/skills/task_implement/` with `SKILL.md`
   (pseudo-XML, positive language). Keep it thin like spec_implement —
   a tight ordered workflow, no fan-out.
2. Port spec_implement's ordered workflow: **read** the task end-to-end →
   **load guardrails** (governing `CLAUDE.md` + the task's stated
   constraints) → **understand** the existing codebase → **implement** the
   `## Approach` in order, honouring scope/non-goals and repo conventions →
   **build tests** for every acceptance check that implies one →
   **cross-check** each `## Acceptance` item → **run the full suite** until
   clean → **update docs + bump versions** per repo rules → report results
   faithfully, including anything unmet or skipped.
3. On full success, bump `updated` and either archive (base `<archive>`
   flow) or hand to `task_audit` — per the decided boundary.
4. Reuse the base skill's bundled scripts; add none unless a real need
   appears. Register in plugin/repo metas; ship at 1.0.0; bump plugin
   lockstep.

## Acceptance

- Given a well-formed task file, `task_implement` reads it and the governing
  guardrails first, builds on existing code, produces the code + tests, runs
  the named verifications to a clean suite, and reports each acceptance item
  as met/unmet with evidence — no "done" claim without a passing check.
- It refuses to start coding before restating its understanding of the task
  and loading the guardrails (spec_implement discipline preserved).
- Tests are treated as required deliverables, not optional — a missing test
  for a stated acceptance check is a gap, not a pass.
- The implement→close boundary with `task_audit` is decided and recorded
  in the shipped `SKILL.md`.
- Trigger evals keep `task_implement` distinct from `task_create`,
  `task_audit`, and the base skill.
- `make lint` and deploy dry-run pass; plugin meta bumped lockstep.

## Related

- Base: [the rename](archive/task-skill_rename-tasks-to-task.md).
- Readiness gate before me: [task_check](task-skill_check-sibling-skill.md).
- Closing peer: [task_audit](task-skill_audit-sibling-skill.md).
- Source skill: `staged-spec/skills/spec_implement/SKILL.md`.
- Tests tracked in
  [task-skill_testing-new-features](task-skill_testing-new-features.md).
