---
description: "Scaffold the plugin packages, their repository rules, and the task backlog in the harness tree."
scope: harness-plugins/opencode_v2
created: 2026-11-05T14:07:12Z
updated: 2026-11-05T19:33:23Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Scaffold the plugin packages and their supporting trees

## Goal

The plugin packages sit in one place with the support an author needs around
them: a package layout, a license, a README, repository rules, a `.gitignore`,
and a task backlog.

## Context

The packages are Bun modules that export a `Plugin.define` server part. Each
carries its own `package.json`, `tsconfig.json`, `src/`, `test/`, and README, so
a package can be copied and deployed on its own.

The repository already holds its wiki and its task backlog, so this task adds
the plugin tree to them rather than creating them. The durable knowledge about
how OpenCode discovers and loads a plugin lives in
[OpenCode plugin loading](../../wiki/concepts/opencode-plugin-loading.md), and
the packaging rules are the repository's standing rules rather than this task's
content.

## Approach

Create the package layout with one directory per plugin, each self-contained.
Add a README describing the packages and their development commands, the
repository rules for the harness tree, and `.gitignore`. Register the harness
directory in the root layout, and file the retrospective tasks for the plugin
work under `tasks/archive/`.

The license is the repository's existing one: the plugin packages ship under it
rather than carrying a second copy.

## Acceptance

- Each plugin is a self-contained package directory with its own manifest,
  TypeScript configuration, source, tests, and README.
- The README, the harness tree's repository rules, and `.gitignore` exist.
- The root layout names `harness-plugins/<harness>/`.
- `tasks/archive/` holds the retrospective tasks for the plugin work.
- The wiki linter reports no blocking findings for the pages this work adds.
