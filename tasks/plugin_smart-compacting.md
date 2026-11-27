---
description: "Medium-priority OpenCode V2 plugin that keeps a rolling summary and substitutes a compacted request only when the gateway's cold-context limit would force compaction."
scope: harness-plugins/opencode_v2
created: 2026-11-11T19:24:51Z
updated: 2026-11-27T08:22:00Z
status: open
reported-by: Andreas Hoffmann
---

# Smart compaction plugin for OpenCode V2 (medium priority)

## Goal

**Priority: medium.** The 2026-11-11 measurement that justified `low` no longer holds: cold-resume compaction is now routine, so this is scheduled ahead of the next long-session cycle rather than deferred until one.

Deliver an OpenCode V2 server plugin at `harness-plugins/opencode_v2/smart-compacting/` that keeps a rolling summary of a session's older turns and substitutes a compacted request only when the configured gateway would otherwise reject the request as cold context. The compacted request preserves the system prompt, the pinned instruction entries, and the last `keepSize` tokens of full turns verbatim; the summary replaces only the middle. With `autoCompact: false` (the default) a warm session is left untouched even above the trigger, and the prepared summary is applied only when the session has been idle longer than the gateway's cache lifetime or the request prefix changed. With `autoCompact: true` the plugin applies it at the trigger regardless of warmth. A fallback hands the prepared summary to OpenCode's own overflow recovery and records a rejected request to tighten the next prediction.

### Measured basis (2026-11-26T13:39Z, read-only query of the local OpenCode session store)

The 2026-11-11 baseline was accurate and still reproduces: at a 2026-11-12T00:00Z cut the store holds 7,006 gateway-model sessions, 632 gateway root sessions, exactly 9 completed gateway compactions, and 8 of 82 root sessions with at least 100 assistant messages. What has changed is the volume and the mix:

| Measure | 2026-11-11 | 2026-11-26 |
| --- | --- | --- |
| Completed compactions (gateway models) | 9 | 39 (33 auto, 6 manual), plus 3 failed |
| Gateway sessions | 6,789 | 15,625 |
| Share of gateway sessions | 0.13% | 0.19% |
| Gateway root sessions | 643 | 1,121 |
| Share of gateway root sessions | 1.24% | 2.50% |
| Root sessions with ≥100 assistant messages | 79 | 266 |
| …of which compacted | 8 (10.13%) | 27 (10.15%) |
| Compactions per compacted session | exactly 1 | 1–3; 4 of 36 sessions repeat |

Two facts carry the priority change:

- **The measured metric never measured the target condition.** Classifying the same rows by `context ≥ 350k` and `idle gap ≥ 4h`, 4 of the 9 compactions in the 2026-11-11 baseline were already cold-resume. Today 16 of 39 completed compactions are, including 8 of the last 13; 23 of 42 rows follow a user or system message with no assistant response between, which is the rejection-then-overflow-recovery path.
- **The gateway rejects for cold context roughly daily.** Ten `limit 350,000` rejections appear in the log's 5.83-day window (2026-11-20T17:52Z to 2026-11-26T13:42Z): 5 cold-resume, 3 new-session, 2 at-once-add. 61 sessions have carried at least 350k measured context, 11 at least 500k, the maximum 675,303.

Every compacted session is a root autonomous implement/audit/commit loop of 246–1,163 assistant messages; compaction does not occur in short or interactive sessions. The plugin's population is therefore long sessions, not sessions in general, and in that population the cold-resume trigger is the dominant compaction cause. Absolute volume stays modest — ten self-healing rejections a week — which is why this is medium and not high.

## Context

### The gateway rule the plugin targets

The configured SeibertGPT gateway enforces cold-context limits that are independent of the model's advertised 1M window. Three rejections are confirmed verbatim by the gateway's own response text:

- a new session may not start with more than 350,000 tokens in its first request;
- a session paused more than 4 hours may not resume with more than 350,000 tokens;
- an ongoing session may not add more than 350,000 new tokens at once.

