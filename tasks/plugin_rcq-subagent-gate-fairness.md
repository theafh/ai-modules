---
description: "Make the request-concurrency-queue subagent gate serve waiters FIFO, honour a reload drain, and re-evaluate host capacity on a timer instead of only on release."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-23T10:01:27Z
updated: 2026-11-23T11:03:53Z
status: ready
reported-by: Andreas Hoffmann
---

# Subagent gate: FIFO, drain, and capacity recheck

## Goal

A child-session launch arriving while launches are queued joins the queue instead of jumping it, a launch during a reload drain is not admitted, and a queued launch is served when the host frees capacity without waiting for another permit to be released.

## Context

`harness-plugins/opencode_v2/request-concurrency-queue/src/subagents.ts`:

- `acquire` admits whenever `liveCount < capacity()`, with no check on `waiters.length`, so a launch arriving after host load drops overtakes a waiter queued while load was high.
- `acquire` also ignores `draining`; `serve()` checks it, so a direct admission bypasses the drain a reload uses to hold new work.
- `serve()` runs only from `releaseSession`, `setMax`, `endDrain`, and permit release. Nothing re-evaluates capacity when host load falls.
- `cancelAll` bumps `generation`, clears `endedEarly`, rejects the waiters, and clears the live set, but never resets `draining`. The teardown path is `beginDrain()` then `cancelAll()`, with no `endDrain` afterwards.

README's subagent bullet states launches beyond the guard wait in FIFO order, and its admission bullet states a waiting request is checked at least every two seconds. The scheduler implements that recheck; the gate has none.

Verified by reading the code above; the review that produced this task recorded `queued=1, live=2` → load drops → a new launch reaching `live=3` while the waiter stayed queued, and a capacity change `1 → 8` leaving a waiter queued.

## Approach

- In `acquire`, route every launch through the queue when `waiters.length > 0` or `draining` is set; otherwise admit directly and increment `pending`. Push the waiter and call `serve()` so a launch that can be admitted is admitted from the queue path.
- Add a self-re-arming `setTimeout` recheck, following the scheduler's `armTimer` precedent, that runs only while `hostAware` is true and waiters exist. Its callback re-checks `waiters.length` and clears itself when the queue is empty. Clear it on `cancelAll` and in the waiter's `onAbort` handler as well, so the last waiter's abort cannot leave it probing `vm_stat` forever. Call `unref()` on the handle.
- Reset `draining` in `cancelAll`, so a post-cancel `acquire` on a torn-down gate settles instead of queueing forever.
- Expose the timer state through a getter that is not part of `SubagentStatus`, so tests can assert it without changing the published RPC schema.
- Keep the existing generation, `endedEarly`, and `pending` accounting unchanged.

**Out of scope:** Changing `hostCapacity`'s load or memory thresholds, and adding a recheck timer for the non-`hostAware` case.

## Acceptance

- A subagent test passes with an injected probe: with one waiter queued and exactly one free slot, a new `acquire` leaves the new launch pending while the older waiter's promise resolves, and `liveCount` rises by exactly one — proving the new launch joined the queue and the older one was served first.
- A subagent test passes: with the probe returning a raised capacity and no permit release, the queued launch is admitted by the recheck, and the timer getter reports no pending recheck once the queue is empty.
- A subagent test passes: `beginDrain()` then `acquire()` leaves the launch queued and `liveCount` unchanged; `endDrain()` admits it.
- A subagent test passes: `beginDrain()` → `cancelAll()` → `acquire()` settles (resolves or rejects, never hangs), and the timer getter reports no pending recheck.
- A subagent test passes: a waiter aborted by its own signal after the last queued launch clears the recheck timer.
- The diff this task produces touches no tracked file outside `harness-plugins/opencode_v2/request-concurrency-queue/` and this task file.
