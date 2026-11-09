---
description: Align the wiki harness entrypoint's Layer 2 footer with the vendor-worker run it actually starts, matching the file header and the two operator docs.
scope: "local test harnesses"
created: 2026-11-04T19:48:40Z
updated: 2026-11-05T21:56:08Z
status: finished
implemented-by: Andreas Hoffmann
design-extended: false
reported-by: Andreas Hoffmann
---

# Align the wiki harness entrypoint's footer with its vendor-worker Layer 2

## Goal

`tests/wiki/run_all.sh` prints a Layer 2 footer that describes the
vendor-worker run the harness actually starts: Cursor by default, `agent -p`,
with no Claude-only claim and no frozen duration.

## Context

The script's header already says "Layer 2 spawns vendor workers (Cursor by
default)", and commit `788773f` updated `tests/wiki/README.md` and
`tests/wiki/RUNBOOK.md` to the same vendor-worker picture. The footer printed
whenever the script runs without `--layer2` still reads "Layer 2 (skill-level
via Claude subagents)" and "Layer 2 is not run by default because it spawns
Claude subagents and takes several minutes", so the first thing an operator
sees after `make test` contradicts the file's own header and both docs. Commit
`630e166` made the same correction to `tests/agent_spinner/run_all.sh`.

## Approach

Rewrite the footer heading and sentence in place to name the vendor worker
with Cursor as the default, matching the header and the two operator docs, and
drop the "takes several minutes" duration rather than replacing it with another
frozen figure. Keep the two numbered options and their commands unchanged.

**Out of scope:**

- Changing the Layer 2 runner, its vendor defaults, or the two operator docs.

## Acceptance

1. A grep of `tests/wiki/run_all.sh` for `Claude subagents` and `takes several
   minutes` returns nothing, and the footer names the vendor worker with Cursor
   as the default.
2. `bash tests/wiki/run_all.sh` prints the updated footer when `--layer2` is
   omitted.
3. `make lint` passes.
