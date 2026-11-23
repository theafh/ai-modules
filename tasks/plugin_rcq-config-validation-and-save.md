---
description: "Close request-concurrency-queue config validation gaps and make Save total: no throws out of the RPC, no half-applied store, no silently dropped edits."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-23T10:01:27Z
updated: 2026-11-23T12:05:13Z
status: implemented
reported-by: Andreas Hoffmann
implemented-by: "Andreas Hoffmann"
design-extended: false
---

# Config validation and Save must be total

## Goal

A `scheduler` object that omits `contextCapacity` loads with a default instead of throwing, an invalid `safetyFactor` is rejected rather than silently disabling token charging, Save always returns a `SaveResult`, and no reachable save leaves the file and the running store describing different edits — with the provider-set change as the one deliberate exception that reports `restartRequired`, and an unreachable apply throw bounded by restoring the file.

## Context

`harness-plugins/opencode_v2/request-concurrency-queue/src/index.ts`:

- `resolveScheduler` requires `configured.contextCapacity` to be a non-negative integer and throws when it is absent, unlike `contextCeiling`, `reserveShare`, `smallShare`, `agingMs`, `queueDeadlineMs`, and `breaker`, which are all optional. A `scheduler` object holding only `{ "queueDeadlineMs": 240000 }` therefore fails to load; a whole config file holding only that key never reaches `resolveScheduler` at all.
- `SchedulerConfig.contextCapacity` is declared required in `src/store.ts`, so the partial object is also a type error under `strict`.
- `resolveTokenBudgets` copies `safetyFactor` without validating it. `TokenBudget` defaults it with `?? 1`, so `safetyFactor: 0` stays `0` and `estimateTokens` returns `0` for every byte count, silently turning off budget charging. `NaN` reaches `estimateTokens` and propagates `NaN` into the bucket's `available`.
- `saveConfig` calls `loadConfigFile(filePath)` while building the merged object and calls `renameSync` at the end; both sit outside the `try` that returns a `SaveResult`. `renameSync` is imported directly from `node:fs`, so a test cannot intercept it without a seam.
- `applyConfig` runs before `renameSync`, so a rename failure leaves the store running the new configuration while the file still holds the old one — contradicting the invariant stated beside the step, "If applying fails, the file is removed so neither side is left describing a state the other never reached", and README's "**Save** writes the config file atomically and applies the change to the running store".

`src/store.ts`: `applyConfig` returns `{ restartRequired: true }` as soon as the provider set differs, before applying any token, scheduler, subagent, or adaptive edit in the same save.

The live task `plugin_rcq-provider-ceiling-and-dialog` also edits `applyConfig`, and its Approach now reads the post-change behaviour: the in-place edits apply first and only the provider-set change is deferred. That supersession is already recorded there, so this task does not edit that file. The live task [live config reporting](plugin_rcq-live-config-reporting.md) also edits `saveConfig`, `applyConfig`, and `TokenBudget`; its merge sits inside this task's post-change flow, and the two compose in either order.

Verified by reading the code above. Baseline: `bun test` and `bunx tsc --noEmit` pass in the package.

## Approach

- In `resolveScheduler`, default a missing `contextCapacity` to `0`, and widen `SchedulerConfig.contextCapacity` to optional in `src/store.ts` so a partial `scheduler` object type-checks. Keep the integer check for a present value.
- In `resolveTokenBudgets` and in `TokenBudget`'s constructor and `reconfigure`, reject a `safetyFactor` that is present but not a finite number greater than zero; an absent factor keeps the `?? 1` default at all three sites, so a budget holding only `capacity` and `refillPerMinute` still loads.
- In `saveConfig`, give the file operations a seam: an optional final `io` parameter carrying `readFile` and `rename` defaults, so a test can force each failure. Wrap the config read and the rename in error-to-`SaveResult` handling: the read returns the `Failed to read <path>` error form, and the rename returns its own message naming the rename and unlinks the temporary file.
- Make the save consistent on both sides. Read the current file bytes before writing, rename the temporary file into place, then apply to the store. On a rename failure neither side has changed. On an apply throw, restore the previous bytes — or remove the written file when no previous file existed — and return `{ ok: false }`; the store keeps only the edits applied before the throw, which `saveConfig`'s up-front validation makes unreachable in practice. Rewrite the comment above the save steps, which still says the file is removed on an apply failure, to the new ordering and recovery, and refresh the README sentence that ends "instead of half-applying".
- In `applyConfig`, apply every in-place edit — token budgets, scheduler settings, the subagent gate, and `adaptive` — for providers present in both sets, then return `restartRequired: true` when the sets differ. The provider-set change itself is the deliberate exception: it is written to the file and deferred in the store until a restart.

**Out of scope:** Changing the config file's keys or format, and applying a provider-set change without a restart.

## Acceptance

- A config test passes: `resolveScheduler({}, { scheduler: { queueDeadlineMs: 240000 } })` returns `{ contextCapacity: 0, queueDeadlineMs: 240000 }` rather than throwing, a config file whose `scheduler` object holds only that key loads, and a present `contextCapacity` of `-1` or `1.5` still throws.
- A config test passes: `safetyFactor` of `0`, `-1`, and `NaN` each throw at load with the provider named, a valid factor still applies, and a budget holding only `capacity` and `refillPerMinute` loads with the `?? 1` default.
- A budget test passes: constructing and reconfiguring a `TokenBudget` with `0`, `-1`, or `NaN` throws, and a valid factor still reaches `estimateTokens`.
- A save test passes: a malformed existing config file makes `saveConfig` return `{ ok: false, errors: [...] }` rather than throwing, and the file is unchanged.
- A save test passes with the injected rename forced to fail: `saveConfig` returns `{ ok: false }`, the error names the rename, no temporary file remains, the previous file is unchanged, and the store's effective maximum and context cap are unchanged.
- A save test passes with the store's `scheduler.reconfigure` stubbed to throw after a successful rename: the previous file bytes are restored and `{ ok: false }` is returned.
- A save test passes on a fresh install with no previous file and the store's `scheduler.reconfigure` stubbed to throw: no file remains at `filePath` and `{ ok: false }` is returned.
- A store test passes: a save that changes the provider set and also changes a shared provider's maximum, token budget, context cap, subagent gate, and `adaptive` applies every in-place edit, writes the changed provider set to the file, and returns `restartRequired: true`.
- The stale `test/config.test.ts` case "a failed apply does not write the file" is renamed to describe the written-then-removed flow, and its assertions still pass.
- The code comment above the save steps states the new ordering and recovery, and the README sentence that ended "instead of half-applying" describes the in-place application.
- The diff this task produces touches no tracked file outside `harness-plugins/opencode_v2/request-concurrency-queue/` and this task file.
