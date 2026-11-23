---
description: "Fix the request-concurrency-queue breaker so only a slot-holding request becomes the half-open probe, and recovery and cooldown follow the documented contract."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-23T10:01:27Z
updated: 2026-11-23T15:17:30Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: "Andreas Hoffmann"
design-extended: false
---

# Half-open probe must be slot-holding, and recovery must reach waiters

## Goal

A half-open circuit is probed by a request that holds a concurrency slot and has a release path, so an auxiliary (budget-only) request can never take the probe and hold the circuit shut for the probe lease. A `wait`-mode queue is served the moment a success closes the circuit, and the breaker honours one fixed `cooldownMs`: a straggler finishing during the cooldown neither closes the circuit early nor extends the cooldown, while the probe's own stall reopens it.

## Context

`harness-plugins/opencode_v2/request-concurrency-queue/src/scheduler.ts`:

- `applyAdmission` marks every admitted waiter as the probe when `openUntil > 0 && now >= openUntil`, with no `budgetOnly` check, and resolves a budget-only waiter with `{ release() {} }`.
- `createSlot().release` is the only release path that clears `probeInFlight` when a request ends. `probeBlocks` also clears it once `PROBE_LEASE_MS` (330000 ms) has elapsed, and `recordSuccess` and `open` reset it, so a probe whose request never reports back is eventually released by the lease.
- `recordSuccess` clears the circuit, then returns before `schedule()` when `contextCapacity === 0 || contextCeiling === 0` (the default is `0`), so on the scheduler alone `wait`-mode waiters are served only by the two-second recheck timer. The plugin's response path also releases the entry afterwards, and `createSlot().release` calls `schedule()`, so the plugin-level queue is additionally served on release.
- `recordSuccess` clears `openUntil` unconditionally, so a straggler admitted before the circuit opened that finishes during the cooldown closes it early. `recordStall` reopens on any stall, so a straggler stall during the cooldown re-extends `openUntil`.

`src/index.ts`: an auxiliary request takes the `acquireBudget` path and returns before any entry exists, and the `http.response` hook returns for `event.kind !== "primary"` before the code that calls `recordSuccess`, so no auxiliary success can settle a probe. An auxiliary **5xx** is different: the hook calls `recordStall()` for every 5xx before that non-primary return, so an auxiliary failure during half-open reopens the circuit and clears a live probe exactly as the primary path does.

Verified by reading the code above and by a half-open reproduction: with `active=0, queued=1, admitted=false`, the queue stayed blocked past 301 s of simulated time. Baseline: `bun test` and `bunx tsc --noEmit` pass in the package, so no existing test pins the corrected behaviour.

README.md's breaker bullet states the intended contract: "After the cooldown one probe is allowed and the rest queue behind it: a success closes the circuit, another stall reopens it."

## Approach

In `src/scheduler.ts`:

- Gate probe assignment on `!waiter.budgetOnly` in `applyAdmission`, and leave `probeInFlight` false when only budget-only waiters are admitted. A half-open circuit with no slot waiter stays half-open and admits budget-only work; the first slot waiter becomes the probe.
- Keep the admission gates untouched, so a budget-only waiter that arrives while a slot probe is in flight still queues behind it. Only the probe *assignment* changes.
- Move `schedule()` in `recordSuccess` so it runs on every success, before the context-growth early returns.
- Make the cooldown authoritative for stragglers only: a stall recorded while `openUntil > now` leaves `openUntil` untouched and does not call `shrinkContext`, so it neither extends the cooldown nor shrinks the cap again. The time key alone is the rule, because no request is admitted during the cooldown. A stall from the probe itself (`now >= openUntil`) reopens the circuit with a fresh `cooldownMs` and calls `shrinkContext()`, keeping both calls that `recordStall` already makes; that includes an auxiliary 5xx, which reaches `recordStall` on its own path.
- A success recorded while `openUntil > now` leaves the circuit as it is while still growing the context cap; only a success at or after `openUntil` (the probe's) closes it. A straggler that finishes after the cooldown but before any probe starts is indistinguishable from the probe's success by time alone, and closes the circuit.
- Amend the `recordSuccess` doc comment to state that only a success at or after the cooldown closes the circuit while the context cap grows, and amend `enqueue`'s half-open comment so it covers a budget-only request admitted with no probe in flight.

In the package `README.md`, extend the breaker bullet so it states four things: the probe is a slot-holding request, a half-open circuit with no probe in flight admits an auxiliary request, an open circuit rejects or queues an auxiliary request like any other request, and an auxiliary 5xx reopens the circuit. Rewrite "the rest queue behind it" in place rather than appending a second statement.

**Out of scope:** Changing the admission gates, the probe lease duration, or the `fail`/`wait` mode choice.

## Acceptance

- A scheduler test passes: with the breaker half-open and one budget-only waiter queued, the waiter is admitted, `probeInFlight` is false, and a following slot waiter becomes the probe and is admitted.
- A scheduler test passes: with the breaker half-open and a slot probe in flight, a budget-only waiter queues rather than being admitted.
- A scheduler test passes: a straggler success recorded while `openUntil > now` leaves `breakerState` `open` and does not admit the queue; a straggler stall recorded while open leaves `breakerRetryAfterMs` no larger than the remaining cooldown and leaves `contextCapacity` unchanged.
- A scheduler test passes: the existing probe-stall case, given a non-zero `contextCapacity` and `contextCeiling`, still reopens the circuit (`breakerState` `open`, `breakerRetryAfterMs` equal to the full cooldown) and still shrinks `contextCapacity`.
- A scheduler test passes with `contextCapacity: 0` (the default): `recordSuccess` serves a queued `wait`-mode waiter immediately rather than on the recheck timer.
- A scheduler test passes with a non-zero `contextCapacity` and `contextCeiling`: a straggler stall recorded while open leaves `contextCapacity` unchanged, proving the cap suppression is real rather than masked by the zero-cap early return.
- A plugin test passes: during half-open, a compaction request and a primary request are both in flight at once — the compaction is admitted as budget-only work and the primary becomes the probe — and a compaction 5xx then reopens the circuit, so the breaker reports the new cooldown and a further primary request is held for it.
- A plugin-level test passes: with `maxConcurrency: 1`, `breaker.mode: "wait"`, and `queueDeadlineMs` set, a compaction request that arrives first after the cooldown is admitted, and a primary request queued behind it is admitted within the deadline.
- The `recordSuccess` doc comment states that only a success at or after the cooldown closes the circuit while the cap grows, and `enqueue`'s half-open comment covers a budget-only admission with no probe in flight.
- The package README's breaker bullet states the slot-holding probe, the half-open auxiliary admission, the open-circuit reject-or-queue behaviour, and that an auxiliary 5xx reopens the circuit, and the prior sentence "the rest queue behind it" is superseded by one canonical statement.
- The diff this task produces touches no tracked file outside `harness-plugins/opencode_v2/request-concurrency-queue/` and this task file.
