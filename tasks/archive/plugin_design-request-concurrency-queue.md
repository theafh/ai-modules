---
description: "Design a process-wide FIFO request concurrency limiter for OpenCode 2, captured in a handoff note before implementation."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-05T15:07:12
updated: 2026-11-05T20:14:00
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Design the request concurrency queue

## Goal

A design for an OpenCode plugin that prevents the harness from exceeding a
model provider's concurrent-request limit. The design uses one FIFO queue per
configured provider, counts in-flight requests rather than sessions, waits
without a timeout, and releases a slot on completion, retry, idle, failure, or
deletion. The design is captured in a handoff note so the implementation can
proceed without re-deriving the decisions.

## Context

The motivating provider class is any provider whose plan caps concurrent
requests and whose API returns a concurrency-limit error when the cap is
exceeded. OpenCode's subagent fan-out can exceed such a cap. The existing
config-level alternatives were rejected because they either disable all
parallel tool calls or cannot distinguish tools from agents.

The design had to account for OpenCode 1.19.5 and OpenCode 2. The V1 path uses
`chat.params` and session events; the V2 path uses `http.request`,
`http.response`, `retry`, and `experimental.idle`.

## Approach

Write a handoff note covering the purpose, naming, scope, non-goals, FIFO
algorithm, acquire and release points, retry and cancellation behavior,
configuration, observability, testing, acceptance criteria, and the V2 port.
Keep the design request-level: a session running a tool or waiting for a
subagent does not hold a slot. Reject timeouts, polling, and backoff in favor
of a promise queue that resumes the oldest waiter.

The note lives temporarily at the repository root as `HANDOFF.md` and is
removed before the final commit.

## Acceptance

- The handoff note states the FIFO algorithm, the acquire and release points,
  the no-timeout rule, and the request-level rather than session-level
  semantics.
- The note names the V1 and V2 hook surfaces and the configuration shape.
- The note lists the non-goals: cross-process coordination, burst protection,
  request-size rejection, and priority scheduling.
- The note records the testing plan and acceptance criteria.
- The note is present in the working tree while the plugin is built and absent
  from the final commit.
