---
description: "Document the plugin packages, their usage, and the verified installation path in the plugin READMEs and the wiki."
scope: harness-plugins/opencode_v2
created: 2026-11-05T14:07:12Z
updated: 2026-11-05T19:14:00Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Document the plugin packages and local loading

## Goal

Documentation that lets a reader install a plugin, understand the queue
semantics, and avoid the local plugin directory loading failure. The
documentation covers the plugin package READMEs, the harness directory README,
the deployer's own README, the repository rules and test guide, and the wiki
pages for the design and the installation procedure.

## Context

The plugins are developed in this repository and deployed by
`deployment/deployment.sh` into the OpenCode plugin discovery root. Both the
deployed directory and the `.ts` file entry receive no `ctx.options`, so a
plugin that takes configuration reads a dedicated config file. The wiki schema
defines the page types and tag taxonomy.

Adding a discovery root and an artifact type is not only a script change: the
deployer's README documents its roots and its per-target behaviour, and the
repository rules describe where a new kind of artifact lives. Leaving those out
of a documentation task makes the record claim less than the change delivered.

## Approach

Write each plugin package README with behavior, options, install steps,
development commands, and limitations. Write
`harness-plugins/opencode_v2/README.md` with the plugin list, the deploy
command, the workspace development commands, and the packaging conventions. Add
the `### Harness plugin packages` section to `deployment/README.md` and a
Plugins column to its per-target table.

Add the harness plugin conventions to `AGENTS.md`, the plugin test entry point
to `TESTING.md`, and the harness tree to the root `README.md` layout and plugin
list. Keep `node_modules` out of git and out of the lint scope in `.gitignore`
and the `Makefile` exclude list.

Add wiki concept pages for the queue and plugin loading, and a procedure page
for installing a local plugin. Extend `wiki/concepts/deployment-model.md` to
the three discovery roots. Add the pages to `wiki/index.md` and append the
creation entry to `wiki/log.md`.

Run the wiki linter and fix every blocking and warn finding.

## Acceptance

- `harness-plugins/opencode_v2/README.md` describes the plugin list, the deploy
  command, development, and the packaging conventions.
- Each plugin package README describes behavior, options, install, development,
  and limitations.
- `deployment/README.md` documents the `harness-plugins/<harness>/` root, the
  `plugin` type, and the whole-directory copy, and its per-target table names
  the OpenCode plugin destination.
- `AGENTS.md` states the harness plugin package conventions, including the
  no-timeout rule, the release-every-slot rule, and the no-payload-logging
  rule.
- `TESTING.md` names `make plugin-test` as the plugin packages' test entry
  point and keeps it outside `make test`.
- The root `README.md` layout tree lists `harness-plugins/<harness>/`.
- `.gitignore` and the `Makefile` exclude list both cover plugin
  `node_modules`.
- `wiki/concepts/request-concurrency-queue.md` and
  `wiki/concepts/opencode-plugin-loading.md` exist and are indexed.
- `wiki/procedures/install-a-local-opencode-plugin.md` exists and is indexed.
- `wiki/concepts/deployment-model.md` describes the three discovery roots.
- The wiki linter reports no blocking or warn findings.
