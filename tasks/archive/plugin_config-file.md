---
description: "Read a dedicated JSON config file for the deployed directory and file-entry installs, with options, file, environment, and default precedence."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-05T15:35:10
updated: 2026-11-05T20:14:00
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Add a dedicated plugin config file

## Goal

A deployed directory install and a file-entry install can configure the plugin
through `~/.config/opencode/request-concurrency-queue.json` instead of
environment variables. The file carries the provider map and the optional `log`
flag. The path can be overridden with
`OPENCODE_REQUEST_CONCURRENCY_CONFIG`.

## Context

A plugin loaded as a directory or a `.ts` file entry receives no `ctx.options`,
so the first local install used environment variables. That is awkward for a
user who wants a persistent, readable configuration. The package install path
still uses `opencode.json` options, so the config file is the non-package
equivalent.

## Approach

Read the config file at plugin setup. Parse it as JSON and validate that it is
an object. Merge the sources in this order: plugin options, then the config
file, then environment variables, then defaults. Use the same provider-map
shape as `opencode.json`: `{ "providers": { "openrouter": 4 } }`. Add a
`config.example.json` to the plugin package and document the file in the
README and wiki.

## Acceptance

- `~/.config/opencode/request-concurrency-queue.json` is read when it exists.
- `OPENCODE_REQUEST_CONCURRENCY_CONFIG` overrides the default path.
- A missing config file is ignored.
- Invalid JSON fails with a clear error.
- Plugin options override the config file.
- The config file overrides environment variables.
- The config file supports `providers`, `maxConcurrency`, and `log`.
- The repository contains `config.example.json` with an OpenRouter example.
- The README and wiki document the file and the precedence order.
- `bun test` and `bun run typecheck` pass.
