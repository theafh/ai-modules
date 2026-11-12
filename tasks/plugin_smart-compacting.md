---
description: "Low-priority OpenCode V2 plugin that keeps a rolling summary and substitutes a compacted request only when the gateway's cold-context limit would force compaction."
scope: harness-plugins/opencode_v2
created: 2026-11-11T19:24:51Z
updated: 2026-11-12T08:32:23Z
status: open
reported-by: Andreas Hoffmann
---

# Smart compaction plugin for OpenCode V2 (low priority)

## Goal

**Priority: low.** Build the plugin only when long-running sessions make cold-resume compaction frequent enough to hurt; the configuration in use already covers most of the benefit.

Deliver an OpenCode V2 server plugin at `harness-plugins/opencode_v2/smart-compacting/` that keeps a rolling summary of a session's older turns and substitutes a compacted request only when the configured gateway would otherwise reject the request as cold context. The compacted request preserves the system prompt, the pinned instruction entries, and the last `keepSize` tokens of full turns verbatim; the summary replaces only the middle. With `autoCompact: false` (the default) a warm session is left untouched even above the trigger, and the prepared summary is applied only when the session has been idle longer than the gateway's cache lifetime or the request prefix changed. With `autoCompact: true` the plugin applies it at the trigger regardless of warmth. A fallback records the prepared summary for OpenCode's own overflow recovery and records a 413 rejection to tighten the next prediction.

Low priority because a read-only query of the local OpenCode session store on 2026-11-11 found 9 completed compactions across 6,789 sessions that used the gateway's DeepSeek models (0.13%), 8 of 643 root sessions (1.24%), exactly one compaction in every compacted session, and 8 of 79 root sessions with at least 100 assistant messages (10.13%). The native configuration in use (`keep.tokens: 60000`, `auto: true`, an unreachable threshold) already delivers "compact only when forced" and a 60k tail. The plugin becomes relevant when sessions run long enough that cold-resume compaction becomes routine.

## Context

### The gateway rule the plugin targets

The configured SeibertGPT gateway enforces cold-context limits that are independent of the model's advertised 1M window: a new session may not start with more than 350,000 tokens in its first request; a session paused more than 4 hours may not resume with more than 350,000 tokens; and an ongoing session may not add more than 350,000 new tokens at once. A session that grows gradually may exceed 350,000 tokens in total while its cache stays warm. The plan window (350k, 500k, or 1M) is a separate cap. The gateway also budgets 400,000 new tokens per minute and returns `burst_protection` when exhausted. The relevant rejection codes are `cold_request_too_large` (413), `context_length_exceeded` (400), and `burst_protection` (429). The plugin targets the first two; a burst rejection is a wait, not a compaction trigger.

### What the native compaction already provides

OpenCode 2.2.5's compaction service starts from `{ auto: true, keep: 15000, precompute: false }` and already implements:

- a threshold of `usable - buffer`, where `usable` is `min(input, context)` and the default buffer is the larger of 15% of `usable` and 16k tokens;
- a keep boundary that walks backward until adding the next message would exceed `keep`, then snaps to the last user message at or before that index, so full turns are never split;
- a background `precompute` that requires `auto` and `precompute`, starts at 85% of the threshold, requires the last measured response to carry at least 64k tokens, and invalidates when the tail since its checkpoint exceeds `min(max(2 * keep, 30000), 25% of the cap)`;
- an overflow recovery that runs before the retry path, calls the compaction service, and retries the request; the `retry` hook is skipped for context-overflow errors because the code guards it with `!K9(we)`;
- an overflow cap of `min(cap, estimate * 0.85)`, with factors 0.85, 0.7, 0.5, and 0.35 on repeated overflow, and truncation levels that may drop the oldest exchanges when the transcript still does not fit.

The plugin reuses the keep-boundary algorithm and the threshold arithmetic rather than inventing new ones. Its own contribution is the trigger dimension the native service does not model: cache warmth.

### What this plugin adds over the native solution