A session that grows gradually may exceed 350,000 tokens in total while its cache stays warm. The plan window (350k, 500k, or 1M) is a separate cap and is not observable from this machine. The gateway also enforces a burst budget; its own `Burst Protection` text states **500,000 new tokens at once and 500,000 per minute**, which supersedes the 400,000/400,000 figure recorded in the earlier admission-control design.

The gateway answers with prose, not with a documented code: `cold_request_too_large` appears in no captured response and in no `@opencode` package, and the 413/400 statuses were never observed. OpenCode classifies the rejection as a context overflow — `context_length_exceeded` is one of the codes its classifier accepts (the `context_length_exceeded` case in `@opencode/ai/dist/provider-error.js`) — and its own log line, `provider rejected the request as too long; compacting`, is written at the first message of the step *after* the compaction, so the log classifies a trigger but does not time it. The plugin therefore targets the cold and context-overflow rejections by status and classification, and treats a burst rejection as a wait, not a compaction trigger.

### What the native compaction already provides (OpenCode 2.4.2)

The sessions that compact are run by the 2.4.2 service, not by the 2.2.5 CLI: session rows record client versions 2.3.0, 2.3.2, 2.4.1 and 2.4.2, and the newest compactions land seconds after a 2.4.2 `serve --service` start. 2.4.2's compaction service starts from `{ auto: true, keep: 15000, background: true }` and implements:

- a threshold of `usable - buffer`, where `usable` is `min(input, context)` and the buffer is the larger of 15% of `usable` and 16k tokens;
- a keep boundary that walks backward until adding the next message would exceed `keep`, then snaps to the last user message at or before that index, so full turns are never split, and never yields an empty tail;
- a background preparation that requires `auto` and `background`, starts at `threshold - min(60000, (threshold - lastMeasured) / 2)`, reads the prompt side only (`input + cache.read + cache.write`), and invalidates when the tail since its checkpoint exceeds `min(max(2 * keep, 30000), 25% of the cap)`;
- an overflow recovery that runs before the retry path, calls the compaction service, and retries the request; the `retry` hook is skipped for context-overflow errors because the code guards it with the context-overflow predicate;
- an overflow cap of `min(cap, estimate * 0.85)`, with factors 0.85, 0.7, 0.5, and 0.35 on repeated too-large rejections, and truncation levels that may drop the oldest exchanges when the transcript still does not fit.

2.2.5 differs in two places that matter to the delta: it starts from `precompute: false` and gates its background preparation on `auto && precompute`, 85% of the threshold, and a 64k last response. The constants the plugin reuses — `keep: 15000`, the 15%/16k buffer, and the 0.85/0.7/0.5/0.35 ladder — are identical in both versions. The plugin reuses the keep-boundary algorithm and the threshold arithmetic rather than inventing new ones. Its own contribution is the trigger dimension the native service does not model: cache warmth.

### What this plugin adds over the native solution

| Capability | Native (2.4.2) | Plugin |
| --- | --- | --- |
| Trigger | request size against a window percentage or token buffer | configurable request budget over system + tools + messages, plus cache warmth |
| Warm sessions | compact at the threshold even when the cache is warm | leave a warm session untouched; substitute only on cold resume or a changed prefix |
| Background preparation | on by default, but starts near `threshold - 60k` (~790k on a 1M window), so it never pre-empts a 350k cold rejection | independent of `auto`; starts at `triggerSize - prepareMargin` (280k by default); persisted in plugin storage |
| Applying the summary | synchronously on overflow, after a rejected request | predictively, before dispatch, with no failed request |
| Head | system prompt and instruction files | plus the spec and guardrails pinned through `session.instructions.entry.put` |
| Emergency summary | may truncate the oldest exchanges | uses the summary built while the history was healthy |
| Tail | `keep.tokens` with the full-turn cut | the same algorithm with an explicit `keepSize` |

