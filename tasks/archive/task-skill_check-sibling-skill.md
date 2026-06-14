---
description: Add a `task_check` sibling skill (inspired by spec_check) that assesses one task's implementation readiness against a checklist (scope, focus, complexity, no contradictions/ambiguity), read-only.
scope: plugins/ai_dev
created: 2026-05-28T20:35:20
updated: 2026-05-31T00:20:09
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Add the `task_check` sibling skill

## Goal

A read-only skill that assesses whether a **single** task file is ready to
hand to `task_implement`. It reads one task and produces a direct
readiness verdict against a checklist — scope, focus, complexity, and
freedom from contradiction and ambiguity — surfacing every issue that would
cause a one-shot AI coder to produce a wrong or divergent implementation. It
makes no edits; it judges and reports. This is the pre-implementation gate
the base skill's "single-shot-ready" body design implies but never
enforces.

## Context

Depends on [the rename](task-skill_rename-tasks-to-task.md). The direct
template is `staged-spec/skills/spec_check/SKILL.md`, a thin skill that
"reviews a single stage spec for implementation readiness … produces one
direct assessment from the current agent" and defers its assessment
criteria to
`staged-spec/skills/spec_development/references/single_stage_assessment.md`.
That reference is the gold mine — adapt its lens from a `/specs` stage to a
`tasks/<scope>_<name>.md` file.

Readiness checklist (spec_check's lens, mapped to a task file):

- **Structural compliance** — the task carries the expected body sections
  (`## Goal`, `## Context`, `## Approach`, `## Acceptance`) and valid
  frontmatter. Run this first; a one-shot implementer follows structure
  literally.
- **Scope fit / sizing** — the most compact scope that still delivers a
  coherent, independently testable unit; flag too-large (multi-pass risk,
  >300-line territory) and too-small (coordination overhead, no real
  capability). Mirrors `<one_task_per_file>` and `<split_at_300>`.
- **Focus** — one atomic item; flag scope creep that should be a sibling
  task and cross-linked instead of folded in.
- **Complexity** — implementable in a single pass; flag hidden multi-step
  or cross-cutting work.
- **No contradictions** — internal consistency, including behavioral
  contradictions where one part makes another non-functional.
- **No ambiguity / under-specification** — missing requirements, unstated
  assumptions, or vague pointers that lead to divergent implementations;
  also flag over-specification that needlessly narrows implementation
  choice, and negation-framed behavior ("not X") that an implementer must
  infer.

Boundary with siblings (keep crisp):

- `task_check` (this) — judges *one* task's readiness **before** building;
  read-only.
- [task_health](task-skill_health-sibling-skill.md) — audits the *whole
  tree's* lint health and fixes mechanical issues.
- [task_audit](task-skill_audit-sibling-skill.md) — verifies a
  *believed-done* task against the *codebase* **after** building, then
  archives.

Natural chain: `task_create` → `task_check` → `task_implement` →
`task_audit`.

## Approach

1. New skill dir `plugins/ai_dev/skills/task_check/` with `SKILL.md`
   (pseudo-XML, positive language). Keep it thin like `spec_check`: one
   reviewer (the current agent), one direct assessment, no fixes, no agent
   fan-out.
2. Port the assessment procedure from `single_stage_assessment.md`: run the
   structural check first, then the content lens (the checklist above),
   adapted to task-file vocabulary and the base skill's own rules
   (`<body>`, `<one_task_per_file>`, `<split_at_300>`, standard-markdown).
3. Output contract: a short **General assessment** paragraph stating
   ready / not-ready and why, then an ordered **Issues** list ranked by how
   likely each is to derail a one-shot implementation (most problematic
   first), each with what's wrong + the minimum fix. "No issues found." when
   clean. Borrow spec_check's exact response shape.
4. No code changes to the task and no status/file moves — `task_check` only
   reports. (Acting on its findings is `task_create`/editing; building is
   `task_implement`.)
5. Register in plugin/repo metas; ship at 1.0.0; bump plugin lockstep.

## Acceptance

- `task_check` triggers on "is this task ready", "check this task before I
  build it", "assess task readiness" phrasings and produces the
  General-assessment + ranked-Issues output for a single named task.
- On a deliberately under-specified / scope-creeping / self-contradicting
  fixture task it flags the right checklist dimension; on a clean,
  single-shot-ready task it returns "No issues found."
- It makes no edits and moves no files — strictly read-only assessment.
- Trigger evals keep `task_check` distinct from `task_health` (tree audit)
  and `task_audit` (post-build codebase verification) and the base skill.
- `make lint` and deploy dry-run pass; plugin meta bumped lockstep.
- Ships the shared `task_*` `<family>` map block (all six siblings, marking itself), matching the block in `task_create` / `task_implement`.

## Related

- Base: [the rename](task-skill_rename-tasks-to-task.md).
- Next in chain: [task_implement](task-skill_implement-sibling-skill.md).
- Boundary peers: [task_health](task-skill_health-sibling-skill.md),
  [task_audit](task-skill_audit-sibling-skill.md),
  [task_create](task-skill_create-sibling-skill.md).
- Source skill: `staged-spec/skills/spec_check/SKILL.md` +
  `single_stage_assessment.md`.
- Tests tracked in
  [task-skill_testing-new-features](task-skill_testing-new-features.md).
