---
description: "Stop an auxiliary request from destroying the primary attempt record in request-concurrency-queue, preserving the shipped newest-first retry release and its streaming-primary guard."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-23T10:01:27Z
updated: 2026-11-23T10:52:30Z
status: ready
reported-by: Andreas Hoffmann
---

# Retry keeps newest-first and an auxiliary attempt stops destroying the primary record

## Goal

An auxiliary attempt (title, compaction, generate) keeps its own record instead of destroying the primary's, so the primary entry survives for a later release. A `retry` event releases a primary entry only when the newest recorded attempt for that session and provider is that primary; when an auxiliary record is the newest, the retry releases nothing and the primary entry is freed by a later retry that finds it newest, or by the session-idle path.

## Context

`harness-plugins/opencode_v2/request-concurrency-queue/src/index.ts`:

- `lastAttempt` is `Map<sessionID, Map<providerID, Attempt>>`, and `recordAttempt` overwrites the entry on every request.
- The primary path records `{ kind: "primary", entry }` after acquiring a slot; the auxiliary path records `{ kind, }` (no entry) after `acquireBudget`.
- The `retry` hook calls `takeAttempt(event.sessionID, event.model.providerID)`, which deletes the single record, and releases `attempt.entry` when its kind is `primary`. `const dispatched = attempt !== undefined` gates stall counting.
- `releaseEntry` is the only path that frees a slot after admission; `releaseSession` deletes the session's attempt records on idle, delete, and dispose.

`SessionRetry` carries `sessionID`, `agent`, `model`, `error`, `attempt`, and `decision` — no request kind and no request identity. That is why the retry cannot be attributed to the auxiliary or primary attempt it replaces, and why this task does not claim to free the primary entry from an auxiliary retry.

Newest-first is the shipped contract and stays. `tasks/archive/plugin_concurrency-admission-defects-and-panel-truth.md`, shipped in commit `627e0b4`, states the Goal "A retry releases the attempt it replaces rather than an older primary request that is still streaming", records "each session's last admitted attempt", and pins it in `test/plugin.test.ts`. The wiki concept page still states the older oldest-first rule and is the stale passage this task refreshes.

The defect this task fixes is the destruction: when a title or compaction request is recorded after a primary, the primary's record is lost entirely. After this change the record survives, so the entry is still released by the idle path instead of depending on a record that no longer exists.

Verified by reading the code above. Baseline: `bun test` and `bunx tsc --noEmit` pass in the package.

## Approach

- Keep an ordered attempt record per session and provider that stores the kind, the primary entry when there is one, and a monotonic sequence number taken at record time.
- Record an auxiliary attempt alongside the primary record instead of replacing it, so both survive until one is consumed or the session ends.
- On `retry`, consume the record with the highest sequence number. Release its entry when its kind is `primary`. When its kind is auxiliary, release nothing and leave every primary record in place. A retry that arrives after the auxiliary record has been consumed therefore finds the surviving primary record as the newest and releases it, which is the shipped newest-first rule; a primary whose record is shadowed by an auxiliary record is released by the session-idle path, never by that auxiliary retry.
- Prune a completed auxiliary record only when its response completes with a 2xx status, in the `http.response` auxiliary branch. Keep the record when the response carries an error status, so the retry that follows a failed auxiliary request consumes its own record instead of a primary one.
- Keep `dispatched` derived from whether a record was consumed, so a retry for a request that never held a slot still skips stall accounting.
- Prune a primary record when its entry is released, so a completed request leaves nothing behind, and clear the structure in `releaseSession` with the existing session cleanup.
- Refresh the wiki concept page's retry sentence to the newest-first rule, and rewrite the package README's retry bullet, which still describes "the kind recorded for that session's last request" and the compaction-retry guarantee this change narrows.

**Out of scope:** Reversing the newest-first rule, which `plugin_concurrency-admission-defects-and-panel-truth` settled; changing the `retry` event shape; and freeing a shadowed primary entry from an auxiliary retry, which the event carries no identity to support.

## Acceptance

- A plugin test passes: a primary request, then an auxiliary request, then a retry consumes the auxiliary record and releases nothing, leaving `active` at 1 with `maxConcurrency: 1`.
- A plugin test passes: a primary request, then an auxiliary request, then an auxiliary retry leaves the primary held at `active: 1`, and a second retry in the same session then releases the primary entry (`active` drops to 0), proving the primary record survived the auxiliary attempt.
- A plugin test passes: a primary entry shadowed by a newer auxiliary record is released by the session-idle path, and the idle path leaves no attempt record behind, proving the entry survives the auxiliary attempt instead of leaking forever.
- A plugin test passes: an auxiliary request answered `429`, then its retry, leaves the streaming primary held at `active: 1`, proving the failed auxiliary's record was not pruned.
- A plugin test passes: a completed 2xx auxiliary response prunes its attempt record, so a later retry in the same session consumes the primary record and releases it.
- A plugin test passes: two primary attempts recorded for one session and provider, with a retry, releases the newer entry and leaves the older one held — the shipped newest-first contract, unchanged.
- A plugin test passes: a primary entry released by its response leaves no attempt record, so a later retry in the same session releases nothing and the next request is admitted normally.
- A plugin test passes: a transport retry after a recorded primary attempt still records a stall, and a retry with no recorded attempt records no stall, proving `dispatched` survives the restructure.
- The wiki concept page states the newest-first retry rule with no "oldest unreleased primary entry" and no "never a newer request's slot", and the package README's retry bullet states that the record survives an auxiliary attempt and that a shadowed primary is released by idle rather than by an auxiliary retry, with no "the kind recorded for that session's last request" and no "releases only the attempt it replaces". One canonical statement remains in each.
- The diff this task produces touches no tracked file outside `harness-plugins/opencode_v2/request-concurrency-queue/`, `wiki/concepts/request-concurrency-queue.md`, and this task file.
