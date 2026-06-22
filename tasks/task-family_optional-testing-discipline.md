---
description: Add an optional decoupled test-discipline skill with stack-agnostic practices, extensible via a root TESTING.md, wired into implement/audit as a standing rule rather than a hard guardrail.
scope: plugins/ai_dev
created: 2026-06-21T15:39:42
updated: 2026-06-21T15:39:42
status: open
reported-by: Andreas Hoffmann
---

# Optional test-discipline skill and standing-rule wiring

## Goal

Make testing an optional, extensible standing rule for the task family rather than a hard guardrail. Ship a small stack-agnostic test-discipline skill carrying universal testing practices, let a root `TESTING.md` extend it with the project's stack methodology, and have `task_implement` and `task_audit` consult both as an extension of applying standing repo rules — recommended, never blocking when absent. Testing stays in the easy tier: the discipline skill is independently usable like the `format_*` skills, the doc is optional, and a project that wants none of it is unaffected.

## Context

Testing is a quality standard verified by the audit step and applied when implementing, not a project-identity guardrail — so it is a standing rule cited via "apply repo rules," and it needs no hook of its own. This separates the tiers the spec system bundled together: project identity is the hard guardrail (it needs the protect hook because an autonomous agent could redefine the project's bounds — see [intent guardrail](task-family_intent-guardrail-for-autonomy.md)), while testing is verified, not fenced. A project that wants to stop autonomous agents weakening `TESTING.md` can add it to the intent task's path-parameterized protect hook, but that is opt-in, not the default.

The `ai_dev` plugin already ships `format_python`, `format_rust`, and `format_markdown` — universal practice skills consulted when editing those file types, and `format_python` already carries Python testing idioms. The gap is a cross-cutting test-discipline skill: stack-agnostic methodology (determinism, behaviour-coverage over line-coverage, explicit fail-branches, fixture hygiene, test selection) that the language `format_*` skills do not own. The base `task` skill's Acceptance contract already names the "measured, with a fail branch" rule, which this skill generalizes. Root `TESTING.md` is the project extension layer — stack, test runner, test layout, thresholds — building on the skill's universals, the same base-in-skill / project-extends-in-doc shape as the intent design. By the filing convention (project-wide material lives in a root `UPPERCASE.md` doc — see [optional standing-doc conventions](task-family_optional-standing-doc-conventions.md)), `TESTING.md` lives at the repo root.

## Approach

Create a small `ai_dev` test-discipline skill (working name `test_discipline`, sibling to the `format_*` skills) carrying only stack-agnostic testing practices, and have it explicitly defer language syntax and test idioms to `format_python`, `format_rust`, and the other language skills — that deferral is what keeps it from overlapping them or ballooning, and is the boundary that keeps testing from becoming heavy. The skill is decoupled and independently usable, consulted whenever tests are written or audited the way `format_python` is consulted when editing `.py`.

Define a root `TESTING.md` as the optional project extension layer (stack, runner, layout, coverage expectations) that builds on the skill's universals. Wire both into `task_implement` and `task_audit` as an extension of the standing "apply repo rules" behaviour those skills already perform: consult the discipline skill on any test-writing or test-auditing step, and read `TESTING.md` when it is present. When `TESTING.md` is absent, behaviour is unchanged and no error is raised — testing is recommended, never blocking.

Keep the toolchain to the repo's standing make + shell + markdown norm and ship the skill at the initial version. Non-goals: a default testing hook (testing is verified, not fenced), and duplicating the language-specific test idioms the `format_*` skills already own.

## Acceptance

- A new `ai_dev` test-discipline skill exists carrying stack-agnostic testing practices, with an explicit deferral to the `format_*` skills for language syntax and idioms; a check confirms it does not duplicate `format_python`'s testing content.
- A root `TESTING.md` is defined as the optional project extension layer (stack, runner, layout, thresholds) that builds on the skill's universals.
- `task_implement` and `task_audit` consult the discipline skill when writing or auditing tests and read `TESTING.md` when present, proven on a staged repo both with the file (methodology applied) and without it (behaviour unchanged, no error).
- Testing adds no hard requirement and no default hook: a check confirms a repo that adopts neither the skill nor `TESTING.md` operates unchanged, and the optional reuse of the intent task's protect hook for `TESTING.md` is documented as opt-in.
- The skill is registered in the plugin README, metadata, and both marketplaces, and `make lint` passes.
