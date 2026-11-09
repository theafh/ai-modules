---
description: "Replace the hand-written plugin shims in the live OpenCode config with deployed packages, and record that the service must be restarted before its plugin list means anything."
scope: deployment
created: 2026-11-05T20:22:00Z
updated: 2026-11-05T20:22:00Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Install the plugins into the live OpenCode config

## Goal

Both plugins run from deployed package directories in the live OpenCode config,
with no hand-written shim and no symlink into a source checkout, and the
deployer's log owns both entries so `--update` and `--uninstall` reach them.

## Context

Before the deployer learned the `plugin` type, the live config carried two
artifacts made by hand:

- `~/.config/opencode/plugins/request-concurrency-queue.ts`, a one-line shim
  re-exporting from a source checkout.
- `~/.config/opencode/plugins/slash-skill-autocomplete`, a symlink into the
  same checkout.

Neither was in `deployed_artefacts.log`, so the deployer could not see them:
`--uninstall` would never remove them, and `--update` would never refresh them.
Leaving them in place beside a deployed directory of the same name would load
one plugin twice, with two independent limiters.

A second fact made the install hard to verify: `opencode plugin list` reports
the **managed service's** in-memory plugin set, not the directory contents. A
service started before the deploy keeps reporting the old set, so a correctly
deployed plugin looks missing until the service restarts.

## Approach

Remove the shim and the symlink after confirming the symlink's target is a
source checkout that must survive. Deploy both packages with the plugin type,
which copies each package whole into the plugin discovery root and records one
log line per package.

Verify the deployed copy matches its source, that no `node_modules` travelled,
and that `opencode plugin list` reports both plugins **after**
`opencode service restart`.

Record the restart requirement in the install procedure, naming the command and
stating that a plugin missing from the list reads as an unrestarted service
before it reads as a broken package.

## Acceptance

- `~/.config/opencode/plugins/` holds one directory per plugin and no `.ts`
  shim or symlink for either.
- The symlink's target directory still exists after the removal.
- Each deployed directory is byte-identical to its package in
  `harness-plugins/opencode_v2/` and contains no `node_modules`.
- `deployed_artefacts.log` carries one `plugin` entry per package, naming the
  deployed path and its source.
- `opencode plugin list` reports both plugins after `opencode service restart`.
- The install procedure names `opencode service restart` and states that the
  list reflects the service's loaded set.
