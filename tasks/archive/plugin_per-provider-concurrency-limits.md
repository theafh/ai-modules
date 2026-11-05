---
description: "Give each configured provider its own FIFO queue and maximum concurrency, with map, list, and environment configuration forms."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-05T15:19:13
updated: 2026-11-05T20:14:00
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Add per-provider concurrency limits

## Goal

Each configured provider gets its own FIFO queue and its own maximum
concurrency. The plugin accepts a provider map such as
`{ "myprovider": 2, "openrouter": 4 }`, a provider list with a shared
`maxConcurrency`, and environment-variable equivalents. The plugin is inactive
when no provider is configured.

## Context

The first implementation used one shared limiter and one maximum for every
listed provider. That cannot express two providers with different allowances at
the same time. The provider ID from `event.model.providerID` is the stable match
key; the endpoint string is not needed.

## Approach

Normalize the configured providers into a map of provider ID to maximum. Build
one `FifoLimiter` per provider. On `http.request`, look up the provider's
limiter and acquire from it; an unconfigured provider passes through. Keep the
per-session entry set for release fallbacks, and record the provider ID on each
entry so release logging reports the correct limiter. Accept the number map, the
list form, and the environment forms (`provider=max,...` and a JSON object).
Validate every maximum as a positive integer.

## Acceptance

- `providers: { "a": 1, "b": 3 }` creates independent queues with those
  maximums.
- `providers: ["a", "b"]` with `maxConcurrency: 2` gives both providers a
  maximum of 2.
- An unconfigured provider is not gated.
- An empty provider list or object leaves the plugin inactive.
- The environment accepts `a=1,b=3` and `{"a":1,"b":3}`.
- An invalid maximum fails with a positive-integer error.
- The plugin still loads and runs in OpenCode 2.2.5 through the file entry.
- `bun test` and `bun run typecheck` pass.
