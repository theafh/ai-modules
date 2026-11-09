---
description: "Implement the OpenCode 2 request concurrency queue plugin with a per-provider FIFO limiter and verified local loading."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-05T14:07:12Z
updated: 2026-11-05T19:14:00Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Implement the V2 request concurrency queue

## Goal

A working OpenCode 2 plugin that gates model requests per provider through a
FIFO semaphore. The plugin acquires before an HTTP request, releases when the
response body ends or the attempt fails, and provides session-level fallbacks
for idle, failure, deletion, and interruption. It has no timeout.

## Context

The design is in the repository handoff note and the wiki page
[Request Concurrency Queue](../../wiki/concepts/request-concurrency-queue.md).
The V2 plugin API exposes `ctx.session.hook` with `http.request`,
`http.response`, `retry`, and `experimental.idle`, plus `ctx.event.subscribe`
for session events. The V2 plugin loader resolves local package directories
through its host resolver, which can fail under Bun when a subpath the manifest
names is missing. A `.ts` entry file in a plugin discovery directory bypasses
that resolution and was the verified load path during development. The plugin
package lives at
`harness-plugins/opencode_v2/request-concurrency-queue/`.

## Approach

Implement `src/limiter.ts` as a standalone FIFO limiter with cancellation and
idempotent release. Implement `src/index.ts` as the `Plugin.define` server part:
read options from `ctx.options` with a config-file and environment fallback,
filter by provider, acquire on `http.request`, wrap the `http.response` body to
release on stream end, release on `retry` and `experimental.idle`, and release
on session idle, deletion, failure, and interruption events. Add a root
`index.ts` that re-exports the plugin for file-based loading. Add the package
manifest, TypeScript configuration, and plugin README.

Use a per-request entry keyed by the `Request` object and a per-session set of
entries, so a retry cannot release a newer request's slot. Keep the queue fair:
release transfers the slot to the oldest waiter. Do not add a timeout.

## Acceptance

- The plugin exports a `Plugin.define` server part with ID
  `request-concurrency-queue`.
- A request to a configured provider acquires a slot before the HTTP request
  and releases it when the response body ends.
- A request that fails and retries releases its slot before the next attempt.
- A queued request waits in FIFO order and is served before a later waiter.
- Aborting a queued request rejects its acquire and preserves the order of the
  remaining waiters.
- A session idle, failure, deletion, or interruption releases every held entry
  for that session.
- The provider filter excludes unconfigured providers.
- `maxConcurrency` defaults to 1 and accepts the environment fallback
  `OPENCODE_REQUEST_CONCURRENCY_MAX`.
- The plugin loads through a `.ts` file entry in `.opencode/plugins/` under
  OpenCode 2.2.5 and logs initialization when `log` is enabled.
- `bun run typecheck` passes.
