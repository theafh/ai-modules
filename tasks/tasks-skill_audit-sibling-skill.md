---
description: Add a `task_audit` sibling skill (modeled on spec_audit): audit a task's claimed completion against the codebase — features, tests, acceptance — report gaps, archive on a clean pass.
scope: plugins/ai_dev
created: 2026-05-28T20:25:06
updated: 2026-05-28T20:45:12
status: open
---

# Add the `task_audit` sibling skill

## Goal

A skill that audits whether a task's *claimed* completion is *real*, by
checking the codebase rather than the prose. It verifies a task end-to-end —
every feature in the body, every acceptance item, and the tests that back
them — reports any gap between specified and built behaviour, and on a clean
pass closes the task out (status → `implemented`, move to `archive/`). It
answers "is this task genuinely done — and if so, close it properly."

## Context

Depends on [the rename](tasks-skill_rename-tasks-to-task.md). The direct
template is `staged-spec/skills/spec_audit/SKILL.md` — the "Implementation
Auditor" — which audits specs marked `✓ Implemented` against the actual
codebase, treats tests and verifications as first-class deliverables, runs
the full suite, and reports gaps. `task_audit` ports that discipline to a
single `tasks/<scope>_<name>.md` file.

What to carry over from spec_audit (the parts the name alone doesn't
capture):

- **Scope filter — audit what claims to be done.** spec_audit audits only
  `✓ Implemented` specs and skips drafts/in-progress/future. The task
  analogue: audit a task whose work is *claimed* complete — a
  believed-done open task being closed, or an archived `status:
  implemented` task being re-checked for drift (work that was archived
  prematurely, or that the codebase later regressed). Don't audit a task
  whose body is still a plan.
- **End-to-end verification.** Read the task thoroughly, read the actual
  implemented code and tests, then walk every item in the body and `##
  Acceptance` and confirm the code covers it.
- **Tests and verifications are first-class.** Confirm every acceptance
  check that names a test has a corresponding, *passing* test; missing or
  incomplete tests are gaps, audited with the same rigour as the feature
  work — not waved through.
- **Run the suite.** Execute the tests/lint the task names (e.g.
  `make lint`, `scripts/lint.py`, a skill's `script_tests`/evals) and
  record every failure or warning as evidence.

The closing mechanics already exist in the base skill's `<archive>`
workflow (`plugins/ai_dev/skills/task/SKILL.md`): set `status`, bump
`updated` from `date`, `git mv` to `archive/`, re-point cross-references,
re-lint. `task_audit` runs the audit first, then those steps only on a
clean pass.

Boundary with siblings:

- `task_health` audits the *tree's* internal lint health (mechanical).
- `task_audit` audits *one task* against the *codebase* (reality-level) and
  closes it. Different oracle, different unit.
- It overlaps with [task_implement](tasks-skill_implement-sibling-skill.md):
  when the audit finds the work unfinished, decide whether `task_audit`
  finishes trivial gaps itself or hands substantial remaining work to
  `task_implement`.

## Approach

1. New skill dir `plugins/ai_dev/skills/task_audit/` with `SKILL.md`
   (pseudo-XML, positive language). Keep it thin like spec_audit.
2. Workflow ported from spec_audit: read the task → read the implemented
   code and existing tests → verify each feature / `## Acceptance` item
   against the code → verify each named test exists and passes → run the
   full suite the task names, recording failures.
3. **Output contract (borrow spec_audit's exact shape):** on full
   compliance, output exactly `Success: full task compliance confirmed.`
   Otherwise output `Gaps:` followed by a numbered list, each gap giving
   **requirement / expected behaviour / actual behaviour / minimum fix**,
   ordered by mismatch size (largest coverage or behaviour gap first).
4. On a clean pass, run the base `<archive>` steps (status → `implemented`,
   `date`-bumped `updated`, move, re-link, re-lint). On gaps, finish trivial
   ones inline or hand off to `task_implement`; never archive until the
   audit is clean. Never mark a task done on prose alone — require codebase
   evidence.
5. Register in plugin/repo metas; ship at 1.0.0; bump plugin lockstep.

## Acceptance

- Given a task whose work is actually complete, `task_audit` confirms every
  feature and acceptance item against the codebase, runs the named tests,
  emits `Success: full task compliance confirmed.`, then archives the task
  (status `implemented`, `updated` bumped, moved, links re-pointed, lints
  clean).
- Given a task with unmet items or failing/missing tests, it emits `Gaps:`
  with each gap's requirement / expected / actual / minimum fix, ordered by
  mismatch size, and leaves the task open (or finishes the gap, per the
  decided hand-off rule) — it does not archive.
- Verification is evidence-based (codebase inspection + a real suite run),
  not prose-trusting; tests are audited as first-class, not assumed.
- Trigger evals keep `task_audit` distinct from `task_health` (tree lint)
  and the base skill.
- `make lint` and deploy dry-run pass; plugin meta bumped lockstep.

## Related

- Base: [the rename](tasks-skill_rename-tasks-to-task.md).
- Hand-off peer: [task_implement](tasks-skill_implement-sibling-skill.md).
- Tree-health peer: [task_health](tasks-skill_health-sibling-skill.md).
- Source skill: `staged-spec/skills/spec_audit/SKILL.md`.
- Tests tracked in
  [tasks-skill_testing-new-features](tasks-skill_testing-new-features.md).
