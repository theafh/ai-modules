---
title: Request concurrency queue
created: 2026-11-05
updated: 2026-11-23
type: concept
tags: [opencode, plugin, deployment]
confidence: high
checked: 2026-11-23
---

# Request concurrency queue

The request concurrency queue is an OpenCode 2 plugin that limits how many
model requests are in flight to a provider at once. It exists because some
providers reject excess concurrent requests instead of queueing them fairly,
and a rejected request can end a session before its retries succeed.

## Definition and explanation

The plugin keeps one admission scheduler per configured provider for the whole
OpenCode server process. Every open location (project) gates its requests
through those same schedulers, so a provider's configured maximum caps
concurrent requests across the process instead of once per location.

Primary model requests (the agent loop) acquire a slot before they are sent and
release it when the response body ends, when the attempt fails and is retried,
or when the session becomes idle, fails, or is deleted. Auxiliary model requests
— title, compaction, and generate — acquire no slot and sit outside the provider
cap: the runtime gives no per-request failure signal for them, so a slot held by
an auxiliary request that failed before its response headers would have no
release path and could stall the session's primary request. A request that finds
every slot taken waits in the queue. The scheduler admits the first waiting
request that fits the concurrency, token-budget, and context-in-flight gates, so
a smaller request can start ahead of an older one that does not yet fit. The
queue has no timeout by default: a request waits until it is admitted or the
request is aborted, and `scheduler.queueDeadlineMs` optionally rejects a waiter
with a `QueueTimeoutError` that names the queue.

The queue counts in-flight requests, not sessions. A session that is running a
tool or waiting for a subagent is not consuming a provider slot. This matters
because provider limits are request limits, and counting idle sessions would
waste the configured capacity.

## Current state of knowledge

The V2 implementation uses the `http.request` and `http.response` hooks. The
response hook replaces the response body with a wrapped stream so the slot is
released only when the stream ends. A retry releases the newest recorded attempt
for the retrying session and provider: the primary entry it recorded, or nothing
when that attempt was an auxiliary request that held no slot. An auxiliary
attempt is recorded beside the primary rather than over it, so the primary's
record survives until a later retry finds it newest or the session goes idle; a
primary shadowed by an auxiliary attempt is released by the idle path, never by
that auxiliary retry. The `retry` hook and the `experimental.idle` hook provide
release fallbacks, and the event stream covers session idle, deletion, failure,
and interruption.

The plugin is configured with a provider map, so each provider has its own
queue and maximum: `{ "myprovider": 2, "openrouter": 4 }`. The provider-list
form with a shared `maxConcurrency` remains available. The request queue is
inactive when no provider is configured; a configured `subagents` gate still
runs. The provider ID is the stable match key; the
endpoint string is not required, because the ID identifies the configured
provider entry even when its base URL changes.

The scheduler admits on more than the concurrency count. A provider with a token
budget configured also gates each request on its new-context allowance, and a
`429` carrying `Retry-After` pauses that provider for the stated time. A circuit
breaker opens after two consecutive attempts that produce no response, rejecting
queued requests at once in `fail` mode or holding them until the cooldown ends in
`wait` mode, then allows one probe. With `adaptive` enabled, the effective
maximum halves on a capacity signal and recovers one step per four clean
completions, up to the configured ceiling. With `subagents` configured, the
plugin also wraps the built-in `subagent` tool and caps how many child sessions
run at once, optionally lowering that ceiling from the host's load average.

Request size is counted in UTF-8 bytes, and an image payload is charged a flat
1200 tokens instead of its base64 byte length. A body at or below 256000 bytes
is scanned in its raw bytes for a `;base64,` marker or a 2048-character base64
run, counting the `\n`, `\r`, and `\/` escapes a wrapped blob carries and not
resolving `\uXXXX` escapes, so a text-only body is sized without a decode or a
`JSON.parse`; a larger body, a matching one, or one whose declared
`content-length` is above the threshold is decoded and parsed once. The
per-session cursor is reset when a compaction is admitted, so the first primary
request after a compaction is charged its whole prompt, and a primary that
queued across a compaction skips its cursor write through a per-session reset
generation; title and generate requests leave the cursor alone. Verified on
2026-11-23 against the package's `measureBody` and token-accounting tests.

The shared queue lives in a versioned `globalThis` registry rather than in one
`setup` closure. The first plugin instance in the server process creates each
provider's limiter; later instances reuse the same limiter objects and the same
provider set, so one provider maximum covers every location. A later instance
whose provider set or configured maximum differs keeps the existing registry
unchanged and logs the mismatch: the first instance's configuration stays
authoritative for the process. Each instance subscribes its `changed` emitter
to the registry, so a transition under one location publishes through every
instance's event stream. Disposing an instance releases only its own session
entries and decrements the registry's refcount; the last instance leaves the
store adoptable for `reloadGraceMs` (default 5000) before clearing it, so a
redeploy hands the queue, its waiters, and the live child sessions to the new
instance. A separate server process still keeps its own queue.

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

