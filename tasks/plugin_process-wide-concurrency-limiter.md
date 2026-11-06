---
description: "Make the request concurrency queue one process-wide limiter shared across every OpenCode location, and make the Concurrency panel show that shared state reliably."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-06T13:18:48
updated: 2026-11-06T13:18:48
status: open
reported-by: Andreas Hoffmann
---

# Make the concurrency queue process-wide across locations

## Goal

One FIFO limiter per provider spans the whole OpenCode server process, shared by
every open location, so a provider's configured maximum caps concurrent requests
across all projects instead of once per project. The pinned Concurrency panel
reads that shared state, updates while requests stream, and reports a fetch
failure instead of showing silent zeros.

## Context

The plugin lives at `harness-plugins/opencode_v2/request-concurrency-queue/`.
`src/index.ts` creates a fresh `limits` map inside `setup`, so every plugin
instance owns its own limiters. OpenCode 2.2.5 instantiates the plugin once per
location in a single server process: the sidecar log records one `loading
plugin` line per open location, and every `changed` event carries the emitting
instance's location.

`ctx.rpc.register` is also per location. The HTTP route
`POST /api/rpc/:rpcID/:method` selects the instance from the
`location[directory]` query parameter, and a call without it reaches the default
location. `subscribeStatus` in `src/status.ts` calls `client.status({})` with no
options, so the panel reads the default location's idle limiter. Measured while
a model request streamed in one project: a status call with that project's
location reported `active: 1` to `2`, while the no-location call and calls for
other locations reported `0`. That is the reported symptom: the panel shows
`0 / max` permanently.

The queue is therefore per location today, not process-wide as
`README.md` `## Behavior` claims. With K open projects, a provider can receive
K times its configured maximum in concurrent requests.

`tasks/plugin_retry-slot-release.md` edits the same hooks and the same
per-session entry tracking, so the two changes stay compatible.

## Approach

Add `src/store.ts` for the process-wide state, keeping domain logic apart from
the hook wiring. The store is a `globalThis` registry under a versioned
`Symbol.for` key, holding per-provider `{ max, limiter }`, a config fingerprint,
a transition subscriber set, and a refcount. Export a factory so tests build
isolated stores without the harness runtime.

`setup` adopts or creates the registry: the first instance creates each
provider's limiter, later instances reuse the same limiter objects, and a later
instance whose configured maximum differs keeps the existing limiter and logs
the mismatch. Each instance registers its `changed` emitter as a store
subscriber, so a transition is published through every instance and the panel's
unfiltered event subscription sees it whichever location emitted it.

The status handler reads the registry, so every location's handler returns the
same provider rows. Keep the RPC contract and the panel's location-less call as
they are; the shared store makes the answer location-independent.

Dispose decrements the refcount and releases that instance's session entries;
the last instance clears the registry. A separate server process still keeps its
own queue, which stays the documented boundary.

Add a slow refetch to `subscribeStatus` beside the event refetch so a missed
event recovers, and render an explicit unavailable state in `StatusView` when
the fetch rejects instead of leaving stale rows.

Rebuild `dist/gui.cjs`, bump the package version, and rewrite the README
`## Behavior` passage and the wiki concept page so one canonical statement says
the cap is process-wide across locations. Record the verified per-location
plugin instantiation and location-routed RPC facts in the wiki with their date
and source.

**Out of scope:** the in-panel activity feed owned by
`plugin_concurrency-activity-feed`; the retry slot release owned by the
retry-slot-release task.

## Acceptance

- Two `setup` calls in one process with the same config share one limiter per
  provider: a slot acquired through the first is visible in the second's status
  snapshot, and the combined active count never exceeds the configured maximum
  (unit test).
- A status call with no location and a status call with a location return the
  same snapshot while a request is in flight (unit test).
- Disposing one instance leaves the shared limiters serving the other instance,
  and disposing the last instance clears the registry (unit test).
- `subscribeStatus` refetches on its interval, and `StatusView` renders the
  unavailable state after a rejected fetch (pinned in `test/status.test.ts` and
  `test/panel.test.ts`).
- `dist/gui.cjs` is rebuilt and the committed-bundle drift test passes.
- `README.md` `## Behavior` and the wiki concept page carry one canonical
  statement that the cap is process-wide across locations; no passage still
  describes a per-location queue.
- `cd harness-plugins/opencode_v2/request-concurrency-queue && bun test` and
  `bun run typecheck` pass, and `make plugin-test` passes.
