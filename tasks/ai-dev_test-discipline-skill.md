---
description: Ship a standalone, stack-agnostic test_discipline skill (independent of the task system, like format_*) carrying durable testing rules; optional root TESTING.md holds the fluid project specifics.
scope: plugins/ai_dev/skills
created: 2026-06-21T15:39:42
updated: 2026-06-27T13:56:39
status: ready
reported-by: Andreas Hoffmann
---

# Standalone test-discipline skill with an optional TESTING.md extension

## Goal

Ship a small, stack-agnostic `test_discipline` skill that carries the durable, cross-cutting testing practices the language `format_*` skills do not own — determinism, behaviour-coverage over line-coverage, explicit fail-branches, fixture hygiene, test selection — as a standalone skill independent of the task system, usable on its own exactly like `format_python` or `format_rust`. Pair it with an optional root `TESTING.md` that holds the project's *fluid* testing specifics — stack, test runner, layout, thresholds — extending the skill's universals. The durable rules live in the skill (standing and stable); `TESTING.md` carries only what changes per project, so it needs no protection. A project that wants neither is unaffected, and the skill works in any repo whether or not a task system is present.

## Context

The `ai_dev` plugin already ships `format_python`, `format_rust`, and `format_markdown` — universal practice skills consulted when editing those file types, with `format_python` already carrying Python testing idioms. The gap this fills is a cross-cutting, stack-agnostic test-discipline skill that no language skill owns; it explicitly defers language syntax and test idioms to the `format_*` skills, which is what keeps it from overlapping them or ballooning. The base `task` skill's Acceptance contract already names the "measured, with a fail branch" rule, which this skill generalizes.

The skill is deliberately decoupled from the task system — like the `format_*` skills, it activates whenever tests are written or audited, in any repo, with no dependency on `tasks/` existing. `TESTING.md` is the optional project extension layer that builds on the skill's universals, and by the filing convention (project-wide material lives in a root `UPPERCASE.md` doc — see [standing-doc framework](task-family_optional-standing-doc-conventions.md)) it lives at the repo root. How the task system *consumes* `TESTING.md` — task_implement and task_audit reading it when present — is owned by that framework's unified, presence-gated doc-consumption model, not wired here; this task only ships the skill and defines the doc.

`TESTING.md` needs no protect hook, unlike `CHARTER.md`. The load-bearing testing rules are standing rules carried in the skill, stable and deployed with it, while `TESTING.md` holds only the fluid project specifics that are expected to change — so there is nothing to fence. If that calculus ever changes, a hook can be added later.

## Approach

Create a small `ai_dev` test-discipline skill (working name `test_discipline`, sibling to the `format_*` skills) carrying only stack-agnostic testing practices, and have it explicitly defer language syntax and test idioms to `format_python`, `format_rust`, and the other language skills — that deferral is the boundary that keeps it from overlapping them or ballooning. Make it independent of the task system: its activation triggers on writing or auditing tests the way `format_python` triggers on editing `.py`, with no reference to or dependency on the task family.

Define a root `TESTING.md` as the optional project extension layer (stack, runner, layout, coverage expectations) that builds on the skill's universals. Keep the toolchain to the repo's standing make + shell + markdown norm and ship the skill at the initial version. Register the skill in `plugins/ai_dev/README.md`, the root `README.md`, `plugins/ai_dev/.codex-plugin/plugin.json`, `plugins/ai_dev/.claude-plugin/plugin.json`, `.agents/plugins/marketplace.json`, and `.claude-plugin/marketplace.json`.

Non-goals: wiring the skill or `TESTING.md` into the task system — the standing-doc framework owns task_implement and task_audit reading `TESTING.md`, and the skill activates independently; a protect hook for `TESTING.md`, since its load-bearing rules live in the skill and the doc is meant to be fluid; and duplicating the language-specific test idioms the `format_*` skills already own.

## Acceptance

- A new `ai_dev` `test_discipline` skill exists carrying stack-agnostic testing practices, with an explicit deferral to the `format_*` skills for language syntax and idioms; a check confirms it does not duplicate `format_python`'s testing content.
- The skill is independent of the task system: a check confirms it activates and applies in a repo that has no `tasks/` and no task-family skills installed.
- A root `TESTING.md` is defined as the optional project extension layer (stack, runner, layout, thresholds) building on the skill's universals, with no protect hook and no task-system wiring introduced here.
- The skill is registered in the plugin `README.md`, the root `README.md`, both `plugin.json` files, and both marketplace registrations.
