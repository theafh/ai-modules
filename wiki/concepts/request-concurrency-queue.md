---
title: Request concurrency queue
created: 2026-11-05
updated: 2026-11-05
type: concept
tags: [opencode, plugin, deployment]
confidence: high
checked: 2026-11-05
---

# Request concurrency queue

The request concurrency queue is an OpenCode 2 plugin that limits how many
model requests are in flight to a provider at once. It exists because some
providers reject excess concurrent requests instead of queueing them fairly,
and a rejected request can end a session before its retries succeed.

## Definition and explanation

The plugin keeps one FIFO semaphore per configured provider. Each model request
acquires a slot before it is sent and releases it when the response body ends,
when the request fails and is retried, or when the session becomes idle, fails,
or is deleted. A request that finds every slot taken waits in the queue; the
oldest waiter is served first. The plugin has no timeout: a request waits until
a slot is released or the request is aborted.

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

For the deployed directory install, the plugin reads
`~/.config/opencode/request-concurrency-queue.json`; the path can be overridden
with `OPENCODE_REQUEST_CONCURRENCY_CONFIG`. Plugin options win over the config
file, which wins over environment variables, which win over defaults. The
environment variables remain a fallback, not the primary local configuration.

The `log` flag is debug logging only. It prints initialization, acquire, and
release events with the provider ID and that provider's active and queued
counts. It is not a structured state API.

The queue does not address token-budget limits such as a provider's
`burst_protection`, nor request-size rejections such as
`cold_request_too_large`. Those are separate failure modes.

## Open questions and debates

The queue is per server process. Separate OpenCode server processes, or other
applications using the same provider key, are not coordinated. A cross-process
limiter would need a shared store, which the current design deliberately avoids.

The V2 plugin loader's directory resolution under Bun has a failure mode that
can make a local package directory unreliable. Deploying the package as a
directory and documenting the `.ts` file entry as a manual alternative covers
both paths. See [OpenCode plugin loading](opencode-plugin-loading.md) and
[Install a local OpenCode plugin](../procedures/install-a-local-opencode-plugin.md).

A desktop status panel is feasible through the V2 GUI plugin `Panel` and `Slot`
APIs, but the plugin is server-only today. It would need a GUI part and an IPC
contract to read the server's per-provider state. The proposed state is
`active`, `queued`, and `max`, with utilization `active / max` and demand
`(active + queued) / max`; green when there is headroom, amber at capacity, and
red when queued. The backlog carries that work.

## Related concepts

- [OpenCode plugin loading](opencode-plugin-loading.md)
- [The deployment model](deployment-model.md)
- [Install a local OpenCode plugin](../procedures/install-a-local-opencode-plugin.md)

## Derived from

- The `request-concurrency-queue` plugin package under `harness-plugins/opencode_v2/`.
- OpenCode 2.2.5 plugin API types from `@opencode/plugin`.
