---
description: "Replace slot-only queueing with cost-aware admission: token budget, in-flight caps with lanes, failure attribution, a circuit breaker, a subagent gate, reload-safe lifecycle, and a settings editor."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-20T13:05:00Z
updated: 2026-11-27T12:29:05Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
---

# Replace slot-only queueing with cost-aware admission control and a resilient lifecycle

## Goal

After this task, the queue plugin keeps OpenCode inside a provider's real allowance during a wide fan-out instead of merely counting requests. It admits on four dimensions — concurrency slots, brand-new context tokens, total context in flight, and a reserve that stops a stream of small requests from starving a large one. It tells a provider that is slow apart from one that is dead, and a request killed while still queued apart from one the provider answered and then failed. It gates subagent fan-out independently of model requests, survives a plugin reload without cancelling live work, and exposes every setting in the Concurrency dialog with server-side validation and immediate effect.

The queue has no deadline of its own. The client's 300-second response-header timeout already includes time spent waiting in the plugin queue, so a plugin deadline can only replace a failure it cannot prevent, and a deadline longer than 300 seconds never fires at all. What protects a run instead is the circuit breaker: it detects a provider that accepts requests and serves nothing, then stops admission so the queue cannot grow while nothing is answered.

The final shipped state is version `0.14.0` with store key `v11`, 179 passing tests across 8 files, `tsc --noEmit` clean, and the package deployed to `~/.config/opencode/plugins/request-concurrency-queue` through `deployment/deployment.sh`.

## Context

**The incident this answers.** On 20 November 2026 the queue reached `65/8`: 8 requests active and 57 waiting. Twenty-one attempts each failed at exactly 300.0 seconds with `provider.transport` and "Timed out waiting for response headers", created between 13:09:26 and 13:09:56 UTC and failing between 13:14:26 and 13:14:56, with more at 13:13:35, 13:25:07, and 13:33:51. No request completed between 13:09 and 13:38, and the provider's dashboard showed nothing processed. There were no `429` responses in the window.

**Why every attempt died at exactly 300 seconds.** The client's header timeout is 300,000 ms and wraps the whole `http.execute`, including time spent waiting in the plugin's queue. A queued request therefore looked like a provider fault even though it had never been sent. The arithmetic also explains why this had not happened before: at roughly 78 completions per minute a 65-deep queue drains in under a minute, but at zero completions per minute the wait grows without bound.

**The provider was not the fault.** With the plugin removed, six concurrent requests all completed in 2.7 seconds with no errors, and a single probe completed in 1.2 seconds. The failures were produced by the plugin's own queueing and by defects in how it classified them.

**The provider allowance this design targets.** Seibert documents a burst budget of 400,000 new uncached tokens, a refill of 400,000 per minute, `429 burst_protection` with `Retry-After`, and a separate cold-request limit of 350,000 tokens that answers `413 cold_request_too_large`. Its per-plan concurrency values are 1, 2, 4, and 16; this installation's allowance is 8, so 8 is configuration rather than a hardcoded number. The design also assumes the estimate should err high, never low: 3.5 bytes per token with a 1.1 safety factor.

**What was actually broken in the plugin.** The work surfaced defects that the tests now pin:

- the breaker counted its own `CircuitOpenError` as a new stall, so it reopened on its own output and kept chat rejecting requests;
- a request killed by the client timeout while still queued was counted as a provider stall, blaming the provider for a request it never received;
- the single half-open probe could end without a recorded verdict (session idle, abort) and leave the circuit rejecting every request forever with the misleading text "retry in 1s";
- a request larger than the token bucket's capacity waited for a refill that could never cover it, because the bucket never holds more than its capacity;
- a store created by an older build could crash plugin setup (`endDrain is not a function`), which made the status bar disappear entirely;
- the per-session body cursor was deleted on every idle, so each turn was charged its whole prompt as new tokens instead of its delta, draining the budget for no visible reason;
- a child session that went idle before its launch bound a permit leaked a fan-out slot permanently;
- a queued request was re-checked only when another request released, so a fan-out in which every session waited on its own queued request could leave free slots and a full bucket idle;
- the response hook's fallback could release another request's entry when a session had two requests in flight.

