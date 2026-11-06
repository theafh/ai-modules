---
description: "Show per-provider request concurrency state in the OpenCode desktop side region with queue depth, utilization, demand, and color states."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-05T15:19:13
updated: 2026-11-06T05:07:52
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
---

# Add a GUI concurrency status panel

## Goal

A desktop status view that shows, for every configured provider, the current
in-flight request count, the waiting queue depth, and the configured maximum.
The view shows utilization as `active / max` and demand as
`(active + queued) / max`, with green when there is headroom, amber when the
provider is at capacity with no queue, and red when queued requests show that
demand exceeds capacity.

## Context

The plugin is server-only today. OpenCode 2 desktop plugins can add a `Panel`
with tabs to a session's side region through `@opencode/plugin/gui`. The
desktop reads server state through a shared RPC definition rather than a
GUI-side IPC contract: the server part registers a `status` method with
`ctx.rpc.register` and emits a `changed` event, and the window reads both
through `props.session.server.client.rpc(definition)` for the routed session's
server. The server plugin already keeps one `FifoLimiter` per
provider and exposes `activeCount` and `queuedCount` on each limiter.

The queue semantics are documented in
[Request concurrency queue](../../../wiki/concepts/request-concurrency-queue.md).
The plugin loading and package layout are documented in
[OpenCode plugin loading](../../../wiki/concepts/opencode-plugin-loading.md).

## Approach

Add a GUI part to the plugin package and define one shared RPC definition that
both parts import. Its `status` method returns the snapshot shape, named here
once: one record per configured provider with provider ID, active, queued, max,
utilization, and demand. The GUI panel calls `status`, subscribes to the
definition's `changed` event, and renders one row per provider.

The server part keeps the registration handle and calls
`void registration.events.emit("changed", {})` at every point a provider's
`active` or `queued` count changes: when a request takes a free slot, when a
request joins the wait queue, when a queued request is cancelled and leaves the
wait queue, when a release frees a slot with no waiter, and when a release
hands the slot to the next waiter — the handoff leaves `active` unchanged while
only `queued` drops, so a signal keyed on `active` alone misses it. The fake context in `test/plugin.test.ts` gains an
`rpc.register` that stores the definition, the handlers, and the registration
so a test can read the snapshot and count the emits.

Ship the GUI part as a prebuilt CommonJS `./gui-experimental` bundle, because
the desktop loads that export and never compiles plugin source. Add
`"./gui-experimental": "./dist/gui.cjs"` to `exports` and `"dist"` to `files`,
add `vite`, `solid-js`, and `vite-plugin-solid` as dev dependencies with a
`build:gui` script that builds `src/gui.tsx` through the `gui()` helper from
`@opencode/plugin/gui/vite`, and enable Solid JSX with `"jsx": "preserve"` and
`"jsxImportSource": "solid-js"` in `tsconfig.json`.

Keep the snapshot-to-row transform and the status subscription in
`src/status.ts`, a module with no GUI imports so it runs under `bun test`.
`providerRows(snapshot)` turns each provider record into its row values and
color, and `subscribeStatus(getClient, onChange)` reads `getClient()` to
subscribe to the routed session's server: it calls `client.status()` once,
registers `client.events.on("changed", ...)` to refetch and hand the new
snapshot to `onChange`, and returns that registration's unsubscribe function.
The GUI calls `subscribeStatus` inside a `createEffect` whose only reactive
read is `props.session.server.client`, with its returned unsubscribe passed to
Solid's `onCleanup`, so a session switch re-runs the effect, disposes the
previous client's handler, and subscribes to the new session's client. The GUI
imports both, and `test/status.test.ts` exercises both.

Use the `Panel` API with `region: "side"` for one dedicated tab in the session
side region, and build no `Slot` variant. Set `pinned: true` on that
`PanelTab`, which the host lists without a stored open id, so neither a
`session.panel` `MenuItem` nor a `ctx.layout.open` call is needed to make the
tab appear. Export the panel definition from `src/gui.tsx` so a test can call
its `list` directly. Keep
the render reactive: the panel stays mounted while the session changes, so read
`props.session` and the contract state at render time rather than destructuring
them once, and let the client effect above re-subscribe to the new session's
server.

