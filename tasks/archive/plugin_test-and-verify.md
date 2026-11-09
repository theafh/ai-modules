---
description: "Add unit and integration coverage for the request concurrency queue and verify it against OpenCode 2.2.5."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-05T14:07:12Z
updated: 2026-11-05T19:14:00Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Test and verify the request concurrency queue

## Goal

Unit tests for the FIFO limiter and the plugin's hook wiring, plus a manual
integration check that the plugin loads and runs inside OpenCode 2.2.5. The
unit tests cover serialization, FIFO order, cancellation, idempotent release,
provider filtering, retry release, response-body release, response-body
cancellation, and every release path the server can trigger: the four session
event types, the experimental idle hook, and plugin disposal.

## Context

The limiter is pure logic and can be tested without OpenCode. The plugin's
`setup` function can be tested with a fake context that records the hook
callbacks and exposes a push-driven event stream, so a test can deliver a
server event and assert that the held slots were released. The integration
check uses a local `.opencode/plugins/` entry file and a mock
OpenAI-compatible provider pointed at a closed port, so no real provider
request is made.

The fake context must model the subscription as a stream the test can push to.
A generator that yields nothing leaves every event-driven release path
untested while the suite still passes, which is the failure this task exists to
prevent.

## Approach

Write `test/limiter.test.ts` with Bun's test runner. Write
`test/plugin.test.ts` with a fake context that captures `http.request`,
`http.response`, `retry`, and `experimental.idle`, plus an event subscription
the test drives: `subscribe` records the type filter and abort signal and
returns an async iterator the test pushes events into. Drive the hooks with
`Request` and `Response` objects, and drive the event paths by emitting each
type and asserting the queued request is served.

Add a manual integration check that starts a standalone OpenCode server with a
temporary config and a mock provider, creates a session, sends a prompt, and
reads the server log for the plugin's initialization, acquire, and release
lines.

Run `bun test` and `bun run typecheck`. Fix every failure before closing the
task.

## Acceptance

- `bun test` passes all limiter and plugin tests.
- The limiter tests cover max 1, max 2, FIFO order, cancellation, already
  aborted signals, double release, and invalid configuration.
- The plugin tests cover request serialization, response-body release,
  provider filtering, retry release, queued cancellation, and response-body
  cancellation.
- The plugin tests cover `session.idle`, `session.deleted`,
  `session.execution.failed`, and `session.execution.interrupted`, each
  releasing every slot the session holds.
- The plugin tests cover `experimental.idle` releasing the session's slots.
- The plugin tests cover disposal releasing every held slot and aborting the
  event subscription.
- A session event for one session leaves another session's slots held.
- The subscription's recorded type filter is the four release-bearing types.
- Each event-driven release test fails when its release call is removed from
  the source, so the coverage is load-bearing rather than incidental.
- `bun run typecheck` exits 0.
- The integration check shows the plugin initializing and acquiring and
  releasing a slot inside OpenCode 2.2.5, and its steps are recorded in the
  task so a later reader can repeat them.
- The temporary integration config and project plugin file are removed after
  the check.

## Integration check

Run these steps to repeat the manual check. They use a throwaway project so the
live config is untouched.

1. Create a project directory with `.opencode/plugins/` and a plugin entry file
   there that default-exports the plugin, plus a temporary `opencode.json`
   pointing one provider at a mock OpenAI-compatible endpoint on a closed port
   so no real request leaves the machine.
2. Start a server against that project directory and enable the plugin's log
   option.
3. Create a session and send one prompt.
4. Read the server log for the plugin's `initialized` line, then its `acquired`
   line, then its `released` line with reason `response-error`, which is what a
   closed port produces.
5. Stop the server and delete the throwaway project directory.

A run that shows `initialized` but no `acquired` means the provider filter did
not match the configured provider ID. A run that shows `acquired` but no
`released` is the failure this plugin exists to prevent: the slot leaked.
