---
description: "Record why skill slash commands register on the server part rather than the TUI or desktop GUI part, so one implementation reaches every surface."
scope: harness-plugins/opencode_v2/slash-skill-autocomplete
created: 2026-11-05T20:33:23
updated: 2026-11-05T20:33:23
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Choose the server surface for skill slash commands

## Goal

A decision record fixing the plugin's surface at the server part. Every client
reads the server's command list, so one registration reaches the terminal UI,
the desktop app, and `opencode run` without per-surface code or a bundling step.

## Context

OpenCode 2 builds its `/` menu from commands, not from skills. A skill is
invocable by name but never listed, so typing a skill name offers nothing.

The harness exposes three plugin surfaces, and they differ in reach:

- The server part is the package root and serves `/api/command`.
- `./tui` reaches the terminal UI only.
- `./gui-experimental` reaches the desktop app only.

The desktop resolves a typed command against the server's list and dispatches it
through `session.command({ name, text })`, so a server command behaves there
exactly as in the terminal.

## Approach

Register on the server part. Reject the two client surfaces because each covers
one client, which would require the same plugin written two or three times and
kept in step by hand. Keep the package's `exports` pointing at the server entry
so a directory install resolves the shared surface.

Keep the mapping from skills to command specs in a pure module free of Solid,
the TUI, and I/O, so the naming and collision rules are testable as a data
transform rather than through a mounted interface.

## Acceptance

- The package's server entry registers the commands and is the `exports`
  target, so a directory install loads the shared surface.
- The plugin contributes no TUI or GUI part.
- The mapping module imports neither Solid nor the TUI nor I/O, and its tests
  run without a mounted client.
- The README states the three surfaces and why the server is the one that
  reaches all of them.
