---
description: "Release only the retried primary request's slot and stop gating auxiliary model requests, so a retry cannot free a sibling's slot and an auxiliary failure cannot stall the primary."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-05T22:29:54
updated: 2026-11-06T15:13:25
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
---

# Release only the retried primary request's slot in the concurrency queue

## Goal

The request-concurrency-queue plugin releases exactly the slot of the primary model request that failed and is retried, never a concurrent request's slot. Auxiliary model requests (title, compaction, generate) acquire no provider slot, so an auxiliary request that fails before its response headers cannot hold a slot and stall the session's primary request.

## Context

The plugin is `harness-plugins/opencode_v2/request-concurrency-queue/src/index.ts`. Its `http.request` hook acquires a slot for every request kind and stores an entry in `bySession`; its `retry` hook calls `releaseSession(event.sessionID, "retry")`, which releases every unreleased entry the session holds. `SessionRetry` in `@opencode/plugin` 2.2.5 (`node_modules/@opencode/plugin/dist/promise/session.d.ts`) carries `sessionID`, `agent`, `model`, `error`, `attempt`, and `decision`, with no request identity, so the hook cannot name the request that failed. The archived implementation task `tasks/archive/plugin_implement-v2-concurrency-limiter.md` states the intended contract: a retry cannot release a newer request's slot.

A local probe against OpenCode 2.2.5 with a temporary OpenAI-compatible endpoint established these facts on 2026-11-05:

- `http.response` fires for an HTTP error response, with `response.status === 500`; the wrapped response body is the release path for every failure that produces a response.
- `http.request.signal` is not aborted on failure: `signal.aborted` stayed `false` after a 500 and after a connection reset, and no `abort` event fired.
- `retry` fires only for the primary model request. A title request that got a 500 fired no `retry`; the primary succeeded and the run completed.
- A connection reset before response headers on the title request fired neither `http.response` nor `retry`; with `maxConcurrency: 1` the primary queued behind the title's held slot and the run stalled.
- Gating only `kind === "primary"` removed that stall in the same probe: the title reset was ignored, the primary acquired and succeeded, and the run completed.
- Each retry is followed by a new `http.request` with `kind === "primary"` for the same session and provider, after the retry delay.

The README's Behavior section and `wiki/concepts/request-concurrency-queue.md` currently say every model request acquires a slot and that a slot is released "when the request fails and is retried".

## Approach

- In the `http.request` hook, return before acquiring unless `event.kind === "primary"`, so title, compaction, and generate requests never acquire or hold a slot. This is the deadlock-free rule the runtime supports: it gives no per-request failure signal for auxiliary requests, and a pre-response auxiliary failure otherwise holds a slot with no release path.
- In the `http.response` hook, return before resolving an entry unless `event.kind === "primary"`, so an auxiliary response cannot fall through to `firstEntry(bySession.get(event.sessionID))` and release the session's primary slot while the primary body is still streaming. Keep that `firstEntry` fallback for primary responses, which covers a primary whose response arrives with a `Request` the hook did not record.
- Keep an entry's `kind` and make the `retry` hook release only the session's oldest unreleased primary entry for `event.model.providerID`, so a retry frees the stale failed attempt and never a newer request's slot. Keep the session idle, execution failure, deletion, interruption, and dispose releases as the fallback.
- Rewrite the README Behavior bullet and the wiki concept page so the gate reads as primary-request-only, naming auxiliary requests as outside the provider cap.
- Extend `test/plugin.test.ts`: the `requestHook` and `responseHook` helpers pass `kind: "primary"` by default and accept a `kind` override; add a test that a title request acquires no slot at `maxConcurrency: 1`, a test that a title response arriving while a primary holds the slot leaves that slot held, and a retry test proving a second session's primary slot survives another session's retry.
- Keep the queue's FIFO order and no-timeout behavior unchanged.

**Out of scope:** Adding a queue timeout or revisiting the no-timeout decision; changing the OpenCode V2 plugin API or filing an upstream request for request identity on `SessionRetry`; the GUI status panel owned by `tasks/archive/plugin_gui-concurrency-status-panel.md` (archived).

## Acceptance

- `rg -n 'event.kind !== "primary"' harness-plugins/opencode_v2/request-concurrency-queue/src/index.ts` matches, and a `kind: "title"` request acquires no slot at `maxConcurrency: 1` (unit test).
- The `retry` hook releases only the retrying session's primary entry (a regression guard, since the current `releaseSession` already filters by session): with `maxConcurrency: 2`, a primary for session A and a primary for session B hold both slots, a retry on session A lets a new request acquire, a further request still queues behind session B's held slot, and ending session B's response body lets that queued request acquire, proving the retry released session A's slot and left session B's held (unit test).
- The `retry` hook releases the older of two primary entries for one session and provider: with `maxConcurrency: 2`, a session's two primary entries hold both slots, a retry on that session lets a queued request from another session acquire, a further request still queues behind the session's newer entry, and ending that newer entry's response body lets the further request acquire, proving the retry left the newer entry held (unit test).
- A title request that fails before its response headers does not block a primary request: with `maxConcurrency: 1`, the title event acquires no slot and the next primary acquires immediately (unit test).
- A title response arriving while a primary holds the slot leaves that slot held: with `maxConcurrency: 1`, a primary acquires, a `kind: "title"` response for the same session is fully read, and a second session's primary is still queued until the first primary's response body ends (unit test).
- `harness-plugins/opencode_v2/request-concurrency-queue/README.md`'s Behavior section states that primary model requests acquire a slot and auxiliary requests do not, and no longer says "Every model request ... acquires a slot"; `wiki/concepts/request-concurrency-queue.md` states the same primary-only gate and supersedes its stale passages, so the page no longer carries the passage saying each model request acquires a slot before it is sent and releases it when the response body ends, when the request fails and is retried, nor the phrase `bracket each request`, leaving one canonical primary-only statement.
- `cd harness-plugins/opencode_v2/request-concurrency-queue && bun test` and `bun run typecheck` pass, and `make plugin-test` passes.
