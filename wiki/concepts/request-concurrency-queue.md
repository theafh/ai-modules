---
title: Request concurrency queue
created: 2026-11-05
updated: 2026-11-12
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

Primary model requests (the agent loop) acquire a slot before they are sent and
release it when the response body ends, when the attempt fails and is retried,
or when the session becomes idle, fails, or is deleted. Auxiliary model requests
— title, compaction, and generate — acquire no slot and sit outside the provider
cap: the runtime gives no per-request failure signal for them, so a slot held by
an auxiliary request that failed before its response headers would have no
release path and could stall the session's primary request. A request that finds
every slot taken waits in the queue; the oldest waiter is served first. The
plugin has no timeout: a request waits until a slot is released or the request
is aborted.

The queue counts in-flight requests, not sessions. A session that is running a
tool or waiting for a subagent is not consuming a provider slot. This matters
because provider limits are request limits, and counting idle sessions would
waste the configured capacity.

## Current state of knowledge

The V2 implementation uses the `http.request` and `http.response` hooks. The
response hook replaces the response body with a wrapped stream so the slot is
released only when the stream ends. A retry releases the session's oldest
unreleased primary entry for the retrying provider, so it frees the attempt that
failed and never a newer request's slot. The `retry` hook and the
`experimental.idle` hook provide release fallbacks, and the event stream covers
session idle, deletion, failure, and interruption.

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

The desktop sidecar sends the plugin's stdout to `/dev/null`, so `log` output
never reaches `opencode.log` or the status bar. The bar and its dialog feed are
the desktop observability surface: the dialog lists recent transitions, while
`log` remains for terminal runs. The feed records identifiers and counts only,
never prompts, message content, API keys, or tool arguments.

The plugin serves a read-only status snapshot over the shared
`request-concurrency-queue` RPC definition. Every location's handler reads the
process-wide registry, so the snapshot is the same whichever location serves
it. The snapshot reports one record per configured provider with `active`,
`queued`, `max`, utilization (`active / max`), and demand
(`(active + queued) / max`). Providers with no configured limit do not appear.
It also carries the most recent 50 transitions, oldest first, each with a
timestamp, provider ID, kind (`acquired`, `queued`, `released`, `dequeued`),
session ID, active count, and queued count. A release handoff records
`released` for the releasing session then `acquired` for the waiter. The server
emits a `changed` event on every count-changing transition: a free slot
acquired, a request joining the wait queue, a queued request aborted, a release
that frees a slot, and a release that hands the slot to the next waiter.

A desktop GUI part ships as the prebuilt `./gui-experimental` bundle. The
window-bottom status bar is its only persistent surface: a full-width bar in the
window's bottom slot that shows the same per-provider state in every window,
including Home, and opens a larger Concurrency dialog on click. It reads the
built-in server because the queue is process-wide, and hides until the first
fetch settles or when no provider is configured. Each provider appears on the
bar as one `X/Y` count, where `X` is active plus queued and `Y` is the
configured maximum, coloured by `(active + queued) / max`. The bar's
subscription refetches on every `changed` event and on a slow interval, so a
missed event recovers, and the dialog renders that same snapshot: each provider
row shows its in-flight count, configured maximum, and queue depth as absolute
numbers, and its utilization and demand as percentages. The numbers are coloured
on a six-anchor load scale: dark green at 0%, light green at 100%, light yellow
at 150%, orange at 200%, light red at 250%, and dark red from 300% on,
interpolated between those anchors and held at dark red above 300%. The active
count and utilization follow the `active / max` load, while the combined count,
queued count, and demand follow `(active + queued) / max`. Below the provider
rows, a compact monospace feed lists the recent transitions newest first with
their timestamp, kind, provider, session, and counts; it renders the newest 20
and scrolls. When a status fetch fails, the bar shows `Status unavailable` and
the dialog shows no provider rows, until a later fetch succeeds.

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

A desktop status bar ships through the V2 GUI plugin `Slot` and `Style` APIs.
The plugin's `./gui-experimental` bundle contributes a window-bottom status bar
and no side panel; it reads the server's per-provider state through the shared
status RPC definition rather than a GUI-side IPC contract, and it is the
plugin's `window.bottom` slot contribution with its CSS registered through
`Style`.

## Related concepts

- [OpenCode plugin loading](opencode-plugin-loading.md)
- [The deployment model](deployment-model.md)
- [Install a local OpenCode plugin](../procedures/install-a-local-opencode-plugin.md)

## Derived from

- The `request-concurrency-queue` plugin package under `harness-plugins/opencode_v2/`.
- OpenCode 2.2.5 plugin API types from `@opencode/plugin`.
