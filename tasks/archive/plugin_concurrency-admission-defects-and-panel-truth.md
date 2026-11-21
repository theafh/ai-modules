---
description: "Repair the post-release admission defects behind queue latency and a flat active count, make the status panel name each queue, and align the example configuration with the real allowance."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-21T20:57:50Z
updated: 2026-11-21T21:11:26Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Repair the post-release admission defects, explain each queue in the status panel, and align the example configuration

## Goal

After this task, the queue plugin's admission gates stop producing latency and starvation the provider never asked for, and every queue the panel reports names the gate that holds it. Specifically:

- A transient provider failure costs no admission width: the in-flight context cap reacts only to a breaker that actually opens, recovers in quarters of the remaining gap, and a configured `contextCeiling: 0` keeps the cap fixed as documented.
- The token reserve holds a small request back only while a large request is genuinely waiting, so a lone session never waits for a reserve that protects nobody.
- A retry releases the attempt it replaces rather than an older primary request that is still streaming, so a background compaction retry cannot push the provider past its cap.
- A `429` is answered by what it means: a burst-protection rejection pauses the token bucket for the stated `Retry-After` (one second when absent), while a concurrency rejection narrows the width when `adaptive` is enabled. An auxiliary request is charged to the budget and its failures are classified like a primary request's.
- Embedded image payloads are charged as images, not as their base64 text length.
- The status panel reports each provider's queue as the gate holding it, and the fan-out line separates live children from the children actually calling the model, so the provider's active count and the fan-out count visibly agree.
- The settings editor reports the file as it is now, rejects an invalid scheduler value, and the activity feed records the counts each transition produced, so a save and its effect are both visible.

The final shipped state is version `0.15.2` with store key `v12`, a passing package test suite, `tsc --noEmit` clean, and the example configuration carrying the values this work established.

## Context

**The report this answers.** After the 0.14.x admission-control release, a six-session fan-out with dozens of subagents showed `active` rarely reaching the configured width of 8 while one to three requests waited, and the same work felt slower than the release before it. The user raised three candidate causes: queue entries that are not counted, the new token reason, and HTTP response-header behavior. The status panel also showed `7/8` active beside `8/8 live · 1 waiting` subagents with an empty `QUEUED` column, which read as a miscount.

**What the measurements settled.** Against the local session store and the OpenCode 2.2.5 source:

- `active` counts in-flight model requests, not sessions or subagents, so a child session running a tool holds a fan-out permit but no model slot. In the reported window, 8 child sessions held permits and exactly 7 model calls were streaming; the eighth child was running a tool. The counts were correct and the panel did not explain them.
- A waiting subagent launch is blocked at the fan-out gate before any request exists, so it can never appear in the provider queue. That is a second, independent limit rather than an uncounted queue entry.
- The configured in-flight context cap was the real ceiling on `active`: with a 1.2M cap and 150k–250k-token contexts, six or seven requests filled it while slots stayed free. The provider meters new tokens, not in-flight context, so this cap was self-imposed.
- The provider's own `429` body states an allowance of 500,000 new tokens at once and 500,000 per minute, and excludes the cached context of running sessions. The configured 400,000/400,000 was therefore 20% stricter than the provider.
- The session store carried 28 `provider.transport` header timeouts, 20 of them within 30 seconds in one window, and six `burst_protection` rejections.

**Why the context cap spiraled.** Every stall halved the cap while a clean completion restored only a fraction, and a header timeout caused by waiting in the plugin's own queue counted as a provider stall. One bad window could therefore shrink the cap repeatedly and leave it low for many turns.

**Prior art.** [The 0.14.0 admission-control task](plugin_concurrency-admission-control-and-resilience.md) introduced the four admission dimensions, the breaker, the subagent gate, and the settings editor; this task repairs the defects that release exposed in service and completes the visibility it promised.

## Approach

**Stall accounting** (`src/scheduler.ts`). `recordStall` shrinks the context cap only when the breaker opens, so one transient failure costs no width. `recordSuccess` restores a quarter of the remaining gap toward `contextCeiling` per clean completion. `shrinkContext` returns without change when `contextCeiling` is `0`, which makes the documented fixed-cap setting true.

**Reserve** (`src/scheduler.ts`). `holdsReserve` applies only when `hasLargeWaiter` finds a waiter above `smallShare` of capacity. With no such demand a small request uses the whole bucket.

**Retry attribution** (`src/index.ts`). Record the kind and, for a primary request, the entry of each session's last admitted attempt. The `retry` hook consumes that record and releases exactly the entry it names, so an auxiliary retry releases nothing. The old per-session retry-credit map is removed.

**Failure classification** (`src/index.ts`). In `http.response`, a `429` carrying capacity pressure calls `recordFailure` and does not pause the bucket; any other `429` pauses the bucket for `parseRetryAfter` or one second. A `5xx` calls `recordFailure` and `recordStall` whether or not its body is drained. In `retry`, only a `provider.transport` failure that produced no response records a stall; an attempt that never received a slot died in this plugin's queue rather than at the provider, so it records no stall; and a plugin-produced rejection is ignored.