**Repair outside the running application.** A loaded plugin module cannot be replaced in place: the server is a detached `opencode-cli serve --service`, and a reload rebuilds plugins without clearing a cached module. Every repair was therefore made in this repository, deployed with `deployment/deployment.sh --global --target opencode --type plugin --only request-concurrency-queue`, and picked up by restarting OpenCode. The repository working tree is the authoritative final state; the deployed copy matches its code byte for byte. The only difference is this task's README correction, which is documentation-only.

**Relationship to the last commit.** Commit `aa8581b` carries version `0.13.0` and the bulk of the admission-control work. This task's final state is the uncommitted `0.14.0` tree, which closes the last four review findings: the dead FIFO limiter, session-ID extraction, the ambiguous response fallback, and the budget-fill guarantee.

## Approach

**One scheduler replaces the FIFO limiter.** `src/scheduler.ts` owns admission and `src/limiter.ts` is deleted; the only remaining reference was the `Slot` type, now `SchedulerSlot`. A request acquires one slot and releases it when its response body finishes, when the attempt is retried, when the session goes idle, or when the session is deleted or interrupted. Only primary model requests take a slot: auxiliary requests (title, compaction, generate) have no per-request failure signal, so a slot held by one that failed before its headers would have no release path.

**Admission is four-dimensional.** A request is admitted only when all four gates allow it:

- **Concurrency slots.** `providers[providerID]` is the maximum, configured as 8 for `seibertgpt` and 4 for `openrouter`. The provider set and maximums are fixed by the first instance in the process; a later instance configured differently keeps the existing queue and logs the mismatch.
- **New-context token budget.** `src/budget.ts` holds a lazily refilled bucket: capacity 400,000, refill 400,000 per minute, safety factor 1.1. `estimateTokens` divides bytes by 3.5 and rounds up, so it over-estimates. A `Retry-After` on a `429` pauses the whole provider for the stated time. A request larger than the bucket's capacity is admitted rather than parked forever, because waiting cannot make the bucket exceed its capacity. Changing a budget keeps its current fill; adding one starts full.
- **Context in flight.** `contextCapacity` caps the total prompt tokens of running requests at 1,200,000 (8 × 150,000), which is what a wide fan-out exhausts even when the request count is within the provider limit. `contextCeiling` bounds recovery, and a transport stall halves the cap before it grows back.
- **The reserve and lanes.** `reserveShare` 0.25 keeps a quarter of the budget free for requests above `smallShare` 0.1 of capacity. `agingMs` 30,000 lets an old waiter ignore the reserve, so a large request cannot be blocked forever by small ones.

**A waiter never depends on another release.** Admission is re-run when a gate lifts: the bucket refills, the reserve stops holding a request, or the breaker's cooldown ends. A two-second recheck bounds every gate that lifts with time alone, such as a probe lease expiring. Without it, a fan-out in which every session waits on its own queued request would leave free slots and a full bucket idle because no release ever comes to trigger a rescan.

**The queue deadline is off.** `queueDeadlineMs` defaults to `0` and the shipped config does not set it. It remains available as an error-clarity aid only: when the client's own header timeout covers queue time, a shorter deadline merely renames a failure that would happen anyway, and a longer one never fires. The breaker is the real protection.

**Failure attribution is narrow.** A retry releases only the failed attempt's slot. A `429` pauses the token bucket with its `Retry-After`; only a concurrency signal (`concurrency_limit`, `queue_timeout`, a transport failure, or a `5xx`) narrows the width when `adaptive` is on. `429 burst_protection` pauses the bucket and does not halve concurrency. An invalid request, a `400`, a `402`, or a `413` narrows nothing. A transport failure counts as a provider stall only when the attempt was actually dispatched; a request that died while queued is the plugin's own queue, not provider pressure. Errors this plugin produced (`request-concurrency-queue:`, `request cancelled:`, `subagent launch cancelled:`) are ignored by the retry hook.

**The breaker recovers by itself.** `threshold` 3 consecutive silent attempts open the circuit for `cooldownMs` 60,000 in `fail` mode: queued requests are rejected at once and new requests fail fast. `wait` mode holds them until the cooldown ends. After the cooldown one probe is allowed. A success closes the circuit; a stall reopens it. A probe that ends without a verdict clears itself, a 330-second lease expires one that never reports back, and a second request during a probe gets an honest "a test request is already checking" message instead of a false "circuit open".