The Concurrency dialog reports the running store rather than the file, so an
install configured through plugin options shows the token budget, context cap,
and host-aware switch it is actually using, and an unchanged save writes those
values back instead of clearing them. A saved maximum becomes the provider's
configured ceiling, which the status snapshot, the config snapshot, the reload
fingerprint, and adaptive recovery all read; a save that raises the ceiling
keeps an adaptive-lowered width where it is, a lowering clamps the width under
the new ceiling, and turning `adaptive` off restores the ceiling. A
provider-set change is deferred in the store and reported with
`restartRequired: true`, and the dialog then disables Save until it is reopened.
When the plugin options carry a provider set, those options win at every load,
so the dialog edits each maximum only and hides its add and remove controls.
Verified on 2026-11-23 against the package's `configSnapshot`, `saveConfig`, and
`applyConfig` tests.

The `log` flag is debug logging only. It prints initialization, acquire, and
release events with the provider ID and that provider's active and queued
counts. Structured state comes from the separate status RPC below.

The desktop sidecar sends the plugin's stdout to `/dev/null`, so `log` output
never reaches `opencode.log` or the status bar. The bar and its dialog feed are
the desktop observability surface: the dialog lists recent transitions, while
`log` remains for terminal runs. The feed records identifiers and counts only,
never prompts, message content, API keys, or tool arguments.

The plugin serves a status snapshot over the shared
`request-concurrency-queue` RPC definition, beside `config` and `save` methods
that back the Concurrency dialog. Every location's handler reads the
process-wide registry, so the snapshot is the same whichever location serves
it. The snapshot reports one record per configured provider with `active`,
`queued`, `max`, `sessions` (distinct sessions holding a slot right now),
`activeSessionIDs` (those sessions), utilization (`min(1, active / max)`, so an
over-subscribed provider reads at most 1), and demand
(`(active + queued) / max`). Providers with no configured limit do not appear.
It also carries `sessionDetails`, one record per session the dialog names —
every session holding a slot and every session in the recent-transition feed —
with its ID and the display metadata resolved from the runtime (title, agent,
project directory, parent ID), cached briefly so a title generated after the
first turn still appears; a session the runtime cannot read is listed by its ID
alone.
It also carries a bounded buffer of recent transitions, oldest first, each with a
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
bar as its in-flight slot count `active/max`, plus a separate `+queued` badge
only when something waits, where `max` is the effective maximum that adaptive
control may lower; the slot count and the Util cell's colour follow the raw
`active / max` ratio and the badge's colour follows
`(active + queued) / max`, so an over-subscribed provider renders hot while its
Util cell shows the bounded utilization, capped at 100%. The bar's tooltip names
how many distinct sessions
hold those slots, what waits and on which gate, and the remaining new-context
tokens. Because the queue is process-wide, the count includes every open
location and any headless `opencode run` session attached to the same server.
The configured ceiling is a separate field in the config tab. The bar's
subscription refetches on every `changed` event and on a slow interval, so a
missed event recovers, and the dialog renders that same snapshot: each provider
row shows its in-flight count, effective maximum, and queue depth as absolute
numbers, and its utilization and demand as percentages. The provider table keeps
one row per provider, so its height never changes with the number of sessions in
flight; the session name lives in the activity feed, where each row's session
cell shows the session's title and `agent · project`, falling back to a short ID
when the runtime cannot be read. The footer bar keeps one count per provider and
carries no session names. The numbers are coloured
on a load scale: dark green at 0%, light green at 100%, light
yellow at 150%, orange at 200%, light red at 250%, dark red at 300%, dark pink
at 350%, and magenta from 400% on, interpolated between those anchors and held
at magenta above 400%. The token count maps its remaining share onto that scale
as `(1 - available / capacity) * 300`, so a full bucket is dark green and an
empty one dark red. The active count and the Util cell's colour follow the raw
`active / max` load, while the queued count and demand follow
`(active + queued) / max`; the Util cell's text shows the bounded utilization,
capped at 100%. The active cell's tooltip names how
many distinct sessions hold the slots. Below the provider
rows, a compact monospace feed lists the recent transitions newest first with
their timestamp, kind, provider, session, and counts; it renders a bounded
newest-first list and scrolls. When a status fetch fails, the bar shows
`Status unavailable` and
the dialog shows no provider rows, until a later fetch succeeds.

A provider's `burst_protection` is handled when that provider has a `tokens`
entry, because the budget numbers are provider-specific. A request-size
rejection such as `cold_request_too_large` is not handled: the provider answers
it, and the plugin neither predicts nor retries it.

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