| Capability | Native | Plugin |
| --- | --- | --- |
| Trigger | request size against a window percentage or token buffer | configurable request budget over system + tools + messages, plus cache warmth |
| Warm sessions | compact at the threshold even when the cache is warm | leave a warm session untouched; substitute only on cold resume or a changed prefix |
| Background preparation | requires `auto`; starts at 85% of the threshold; held in memory | independent of `auto`; starts at `triggerSize - prepareMargin`; persisted in plugin storage |
| Applying the summary | synchronous on overflow, after a rejected request | predictive, before dispatch, with no failed request |
| Head | system prompt and instruction files | plus the spec and guardrails pinned through `session.instructions.entry` |
| Emergency summary | may truncate the oldest exchanges | uses the summary built while the history was healthy |
| Tail | `keep.tokens` with the full-turn cut | the same algorithm with an explicit `keepSize` |

### Related artifacts

The sibling [plugin design](archive/plugin_design-request-concurrency-queue.md) sets the package layout, README, and test conventions this package follows. The [retry slot release](archive/plugin_retry-slot-release.md) task documents the `http.request` and `retry` hook fields and the `@opencode/plugin` 2.2.5 types the fallback uses. The existing [request-concurrency-queue source](../harness-plugins/opencode_v2/request-concurrency-queue/src/index.ts) shows hook registration, storage, and the package build. The repo's [Harness plugin packages](../TESTING.md) gate is `make plugin-test`.

## Approach

### Package and configuration

Create a Bun package under `harness-plugins/opencode_v2/smart-compacting/` with `package.json`, `src/index.ts`, `test/`, `README.md`, and `tsconfig.json`, following the sibling plugin's layout. Register it the way every sibling package is registered: add `smart-compacting` to the workspace `harness-plugins/opencode_v2/package.json`'s `workspaces`, `scripts.test`, and `scripts.typecheck`, which is what `make plugin-test` runs, and add its row to the `## Plugins` table in `harness-plugins/opencode_v2/README.md`, as the standing repo rules require for a new harness plugin package. Read options from `ctx.options` with these defaults:

```jsonc
{
  "triggerSize": 320000,
  "keepSize": 60000,
  "autoCompact": false,
  "prepareMargin": 40000,
  "coldAfterHours": 4,
  "minTailTurns": 2
}
```

`triggerSize` is a request budget, not a message budget: it is compared against the estimate of the whole request, including system instructions and tool schemas. The 320k default leaves headroom under the gateway's 350k cold limit for estimator drift. `keepSize` is the largest full-turn suffix kept verbatim. `prepareMargin` starts the rolling summary early enough to have it ready before the trigger. `coldAfterHours` mirrors the gateway's cache lifetime.

### Estimator

Compute the request size the way the native service does: take the measured token count from the last assistant message (`input + cache.read + cache.write + output + reasoning`), add a character-based estimate of every message after it, and add the estimated size of `event.system` and `event.tools`. Read the measured value through `ctx.session.context` or track it from the event stream, because the `context` hook carries no usage field. Over-estimate rather than under-estimate; `triggerSize` carries the safety margin.

### Keep boundary

Walk backward from the last message, accumulating the estimated tokens of each full turn, and stop before adding the next turn would exceed `keepSize`. Then move the cut forward to the nearest user message so the kept suffix starts a turn. Never split a tool call from its result. When the last turn alone exceeds `keepSize`, keep it whole and record a warning; the alternative is an invalid request. The result is the largest full-turn suffix whose size is at most `keepSize`, the same shape as the native `wL` and `vy` pair.

### Rolling summary

Maintain one held summary per session in `ctx.storage`, keyed by the session ID, and record the covered range, the model reference, a hash of the initial instructions, the first message ID, and the tail length at preparation time.

- Start preparation when the estimate reaches `triggerSize - prepareMargin`.
- Summarize everything before the keep boundary, using `ctx.experimental.generate.text` so the summary request does not enter session history. Prefer the session's model; allow `agents.compaction.model` to override it.
- When new messages push the boundary forward, summarize only the delta and extend the held summary. Re-summarize from scratch when the model, the initial instructions, or the first message changed, because the prefix is no longer the one the summary covers.
- Invalidate the held summary when the tail since its covered range exceeds `keepSize`, so the summary never leaves an uncovered gap.
- Persist the held summary so a restart does not lose it; the native precompute is memory-only.

### Applying the summary

In the `context` hook, when the cold condition and the trigger both hold, replace `event.messages` with the summary plus the kept tail. Put the summary into `event.system` as a text part rather than splicing a message into the transcript: the system part avoids role-alternation and tool-pairing constraints, and the native system prompt is already outside the summarized region. Pin the spec and guardrails with `ctx.session.instructions.entry.put` so they render as instruction blocks and survive every substitution.

