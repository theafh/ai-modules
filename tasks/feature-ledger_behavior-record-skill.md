---
description: Ship a decoupled ai_dev skill that maintains a root FEATURES.md behavior ledger from the codebase, analogous to update_changelog - independent of the task system, optional, used if present.
scope: plugins/ai_dev
created: 2026-06-21T15:17:35
updated: 2026-09-05T21:26:04
status: open
reported-by: Andreas Hoffmann
---

# Decoupled feature-ledger skill (behavior record)

## Goal

Ship a standalone, optional skill that maintains a root `FEATURES.md` behavior-of-record, a behaviour-first description of what the system does today with an explicit not-yet-built boundary, by inspecting the codebase, in the same independent way `update_changelog` maintains `CHANGELOG.md`. The ledger is a general, reusable artifact that any repo can adopt with or without the task system, so it ships as its own skill rather than as a requirement wired into the task lifecycle.

## Context

The assessment behind this task: a behaviour ledger is separable from task tracking and need not be coupled to it. The task family deliberately draws the line that tasks capture *upcoming work*, not durable behaviour, so once a task is archived its behaviour description goes with it and there is no steady-state surface describing the running system. A feature ledger fills that gap, and it does so as cleanly off to the side as the changelog does. `update_changelog` is the working model: a repo-agnostic, on-demand skill that maintains a root `UPPERCASE.md` document (`CHANGELOG.md`) independently of any task or backlog. `FEATURES.md` is the behaviour analogue, derived from the codebase rather than git history, and by the filing rule (project-wide material lives in a root `UPPERCASE.md` doc) it lives at repo root alongside `CHANGELOG.md`.

Conclusion encoded as the design: this is a separate, optional, complementary skill, not needed for the task-family extension, and usable on its own. Tasks that want richer context may cite `FEATURES.md` when it exists, but nothing in the task lifecycle requires it.

## Approach

Add a new `ai_dev` skill (`update_features`) that inspects the codebase end to end and writes or refreshes a root `FEATURES.md` as a behaviour-first ledger: user-observable contracts stated as current behaviour, organized by capability area, with an explicit not-yet-implemented boundary. It runs on demand, is repo-agnostic, and has no dependency on a task system being present. Keep the toolchain to the repo's standing make + shell + markdown norm and ship at the initial version.

Define one light, optional courtesy rather than a coupling: when `FEATURES.md` exists, the autonomous shaper or an implement flow *may* refresh it after shipping behaviour, but its absence is never an error and never blocks. This keeps the ledger genuinely decoupled: adopt it alone, adopt it alongside the autonomous layer, or never adopt it.

## Acceptance

- A new `ai_dev` skill exists that, run against a staged codebase fixture, produces a root `FEATURES.md` behaviour ledger: behaviour-first, organized by capability area, with an explicit not-yet-built boundary.
- The skill runs with no dependency on `tasks/` existing: a check confirms it works in a repo that has no task system.
- The skill is registered in the plugin README, metadata, and both marketplaces, and `make lint` passes.
- The task lifecycle gains no hard dependency on `FEATURES.md`: a check confirms the create/check/implement chain operates unchanged when `FEATURES.md` is absent, and any refresh-on-ship behaviour is an optional courtesy that no-ops when the file is missing.