Define the color states explicitly:

- Green: `active < max` and `queued == 0`.
- Amber: `active == max` and `queued == 0`.
- Red: `queued > 0`.

Show the in-flight count, the configured maximum, and the queue depth as
absolute numbers, and the utilization and demand as percentages. Keep the values per provider; do not aggregate providers into one
number.

## Acceptance

- The package loads the GUI part alongside the existing server part: the file
  the `./gui-experimental` export names exists in the package tree and a check
  imports it and finds the exported GUI part, while the `.` export still names
  the server entry.
- The server part exposes a read-only state contract with per-provider
  `active`, `queued`, and `max`.
- The GUI lists a `pinned: true` status tab in the desktop side region: `bun
  test test/panel.test.ts` imports the exported panel definition, asserts it is
  a `Panel` with `region: "side"` and no exported `Slot` part, and calls `list`
  with `open: []`, asserting it returns that one tab with `pinned: true`.
- Each configured provider row shows its in-flight count, configured maximum,
  and queue depth as absolute numbers, and its utilization and demand as
  percentages; `bun test test/status.test.ts` asserts a snapshot with
  `active: 2`, `queued: 1`, `max: 4` renders utilization `50%` and demand
  `75%`.
- The color follows the green, amber, red model above, with
  `bun test test/status.test.ts` covering each boundary: green at `active < max`
  with `queued == 0`, amber at `active == max` with `queued == 0`, and red at
  `queued > 0`.
- The state updates while requests acquire and release slots: `bun test
  test/plugin.test.ts` drives a limiter through acquire, queue, and release and
  asserts the status snapshot's `active` and `queued` follow at each step.
- The registration emits `changed` once per count-changing transition: `bun
  test test/plugin.test.ts` captures the registration through the fake
  context's `rpc.register` and, with a provider at `maxConcurrency: 1`, drives
  `http.request` for a free slot, a second `http.request` into the wait queue,
  an abort of that queued request's signal, a third `http.request` into the wait
  queue, a release that hands the slot to the queued waiter, and a release that
  frees a slot with no waiter, asserting one `changed` per step and failing when
  an emit site is removed.
- The panel reads a fresh snapshot on every `changed`: `bun test
  test/status.test.ts` gives `subscribeStatus` a fake client whose `status`
  returns a different `active` count per call and whose `events.on` records
  its handler, asserts the initial snapshot reaches `onChange`, fires the
  recorded handler and asserts the updated snapshot reaches it, then calls the
  returned unsubscribe and asserts a further fire reaches nothing.
- A session switch moves the subscription to the new session's server: `bun
  test test/status.test.ts` calls `subscribeStatus` with an accessor returning
  a first fake client, calls the returned unsubscribe to simulate the effect's
  `onCleanup`, points the accessor at a second fake client and calls
  `subscribeStatus` again, then asserts the second client's initial snapshot
  and `changed` fire reach `onChange` while the first client's recorded handler
  reaches nothing.
- A provider with no configured limit is not shown.
- The panel does not change queue behavior, add a timeout, or alter retries.
- The README `## State and observability` section and the wiki page describe
  the shipped panel and its state model in place of their future-tense text:
  the README passage from "The plugin does not yet expose a structured state
  API." through "The GUI panel is tracked separately." becomes that account,
  the wiki sentence "It is not a structured state API." is rewritten to the
  same account, and the wiki `## Open questions and debates` panel paragraph
  ending "The backlog carries that work." is rewritten or removed now that the
  panel ships; `grep` over both files finds none of those phrases.
- `bun test` and `bun run typecheck` pass.

## Out of scope

- Cross-process or cross-application aggregation.
- Historical charts or persisted metrics.
- Alerting, notifications, or automatic concurrency adjustment.
