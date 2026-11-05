---
description: "Show per-provider request concurrency state in the OpenCode desktop side region with queue depth, utilization, demand, and color states."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-05T15:19:13
updated: 2026-11-05T20:14:00
status: open
reported-by: Andreas Hoffmann
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
with tabs to a session's side region, or a `Slot` such as `window.bottom`,
through `@opencode/plugin/gui`. A GUI part needs an IPC contract to read state
from the server part. The server plugin already keeps one `FifoLimiter` per
provider and exposes `activeCount` and `queuedCount` on each limiter.

The queue semantics are documented in
[Request concurrency queue](../../wiki/concepts/request-concurrency-queue.md).
The plugin loading and package layout are documented in
[OpenCode plugin loading](../../wiki/concepts/opencode-plugin-loading.md).

## Approach

Add a GUI part to the plugin package and expose a read-only state contract from
the server part. The contract returns one record per configured provider:
provider ID, active, queued, max, utilization, and demand. The GUI panel
subscribes to that state and renders one row per provider.

Use the `Panel` API for a dedicated tab in the session side region, with a
`Slot` fallback for a compact status label if a full panel is too heavy. Keep
the render reactive: the panel stays mounted while the session changes, so read
`props.session` and the contract state at render time rather than destructuring
them once.

Define the color states explicitly:

- Green: `active < max` and `queued == 0`.
- Amber: `active == max` and `queued == 0`.
- Red: `queued > 0`.

Show the queue depth as an absolute number and the utilization and demand as
percentages. Keep the values per provider; do not aggregate providers into one
number.

## Acceptance

- The plugin package loads a GUI part alongside the existing server part.
- The server part exposes a read-only state contract with per-provider
  `active`, `queued`, and `max`.
- The GUI renders a status tab or slot in the desktop side region.
- Each configured provider shows its absolute queue depth, utilization
  percentage, and demand percentage.
- The color follows the green, amber, red model above.
- The state updates while requests acquire and release slots.
- A provider with no configured limit is not shown.
- The panel does not change queue behavior, add a timeout, or alter retries.
- The README and wiki document the panel and its state model.
- `bun test` and `bun run typecheck` pass.

## Out of scope

- Cross-process or cross-application aggregation.
- Historical charts or persisted metrics.
- Alerting, notifications, or automatic concurrency adjustment.
