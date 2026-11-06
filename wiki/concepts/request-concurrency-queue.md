---
title: Request concurrency queue
created: 2026-11-05
updated: 2026-11-06
type: concept
tags: [opencode, plugin, deployment]
confidence: high
checked: 2026-11-06
---

# Request concurrency queue

The request concurrency queue is an OpenCode 2 plugin that limits how many
model requests are in flight to a provider at once. It exists because some
providers reject excess concurrent requests instead of queueing them fairly,
and a rejected request can end a session before its retries succeed.

## Definition and explanation

The plugin keeps one FIFO semaphore per configured provider for the whole
OpenCode server process. Every open location (project) gates its requests
through those same semaphores, so a provider's configured maximum caps
concurrent requests across the process instead of once per location.

Each model request acquires a slot before it is sent and releases it when the
response body ends, when the request fails and is retried, or when the session
becomes idle, fails, or is deleted. A request that finds every slot taken waits
in the queue; the oldest waiter is served first. The plugin has no timeout: a
request waits until a slot is released or the request is aborted.

The queue counts in-flight requests, not sessions. A session that is running a
tool or waiting for a subagent is not consuming a provider slot. This matters
because provider limits are request limits, and counting idle sessions would
waste the configured capacity.

## Current state of knowledge

The V2 implementation uses the `http.request` and `http.response` hooks to
bracket each request. The response hook replaces the response body with a
wrapped stream so the slot is released only when the stream ends. The `retry`
hook and the `experimental.idle` hook provide release fallbacks, and the event
stream covers session idle, deletion, failure, and interruption.

The plugin is configured with a provider map, so each provider has its own
queue and maximum: `{ "myprovider": 2, "openrouter": 4 }`. The provider-list
form with a shared `maxConcurrency` remains available. The plugin is inactive
when no provider is configured. The provider ID is the stable match key; the
endpoint string is not required, because the ID identifies the configured
provider entry even when its base URL changes.

The shared queue lives in a versioned `globalThis` registry rather than in one
`setup` closure. The first plugin instance in the server process creates each
provider's limiter; later instances reuse the same limiter objects and the same
provider set, so one provider maximum covers every location. A later instance
whose provider set or configured maximum differs keeps the existing registry
unchanged and logs the mismatch: the first instance's configuration stays
authoritative for the process. Each instance subscribes its `changed` emitter
to the registry, so a transition under one location publishes through every
instance's event stream. Disposing an instance releases only its own session
entries and decrements the registry's refcount; the last instance clears it. A
separate server process still keeps its own queue.

Verified on 2026-11-06 against OpenCode 2.2.5: the server instantiates the
plugin once per open location inside one server process. The sidecar log
records one `loading plugin` line per open location, and every `changed` event
carries the emitting instance's location. `ctx.rpc.register` is also per
location: the HTTP route `POST /api/rpc/:rpcID/:method` selects the instance
from the `location[directory]` query parameter, and a call without that
parameter reaches the default location. Measured while a model request streamed
in one project, a status call with that project's location reported
`active: 1` to `2`, while the no-location call and calls for other locations
reported `0`. That is why state kept inside `setup` was per location, and why
the queue now lives in the process-wide registry. Source: OpenCode 2.2.5
sidecar log and a live status probe on 2026-11-06.

For the deployed directory install, the plugin reads
`~/.config/opencode/request-concurrency-queue.json`; the path can be overridden
with `OPENCODE_REQUEST_CONCURRENCY_CONFIG`. Plugin options win over the config
file, which wins over environment variables, which win over defaults. The
environment variables remain a fallback, not the primary local configuration.

The `log` flag is debug logging only. It prints initialization, acquire, and
release events with the provider ID and that provider's active and queued
counts. Structured state comes from the separate read-only status RPC below.

The plugin serves a read-only status snapshot over the shared
`request-concurrency-queue` RPC definition. Every location's handler reads the
process-wide registry, so the snapshot is the same whichever location serves
it. The snapshot reports one record per configured provider with `active`,
`queued`, `max`, utilization (`active / max`), and demand
(`(active + queued) / max`). Providers with no configured limit do not appear.
The server emits a `changed` event on every count-changing transition: a free
slot acquired, a request joining the wait queue, a queued request aborted, a
release that frees a slot, and a release that hands the slot to the next
waiter.

A desktop GUI part ships as the prebuilt `./gui-experimental` bundle. It adds a
pinned Concurrency tab to the session side region and reads the routed
session's server through the shared status definition, passing the session's
directory as the RPC location so the call reaches that location's instance. It
refetches on every `changed` event and on a slow interval, so a missed event
recovers. Each provider row shows its in-flight count, configured maximum, and
queue depth as absolute numbers, and its utilization and demand as percentages.
The row is green while `active < max` and nothing waits, amber when
`active == max` and nothing waits, and red when a queue exists. When a status
fetch fails, the panel shows `Status unavailable` and no provider rows until a
later fetch succeeds.

The queue does not address token-budget limits such as a provider's
`burst_protection`, nor request-size rejections such as
`cold_request_too_large`. Those are separate failure modes.

## Open questions and debates

The queue spans one server process. Separate OpenCode server processes, or other
applications using the same provider key, are not coordinated. A cross-process
limiter would need a shared store, which the current design deliberately avoids.

The V2 plugin loader's directory resolution under Bun has a failure mode that
can make a local package directory unreliable. Deploying the package as a
directory and documenting the `.ts` file entry as a manual alternative covers
both paths. See [OpenCode plugin loading](opencode-plugin-loading.md) and
[Install a local OpenCode plugin](../procedures/install-a-local-opencode-plugin.md).

A desktop status panel ships through the V2 GUI plugin `Panel` API. The
plugin's `./gui-experimental` bundle contributes a pinned tab to the session
side region and reads the server's per-provider state through the shared status
RPC definition rather than a GUI-side IPC contract. The panel uses no `Slot`
variant, so a `session.panel` menu item and a `ctx.layout.open` call are not
needed to make the tab appear.

## Related concepts

- [OpenCode plugin loading](opencode-plugin-loading.md)
- [The deployment model](deployment-model.md)
- [Install a local OpenCode plugin](../procedures/install-a-local-opencode-plugin.md)

## Derived from

- The `request-concurrency-queue` plugin package under `harness-plugins/opencode_v2/`.
- OpenCode 2.2.5 plugin API types from `@opencode/plugin`.