**Subagent fan-out is gated separately.** `src/subagents.ts` wraps the built-in `subagent` tool and limits live child sessions to 8, independent of model requests; a child waiting on a tool still holds its permit. Because the tool returns at launch, each permit is bound to the child's session ID and released when the child goes idle. A child that ends before its permit binds is remembered and released at bind, permits carry a generation so one handed out before `cancelAll` cannot corrupt the count, and extraction accepts only a string that is entirely a session ID rather than the first `ses_…` mentioned in prose. `hostAware` is `false`, so the configured 8 is always allowed. The wrapper reads the gate at call time, so setting `max: 0` disables it without a restart.

**Lifecycle survives a reload.** The store is process-wide and adoptable for `reloadGraceMs` 5,000 after the last instance disposes, so a redeploy hands the queue, its waiters, and its live child sessions to the new instance instead of cancelling them. Admission pauses during that window (`beginDrain`/`endDrain`) so a freed slot cannot be dispatched ungated. An incompatible store is discarded rather than allowed to break loading, and every cross-build call is capability-guarded. `STORE_KEY` is `v11`. The body cursor is deleted only on `session.deleted` or dispose, so a turn is charged only its delta.

**Every setting is editable from the dialog.** The Concurrency dialog now has two tabs. **Queue** is the existing provider table and transition feed. **Config** edits provider maximums, the token budget, the context cap and lanes, the breaker, the subagent ceiling, and `adaptive`, with help text under each field and units in the labels. `saveConfig` validates every value before touching anything, applies the change to the running store first, and only then writes the file atomically, so a failed apply leaves both the file and the runtime unchanged. Adding or removing a provider reports `restartRequired: true` instead of half-applying. The RPC surface gains `config` and `save` beside `status`.

**Estimation is cheap and only runs when needed.** The estimator uses `Content-Length` when present and streams a clone only when it is absent. It is skipped entirely when neither a token budget nor a context cap is configured. The `429` body classifier streams and stops at 8 KB instead of buffering the whole response.

## Acceptance

- `cd harness-plugins/opencode_v2/request-concurrency-queue && bun test` passes 179 tests across 8 files with 0 failures, `bun run typecheck` is clean, and `bun run build:gui` produces the committed `dist/gui.cjs`.
- Scheduler tests cover slots, the token budget, the context cap, the reserve and aging lanes, the deadline default of 0, the breaker, half-open probe recovery, and an oversized token cost being admitted.
- Scheduler tests prove a queued request is admitted with no release and no new arrival: reserve-held small requests are admitted when the bucket refills, a request the bucket cannot refill for is admitted when it ages, and a held small request does not cancel a large request's refill wake-up.
- Plugin tests cover the token cursor surviving an idle boundary and charging only the delta, the early-idle subagent permit, plugin-generated errors not counting as stalls, a queued timeout not counting as a provider stall, and a failed apply leaving the config file unwritten.
- Store tests cover a reload adopting a store and serving its waiters, an expired grace cancelling them, drain stopping admission until adoption, adoption of an older store, live subagent disablement, and budget fill surviving an edit.
- The deployed plugin is version `0.14.0` and reports `max 8`, `queued 0`, `breaker closed`, `stalls 0`, `contextCapacity 1200000` for `seibertgpt`, and `subagents max 8, queued 0`.
- A real child session is observed as `live: 1` while it runs and `live: 0` after it finishes, proving the stricter session-ID extraction still binds and releases the permit.
- A config save round-trip returns `{"ok":true,"errors":[],"restartRequired":false}` and applies a changed `contextCapacity` without a restart; an invalid value is rejected at the RPC boundary and the file keeps its previous value.
- The live config carries providers `8`/`4`, tokens `400000`/`400000`/`1.1`, context `1200000`/`1200000`, deadline `0`, breaker `3`/`60000`/`fail`, subagents `8` with `hostAware false`, and `adaptive false`.
- `README.md` documents the budget, lanes, breaker, subagent gate, reload grace, and the Config tab, and its example and limitations agree with the shipped code rather than describing the pre-admission behaviour.