### Cold trigger and fallback

Track the last request time per session in storage. Treat the request as cold when the idle time exceeds `coldAfterHours`, or when the model, the initial instructions, or the first message changed since the last request. With `autoCompact: false`, substitute only when the request is both cold and over `triggerSize`; leave a warm request alone even above the trigger. With `autoCompact: true`, substitute whenever the request exceeds `triggerSize`.

Because the native overflow path bypasses the `retry` hook, the plugin cannot wait for the 413. It predicts instead. Register `http.response` to record a `cold_request_too_large` or `context_length_exceeded` response and set a force flag for the next request, and register the `compaction` hook to return the held summary through `event.result` when the native overflow recovery does run. That gives the first missed prediction a better summary than the native emergency path, and every later request the predictive path.

### Keep the native mechanisms out of the way

Leave OpenCode's `compaction.auto` at `true` and keep its threshold unreachable: the model's declared 1M window with the default buffer yields roughly 850k. Then the native auto path never fires on size, and the native overflow recovery remains as the safety net for a missed prediction. Do not set `auto: false`: it also disables the overflow recovery and the native precompute, so a missed prediction becomes a hard error. Keep `compaction.keep.tokens` at 60k so the native fallback and a manual `/compact` retain the same tail the plugin uses.

**Out of scope:**

- Changing the gateway, its plan, or its limits.
- Replacing OpenCode's built-in compaction, or editing OpenCode or the `@opencode/plugin` API.
- Slicing inside a message or splitting a tool call from its result.
- A TUI surface, a status indicator, or a per-session dashboard.
- Automatic plan upgrades or provider negotiation.

## Acceptance

- `harness-plugins/opencode_v2/smart-compacting/` exists with `package.json`, `src/index.ts`, `test/`, `README.md`, and `tsconfig.json`; `harness-plugins/opencode_v2/package.json` lists `smart-compacting` in `workspaces`, `scripts.test`, and `scripts.typecheck`, so `make plugin-test` runs its `test` and `typecheck` scripts; and the workspace `harness-plugins/opencode_v2/README.md` `## Plugins` table carries its row.
- A keep-boundary test over a fixture of user, assistant, and tool messages passes: the kept suffix begins at a user message, no tool-call/result pair is split, its estimated size is at most `keepSize`, and a single trailing turn larger than `keepSize` is kept whole and reported. The test fails against a naive tail slice.
- An estimator test passes: the estimate equals the sum of the system, tools, and message estimates, and the measured value is taken from the last assistant message's usage.
- A rolling-summary test passes: the held summary is reused when the model, instructions, first message, and tail are unchanged; it is extended by only the delta when the boundary moves; it is regenerated when the model, instructions, or first message changes; and it is invalidated when the tail exceeds `keepSize`.
- A trigger test with a fake clock passes: a session idle 3 hours and over `triggerSize` is not substituted with `autoCompact: false`; the same session idle 5 hours is substituted; `autoCompact: true` substitutes at `triggerSize` while warm; a warm session over `triggerSize` is left untouched with the default.
- An apply test passes: the substituted request contains the system prompt, the summary as a system text part, and the kept tail; no tool pair is split; the summary text is the held summary, not a fresh model call.
- A fallback test passes: a simulated 413 sets the force flag, the next request substitutes, and the `compaction` hook returns the held summary through `event.result` and skips the model call.
- An integration test with a fake OpenAI-compatible provider passes: the provider rejects a request carrying more than 350,000 new tokens when the session has been idle more than 4 hours; the session grows past 350,000 tokens while warm without a substitution, idles, resumes, and the first resumed request is accepted; the fake provider records no rejected request.
- `make plugin-test` passes at the repository root, and `bun test` plus `bun run typecheck` pass inside the package.
- `README.md` states the option defaults, the cold-trigger rule, the native-versus-plugin delta, and the conditions under which the plugin is worth enabling, and names the low-priority measurement from `## Goal` as the reason the plugin is optional.
- The working tree changes only under `harness-plugins/opencode_v2/smart-compacting/`, the workspace `harness-plugins/opencode_v2/package.json` and `README.md`; the gateway and the OpenCode installation are untouched.
