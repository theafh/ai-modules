---
description: "Add a bounded recent-transition feed to the Concurrency panel so acquire, queue, and release activity is visible in the desktop app instead of only in discarded stdout."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-06T13:18:48
updated: 2026-11-06T13:18:48
status: open
reported-by: Andreas Hoffmann
---

# Show recent concurrency transitions in the panel

## Goal

The pinned Concurrency tab lists the most recent acquire, queue, release, and
dequeue transitions below the provider rows, with the provider, the active and
queued counts, and the session identifier, so a user can watch the queue work in
the desktop app without a terminal.

## Context

The work builds on the process-wide store introduced by
`plugin_process-wide-concurrency-limiter`, which holds the per-provider limiters
and is the natural home for transition history. Land that task first.

`src/status.ts` fetches one snapshot and turns it into rows, `src/gui.tsx`
renders those rows, and `src/rpc.ts` defines the shared `statusRpc` snapshot
shape that both the server part and the GUI bundle import.

The plugin's `log` option writes `console.log` lines, but the desktop sidecar
sends its stdout to `/dev/null`, so those lines never reach `opencode.log` or the
UI. The panel feed is the desktop-visible surface; `log` stays for terminal
runs. The repo rule that plugin logging records identifiers and counts and never
prompts, message content, API keys, or tool arguments governs what the feed
carries.

## Approach

The store keeps a bounded ring buffer of transitions, for example the most
recent 50 entries: timestamp, provider ID, kind (`acquired`, `queued`,
`released`, `dequeued`), session ID, active count, and queued count. Session ID
is an identifier, not payload.

Extend the status snapshot with the buffer and update the `statusRpc` output
schema in `src/rpc.ts` so the server part and the GUI bundle agree. Render the
feed below the provider rows, newest first, as a compact monospace list with a
timestamp; cap the rendered window and let it scroll.

Keep the ring buffer in the store so every location's handler returns the same
history. Rebuild `dist/gui.cjs`, bump the package version, and update the README
and wiki so one canonical statement each names the feed as the desktop
observability surface and states that the desktop sidecar discards `log`
output.

**Out of scope:** changing limiter semantics or panel refresh behaviour, owned
by `plugin_process-wide-concurrency-limiter`; writing the feed to a file or
exporting it.

## Acceptance

- The ring buffer is bounded and drops the oldest entry past its limit (unit
  test).
- The status snapshot carries the recent transitions in a stable order and
  holds only identifiers and counts; a test asserts no prompt, message, or tool
  content field is present.
- The panel renders the feed below the provider rows and it updates on a
  `changed` event (panel test plus the committed-bundle drift test).
- `README.md` and the wiki concept page carry one canonical statement each that
  the feed is the desktop observability surface and that the desktop sidecar
  discards `log` output.
- `cd harness-plugins/opencode_v2/request-concurrency-queue && bun test` and
  `bun run typecheck` pass, and `make plugin-test` passes.