**Auxiliary requests** (`src/index.ts`). An auxiliary request calls `acquireBudget`, takes no slot, and is charged its whole prompt as new context because a compaction rewrites the transcript into a new prompt. Its `429` and `5xx` responses are classified in the response hook before the primary-only return.

**Image payloads** (`src/index.ts`). A body above 256,000 declared bytes is read once and walked; a base64 or data-URI payload is charged 1,200 tokens as an image and excluded from the text estimate. A smaller body keeps the declared-length estimate. The body cursor advances only when a request is admitted.

**Visibility** (`src/scheduler.ts`, `src/store.ts`, `src/status.ts`, `src/gui.tsx`, `src/rpc.ts`). The scheduler exposes the sessions holding a slot and each waiting request's blocking gate. The snapshot carries a per-provider `blocked` record (`slots`, `context`, `budget`, `breaker`, `draining`) and a subagent `calling` count computed as the intersection of live child sessions and active model sessions. The dialog renders the blocked breakdown as a tooltip on the queued cell, and the bar and dialog render `live · calling`, with the waiting count only when it is non-zero. The duplicate `waiting on slots` line is removed.

**Configuration and lifecycle** (`src/index.ts`, `src/store.ts`). The `config` RPC re-reads the file so a save is visible immediately. `saveConfig` writes a temp file, applies the change, then renames, and removes the temp file if the apply fails. Validation covers `contextCeiling`, `reserveShare`, `smallShare`, and `agingMs`. The breaker threshold default is 3 in the scheduler, the snapshot, and the form. Transition records carry the counts at that transition. A disposing instance stops admission and releases the in-flight entries it holds; waiters of sessions that hold no entry stay in the shared store through the reload grace so an adopting instance serves them, and the last release cancels whatever still waits. Live child sessions keep their permits.

**Example configuration** (`config.example.json`). Carry the measured allowance and the settings that remove the self-imposed caps: 500,000 tokens at once and per minute with a 1.1 safety factor, `contextCapacity` and `contextCeiling` `0`, `queueDeadlineMs` 240000, and a breaker of 3 stalls, 60000 ms, `wait`. Keep the provider key generic.

**Subagent gate framing.** Document `subagents.max` as a host and cost guard on live child sessions, not a model-request limit, because a child running a tool holds a permit but no provider slot. Set the example well above a typical provider width.

**Out of scope:** changing the provider, its plan, or its limits; editing OpenCode or the `@opencode/plugin` API; and adding a second admission queue for subagent launches.

## Acceptance

- The package test suite passes with no failure, and `test/fixes.test.ts` exists with a case for each of: a drained `5xx` opening the breaker and shrinking the cap, a base64 image fitting a budget its bytes would exhaust, an auxiliary request waiting on a spent bucket, an auxiliary `429` pausing the bucket, an auxiliary `5xx` counting as a stall, a request counted under `blocked.slots`, the fan-out `calling` count following a child between a model call and a tool, and the `config` RPC reporting a saved change.
- `test/scheduler.test.ts` pins that the cap is unchanged after two stalls below the threshold, halves at the third, and grows by a quarter of the remaining gap on each success; that `contextCeiling: 0` keeps a fixed cap; that the reserve holds a small request only while a large one waits; that a request queues behind a half-open probe instead of failing; and that a waiter held by the context cap counts under `blocked.context` while a waiter held by a spent bucket counts under `blocked.budget`.
- `test/plugin.test.ts` pins that a retry releases the attempt it replaces and leaves an older primary entry held; that an auxiliary retry leaves a streaming primary slot held; that a request that died while queued records no stall; that a burst-protection `429` pauses the bucket without narrowing the width; that a capacity `429` narrows the width without pausing the bucket; and that a `429` without `Retry-After` pauses for one second.
- `test/status.test.ts` pins `blockedLabel` naming only the gates with waiters and `subagentRow` rendering `live · calling` with the waiting part omitted at zero.
- `test/store.test.ts` pins a `released` transition carrying the counts that transition produced rather than the batch's final counts.
- `test/config.test.ts` rejects an invalid provider maximum and a `contextCeiling` below the capacity, and writes no file when it rejects.
- `README.md` states the three-stall breaker, the `429` split, the conditional reserve, the fixed-cap meaning of `contextCeiling: 0`, the subagent gate as a host and cost guard, and the `calling` count; the stale two-stall and unconditional-pause passages are absent, and the reload passage describes the waiters that survive the grace and are served on adoption.
- `config.example.json` carries the 500,000/500,000 allowance with a 1.1 safety factor, `contextCapacity` and `contextCeiling` `0`, `queueDeadlineMs` 240000, a breaker of 3/60000/`wait`, and a subagent guard above the provider width, under a public example provider key.
- The settings form's token-budget help states the measured allowance and names no private provider, `src/index.ts` contains no retry-credit map, and the dialog renders no separate `waiting on slots` line.
- `package.json` reports version `0.15.2`, `src/store.ts` uses store key `v12`, and `dist/gui.cjs` matches a fresh build of `src/gui.tsx`.