The native background preparation is the one native feature that has changed since the task was written, and it still does not reach the cold limit: with a 1M window and a ~400k measured request it starts near 790k, roughly 440k above the point at which the gateway refuses a cold resume. Post-compaction context in the observed rows lands at 79k–113k, so a native compaction leaves a resumed request far under the limit; the cost the plugin removes is the rejected request and the discarded middle, not the tail.

### Related artifacts

The [request-concurrency-queue source](../harness-plugins/opencode_v2/request-concurrency-queue/src/index.ts) is the layout, storage, and test precedent this package follows. The [retry slot release](archive/plugin_retry-slot-release.md) task documents the `http.request` and `retry` hook fields and the `@opencode/plugin` 2.2.5 types the fallback was first written against. The [plugin hook documentation](https://opencode.ai/docs/build/plugins/server) defines the hook contract this design relies on, including that a hook's changes affect only the outgoing model call. The repo's [Harness plugin packages](../TESTING.md) gate is `make plugin-test`.

## Approach

### Package and configuration

Create a Bun package under `harness-plugins/opencode_v2/smart-compacting/` with a root entry file `index.ts` that default-exports `./src/index.js`, `src/` for the hook wiring and the domain modules, `test/`, `README.md`, and `tsconfig.json`, following the sibling plugin's layout. The `package.json` carries `name` equal to the directory name, `version: 1.0.0`, `"type": "module"`, `"exports": { ".": "./index.ts" }`, a `files` array, `scripts.test: "bun test"`, `scripts.typecheck: "tsc --noEmit"`, and `dependencies["@opencode/plugin"]: "2.4.2"`; `tsconfig.json` sets `strict`, `noEmit`, `moduleResolution: "Bundler"`, `types: ["bun"]`, and includes `src`, `test`, and `index.ts`.

Register it the way every sibling package is registered: add `smart-compacting` to the workspace `harness-plugins/opencode_v2/package.json`'s `workspaces`, `scripts.test`, and `scripts.typecheck`, which is what `make plugin-test` runs; add its row, linking the package's own `README.md`, to the `## Plugins` table in `harness-plugins/opencode_v2/README.md`; and refresh `harness-plugins/opencode_v2/bun.lock` with a plain `bun install` in that directory, because `make plugin-test` installs with `--frozen-lockfile` and fails on a workspace the lockfile does not yet carry.

Read options from `ctx.options` with these defaults, and read them from a dedicated config file for a deployed copy, which receives no `ctx.options`; the README states that precedence:

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

`triggerSize` is a request budget, not a message budget: it is compared against the estimate of the whole request, including system instructions and tool schemas. The 320k default leaves headroom under the gateway's 350k cold limit for estimator drift, which the data shows is real: the gateway counted 28k–86k more tokens than the last measured response in the observed rejections, and one session measured at 338k was refused. `keepSize` is the largest full-turn suffix kept verbatim. `prepareMargin` starts the rolling summary early enough to have it ready before the trigger. `coldAfterHours` mirrors the gateway's cache lifetime. `minTailTurns` is the fewest full turns the kept tail may hold, so a `keepSize` that would cut the tail down to a single short exchange is widened to that many turns instead.

### Estimator

Compute the request size the way the native service does: take the measured token count from the last assistant message (`input + cache.read + cache.write + output + reasoning`), add a character-based estimate of every message after it, and add the estimated size of `event.system` and `event.tools`. Read the measured value through `ctx.session.context` or track it from the event stream, because the `context` hook carries no usage field. Over-estimate rather than under-estimate; `triggerSize` carries the safety margin.

### Keep boundary

Walk backward from the last message, accumulating the estimated tokens of each full turn, and stop before adding the next turn would exceed `keepSize`. Then move the cut forward to the nearest user message so the kept suffix starts a turn, and widen it to `minTailTurns` turns when the cut would otherwise leave fewer. Never split a tool call from its result. When the last turn alone exceeds `keepSize`, keep it whole and record a warning; the alternative is an invalid request. The result is the largest full-turn suffix whose size is at most `keepSize`, or the whole last turn when it alone is larger — the same shape as the native keep boundary.

### Rolling summary

Maintain one held summary per session in `ctx.storage`, keyed by the session ID, and record the covered range, the model reference, a hash of the initial instructions, the first message ID, and the tail length at preparation time.

- Start preparation when the estimate reaches `triggerSize - prepareMargin`, after the turn's response has been delivered rather than inline with it, so summarization never sits on the critical path.
- Summarize everything before the keep boundary, using `ctx.experimental.generate.text`, which generates with a selected model "without creating a session, invoking tools, or adding to session history", so the summary request cannot pollute the transcript or trigger the session's own hooks. Prefer the session's model; allow the compaction agent's configured model, read through `ctx.agent.get("compaction")?.model`, to override it. Put the summarization instruction after the transcript, so the prompt stays a true prefix of the conversation and the warm prompt cache serves it; an instruction at the front changes the prefix and turns a cached read into a full-price request.
- When new messages push the boundary forward, summarize only the delta and extend the held summary. Re-summarize from scratch when the model, the initial instructions, or the first message changed, because the prefix is no longer the one the summary covers.
- Extend the summary from the stored original messages, never from the previous summary text: one level of compression applied to originals, so the held summary cannot become a summary of a summary.
- Invalidate the held summary when the tail since its covered range exceeds `keepSize`, so the summary never leaves an uncovered gap.
- Persist the held summary so a restart does not lose it; the native background preparation is memory-only.

### Applying the summary

In the `context` hook, when the cold condition and the trigger both hold, replace `event.messages` with the summary plus the kept tail. This is a per-request view, not a rewrite of history: OpenCode's documented hook contract is that "changes affect only the outgoing model call, not persisted history or configuration", so the session keeps every original message and the substitution can be applied to one request and not the next. Append the summary to `event.system` as a `SystemPart` of type `text` rather than splicing a message into the transcript: the system part avoids role-alternation and tool-pairing constraints, and the native system prompt is already outside the summarized region. Pin the spec and guardrails with `ctx.session.instructions.entry.put`, which takes `{ sessionID, key, value }` and renders the entry as a `<context key="...">` block in the session's instructions, so they survive every substitution.

Register the substitution on `context` only. `context`, `compaction`, `generate`, and `title` are separate hooks for separate request kinds, and `context` alone covers the agent loop including tool-driven continuations; a plugin that also rewrote `compaction` or `title` requests would compact a compaction.

### Cold trigger and fallback

Track the last request time per session in storage. Treat the request as cold when the idle time exceeds `coldAfterHours`, or when the model, the initial instructions, or the first message changed since the last request. With `autoCompact: false`, substitute only when the request is both cold and over `triggerSize`; leave a warm request alone even above the trigger. With `autoCompact: true`, substitute whenever the request exceeds `triggerSize`.

Coldness is inferred, not observed: the plugin cannot see the gateway's cache, so it reads idle time and prefix identity. The two error modes are asymmetric and both are acceptable — an early substitution costs one unnecessary cache miss on an otherwise warm request, and a late one costs one rejected request that the native overflow recovery absorbs. The second is why the fallback below exists.

Because the native overflow path bypasses the `retry` hook, the plugin cannot wait for the rejection. It predicts instead. Register `http.response` to record a rejection by its status — a 413, or a 4xx whose body names the 350,000 limit — or by OpenCode's context-overflow classification, and set a force flag for the next request. Do not match on `cold_request_too_large`: no captured response carries it. Register the `compaction` hook to return the held summary through `event.result` when the native overflow recovery does run. That gives the first missed prediction a better summary than the native emergency path, and every later request the predictive path.

### Keep the native mechanisms out of the way

Leave OpenCode's `compaction.auto` at `true` and keep its threshold unreachable: the model's declared 1M window with the default buffer yields roughly 850k, and the native background preparation then starts near 790k, so neither fires before a 350k cold rejection. The native overflow recovery remains as the safety net for a missed prediction. Do not set `auto: false`: it also disables the overflow recovery and the native background preparation, so a missed prediction becomes a hard error. Keep `compaction.keep.tokens` at 60k so the native fallback and a manual `/compact` retain the same tail the plugin uses.

**Out of scope:**

- Changing the gateway, its plan, or its limits.
- Replacing OpenCode's built-in compaction, or editing OpenCode or the `@opencode/plugin` API.
- Slicing inside a message or splitting a tool call from its result.
- A TUI surface, a status indicator, or a per-session dashboard.
- Automatic plan upgrades or provider negotiation.

## Acceptance

- `harness-plugins/opencode_v2/smart-compacting/` exists with a root `index.ts` default-exporting `./src/index.js`, `src/`, `test/`, `README.md`, `tsconfig.json`, and a `package.json` that carries `exports`, `files`, `scripts.test`, `scripts.typecheck`, and `@opencode/plugin: 2.4.2`; `harness-plugins/opencode_v2/package.json` lists `smart-compacting` in `workspaces`, `scripts.test`, and `scripts.typecheck`; `harness-plugins/opencode_v2/bun.lock` is refreshed so `bun install --frozen-lockfile` succeeds; the workspace `harness-plugins/opencode_v2/README.md` `## Plugins` table carries its row linking the package README; and `make plugin-test` runs its `test` and `typecheck` scripts.
- A keep-boundary test over a fixture of user, assistant, and tool messages passes: the kept suffix begins at a user message, no tool-call/result pair is split, its estimated size is at most `keepSize`, it holds at least `minTailTurns` turns, and a single trailing turn larger than `keepSize` is kept whole and reported. The test fails against a naive tail slice.
- An options test passes: the defaults apply with no configuration, `ctx.options` overrides them for a source install, and the config file overrides the defaults when `ctx.options` is absent.
- An estimator test passes: the estimate equals the sum of the system, tools, and message estimates, and the measured value is taken from the last assistant message's usage.
- A rolling-summary test passes: the held summary is reused when the model, instructions, first message, and tail are unchanged; it is extended by only the delta when the boundary moves; it is regenerated when the model, instructions, or first message changes; and it is invalidated when the tail exceeds `keepSize`.
- A trigger test with a fake clock passes: a session idle 3 hours and over `triggerSize` is not substituted with `autoCompact: false`; the same session idle 5 hours is substituted; `autoCompact: true` substitutes at `triggerSize` while warm; a warm session over `triggerSize` is left untouched with the default.
- An apply test passes: the substituted request contains the system prompt, the summary as a `SystemPart` text part, and the kept tail; no tool pair is split; the summary text is the held summary, not a fresh model call; and the hook mutates only the event it receives and writes nothing back to the session's stored messages.
- A hook-scope test passes: the plugin registers `context`, `compaction`, and `http.response`, and a compaction or title request is never rewritten.
- A no-compounding test passes: extending the held summary summarizes only messages after the covered range, and the previous summary text is never passed to the summarizer.
- A fallback test passes: a simulated 413 sets the force flag, the next request substitutes, and the `compaction` hook returns the held summary through `event.result` and skips the model call; a simulated 200 does not set the flag.
- An integration test with a fake OpenAI-compatible provider passes: the provider rejects a request carrying more than 350,000 new tokens when the session has been idle more than 4 hours; the session grows past 350,000 tokens while warm without a substitution, idles, resumes, and the first resumed request is accepted; the fake provider records no rejected request.
- `make plugin-test` passes at the repository root, and `bun test` plus `bun run typecheck` pass inside the package.
- `README.md` states the option defaults and where they are read from, the cold-trigger rule, the native-versus-plugin delta for 2.4.2 including its background preparation starting near `threshold - 60k`, the conditions under which the plugin is worth enabling, and the measured basis from `## Goal` with its date.
- The working tree changes only under `harness-plugins/opencode_v2/smart-compacting/`, `harness-plugins/opencode_v2/package.json`, `harness-plugins/opencode_v2/README.md`, and `harness-plugins/opencode_v2/bun.lock`; the gateway and the OpenCode installation are untouched.
