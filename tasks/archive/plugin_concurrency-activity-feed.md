---
description: "Add a bounded recent-transition feed to the Concurrency panel so acquire, queue, and release activity is visible in the desktop app instead of only in discarded stdout."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-06T12:18:48Z
updated: 2026-11-06T14:23:00Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
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

The store keeps a bounded ring buffer of the most recent 50 transitions: timestamp, provider ID, kind (`acquired`, `queued`,
`released`, `dequeued`), session ID, active count, and queued count. Session ID
is an identifier, not payload. Map each of the five shipped count-changing
transitions onto those kinds as follows (one buffer entry per named row;
handoff appends two entries because each entry carries one session ID):

- free-slot acquire → `acquired`
- join wait queue → `queued`
- queued-request abort → `dequeued`
- release with no waiter → `released`
- release handoff to waiter → `released` for the releasing session, then
  `acquired` for the waiter

Extend the status snapshot with the buffer and update the `statusRpc` output
schema in `src/rpc.ts` so the server part and the GUI bundle agree. Render the
feed below the provider rows, newest first, as a compact monospace list with a
timestamp; cap the rendered window and let it scroll.

Append from the limiter's count-changing path, not from the plugin `log` calls:
widen `FifoLimiter` so each of its five `onChange` sites (free-slot acquire,
join wait queue, queued abort, release with no waiter, release handoff) notifies
with kind and session ID, and thread the session ID into `acquire` (and the
waiter) so join-queue, abort, and handoff carry it. Handoff keeps one site and
one notify: that notify appends both buffer entries (`released` then
`acquired`) so the existing one-`changed`-emit-per-transition contract stays;
do not notify twice for handoff. Every location's status handler only reads the
store buffer; it does not append.

Keep the ring buffer in the store so every location's handler returns the same
history. Rebuild `dist/gui.cjs`, bump the package version, and update the README
and wiki so one canonical statement each names the feed as the desktop
observability surface and states that the desktop sidecar discards `log`
output.

**Out of scope:** changing limiter semantics or panel refresh behaviour, owned
by `plugin_process-wide-concurrency-limiter`; writing the feed to a file or
exporting it.

## Acceptance

- The ring buffer keeps at most 50 entries and drops the oldest entry when a
  51st is appended (unit test).
- The status snapshot carries the recent transitions in a stable order and
  holds only identifiers and counts; a test asserts no prompt, message, or tool
  content field is present.
- A unit test drives each of the five count-changing transitions named in README
  `## State and observability` (free-slot acquire, join wait queue,
  queued-request abort, release handoff, release with no waiter) and asserts
  the Approach mapping: free-slot acquire → one `acquired`, join wait queue →
  one `queued`, queued-request abort → one `dequeued`, release with no waiter →
  one `released`, release handoff → one `changed` emit and buffer entries
  `released` then `acquired`; the test fails if handoff emits `changed` twice,
  if handoff is recorded as a single kind, or if abort is recorded as
  `released` or `acquired`.
- A unit test exercises free-slot acquire, join-queue, queued abort, release with
  a waiter, and release with no waiter, and asserts the ring buffer includes
  `acquired`, `queued`, `released`, and `dequeued`, and that each retained entry
  carries provider ID, active count, queued count, and session ID alongside kind.
- The panel renders the feed below the provider rows and it updates on a
  `changed` event (panel test plus the committed-bundle drift test).
- `README.md` and the wiki concept page carry one canonical statement each that
  the feed is the desktop observability surface and that the desktop sidecar
  discards `log` output.
- `cd harness-plugins/opencode_v2/request-concurrency-queue && bun test` and
  `bun run typecheck` pass, and `make plugin-test` passes.
