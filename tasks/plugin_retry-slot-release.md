---
description: "Release only the retried primary request's slot and stop gating auxiliary model requests, so a retry cannot free a sibling's slot and an auxiliary failure cannot stall the primary."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-05T22:29:54
updated: 2026-11-05T22:29:54
status: open
reported-by: Andreas Hoffmann
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
- Keep an entry's `kind` and make the `retry` hook release only the session's primary entry for `event.model.providerID`. Keep the session idle, execution failure, deletion, interruption, and dispose releases as the fallback.
- Rewrite the README Behavior bullet and the wiki concept page so the gate reads as primary-request-only, naming auxiliary requests as outside the provider cap.
- Extend `test/plugin.test.ts`: the `requestHook` helper passes `kind: "primary"` by default; add a title-bypass test, a retry test proving a second session's primary slot survives another session's retry, and a test that a title request acquires no slot at `maxConcurrency: 1`.
- Keep the queue's FIFO order and no-timeout behavior unchanged.

**Out of scope:** Adding a queue timeout or revisiting the no-timeout decision; changing the OpenCode V2 plugin API or filing an upstream request for request identity on `SessionRetry`; the GUI status panel owned by `tasks/plugin_gui-concurrency-status-panel.md`.

## Acceptance

- `rg -n 'event.kind !== "primary"' harness-plugins/opencode_v2/request-concurrency-queue/src/index.ts` matches, and a `kind: "title"` request acquires no slot at `maxConcurrency: 1` (unit test).
- The `retry` hook releases only the retrying session's primary entry: with `maxConcurrency: 2`, a primary for session A and a primary for session B hold both slots, a retry on session A lets a new request acquire, and a further request still queues behind session B's held slot (unit test).
- A title request that fails before its response headers does not block a primary request: with `maxConcurrency: 1`, the title event acquires no slot and the next primary acquires immediately (unit test).
- `harness-plugins/opencode_v2/request-concurrency-queue/README.md`'s Behavior section states that primary model requests acquire a slot and auxiliary requests do not, and no longer says "Every model request ... acquires a slot"; `wiki/concepts/request-concurrency-queue.md` carries the same statement.
- `cd harness-plugins/opencode_v2/request-concurrency-queue && bun test` and `bun run typecheck` pass, and `make plugin-test` passes.
