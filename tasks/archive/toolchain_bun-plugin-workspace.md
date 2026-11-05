---
description: "Give the harness plugin packages a Bun workspace root, a separate make plugin-test target, and lint and git exclusions for their node_modules."
scope: harness-plugins/opencode_v2
created: 2026-11-05T20:33:23
updated: 2026-11-05T20:33:23
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
---

# Set up the Bun workspace for the harness plugins

## Goal

One install and one command run both plugin packages' unit tests and type
checks, while the repository's default test gate keeps running on Make, shell,
and Python alone so a machine without Bun still reaches a clean pass.

## Context

The repository's toolchain floor is Make plus POSIX shell plus Markdown, with
`jq`, `git`, and Python 3 as standing tools. The plugin packages are TypeScript
and need Bun to test and type-check. Adding Bun to the default gate would make
every machine need it for a change that touches no plugin.

The packages depend on `@opencode/plugin`, which OpenCode supplies from its own
runtime. The dependency exists for local type checking and tests, not for the
deployed copy, which needs no `node_modules`.

## Approach

Add a private workspace `package.json` at `harness-plugins/opencode_v2/` listing
both packages, with `test` and `typecheck` scripts that fan out to each. Commit
the lockfile so the test toolchain is pinned.

Add `make plugin-test` as the one entry point: install from the committed
lockfile, run both packages' unit tests, and type-check both. Keep it out of
`make test`.

Keep `node_modules` out of the lint scan and out of git, since a dependency tree
is neither authored content nor reviewable source.

## Acceptance

- `bun install && bun run test && bun run typecheck` at
  `harness-plugins/opencode_v2/` exits 0.
- `make plugin-test` runs that same sequence.
- `make test` still passes without invoking Bun.
- `make lint` scans no file under a `node_modules` tree.
- `git status` reports no `node_modules` path, and the lockfile is tracked.
- Both packages' `typecheck` scripts run `tsc --noEmit` under strict mode.
