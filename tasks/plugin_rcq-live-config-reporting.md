---
description: "Make the request-concurrency-queue config dialog report and apply the live store settings, so an options-configured install keeps its token budget, context cap, and hostAware on Save."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-23T10:01:27Z
updated: 2026-11-23T11:15:39Z
status: ready
reported-by: Andreas Hoffmann
---

# Config dialog must show and apply the live settings

## Goal

`config()` reports the settings the running store is actually using, whichever source configured them (plugin options, environment, or config file). Saving from the dialog applies the edited `hostAware` to the running gate and never discards an options-sourced token budget or context cap. A genuine reload adopts a changed `adaptive` flag and a removed `subagents` section; a second location opening in the same process does not.

## Context

`harness-plugins/opencode_v2/request-concurrency-queue/src/index.ts`:

- `configSnapshot(store, fileConfig)` builds `tokens`, `scheduler`, and `subagents.hostAware` from `fileConfig` alone, while `providers` and `adaptive` come from the store.
- The plugin loads with `adoptStore(resolveProviderLimits(...), resolveTokenBudgets(...), resolveScheduler(...), resolveSubagents(...))`, and those resolvers prefer `ctx.options` over the file. For a package install configured through options with no file, the store holds the budget and cap while `config()` reports `tokens: {}`, `contextCapacity: 0`, `hostAware: false`.
- `saveConfig` validates and applies that snapshot, so `tokens: {}` calls `scheduler.clearBudget()` and `contextCapacity: 0` clears the cap. It also rebuilds `tokens` from the input alone, so a file entry for a provider the store does not gate is deleted on an unchanged save.

`src/store.ts`: `applyConfig` applies `maxSlots` and `setMax` but has no path for `hostAware`. `adoptStore` calls only `setMax`, and it runs for every plugin instance, not only a reload, so it must not let a second location overwrite the process-wide `adaptive` flag or drop the gate.

`src/subagents.ts`: `hostAware` is `readonly` and only `max` has a setter, so a saved change reports `ok: true` while the live gate keeps the old value.

`src/scheduler.ts` exposes `contextCapacity`, the budget snapshot, and `budgetSafetyFactor`, but no getter for `contextCeiling`, `reserveShare`, `smallShare`, `agingMs`, `queueDeadlineMs`, the breaker settings, or the budget's `refillPerMinute`.

`src/budget.ts` stores `refillPerMs`, not `refillPerMinute`, and `saveConfig` requires `refillPerMinute` to be an integer, so reconstructing `500000/60000*60000` yields `500000.00000000006` and an unchanged save of a 500k budget is rejected.

The live task [config validation and save](archive/plugin_rcq-config-validation-and-save.md) rewrites `saveConfig`'s write/apply ordering: it reads the current file bytes, renames the temporary file into place, then applies to the store, with an injected `io` seam and a restore on an apply throw. This task's preserve-uncovered-entries merge sits inside that post-change flow, in the step that builds the merged object before the temporary file is written, and restores no part of the old ordering.

The provider-ceiling-and-dialog task also edits `src/gui.tsx` and `test/panel.test.ts`, and its loaded-form split shares `ConfigForm`'s composition site with this task's Subagents-section extraction. The two compose in either order: whichever lands second places its structure around the other's.

`test/config.test.ts`'s case "reads the token budget from the file config" pins the current file-sourced behaviour and is superseded by this change. `test/fixes.test.ts`'s "the settings form reads the file as it is now" asserts a scheduler cap that now comes from the store; rename it and refresh its comment in the same edit.

Verified by reading the code above; the review that produced this task recorded an options budget of 500k with a 900k cap reading back as `{}`/`0`/`false`, and a live budget of `NONE` plus cap `0` after Save.

## Approach

- Add read accessors to `RequestScheduler` for `contextCeiling`, `reserveShare`, `smallShare`, `agingMs`, `queueDeadlineMs`, and the breaker settings, plus a `budgetConfig` getter returning `capacity`, `refillPerMinute`, and `safetyFactor`, or `undefined` when no budget is attached.
- Have `TokenBudget` retain the `refillPerMinute` it was constructed with and update it in `reconfigure`, so `budgetConfig` returns the exact integer after a refill change and an unchanged save passes validation.
- Build `configSnapshot` from the store: each provider's tokens from its live budget, `scheduler` from the first provider in `store.providers` — every provider starts from the one configured scheduler and `applyConfig` writes one scheduler config back to all, so a diverged adaptive cap is reported as that provider's live value — and `subagents.hostAware` from the gate. When `store.providers` is empty, report the zeroed defaults the function reports today (`contextCapacity` 0, `contextCeiling` 0, `reserveShare` 0.25, `smallShare` 0.1, `agingMs` 30000, `queueDeadlineMs` 0, breaker 3 / 60000 / fail) rather than reading a provider. For a per-provider `tokens` entry with no live budget, report no entry rather than a fabricated default.
- Make `saveConfig` preserve file entries the snapshot does not cover, so a provider outside the current gate keeps its token budget.
- Make `SubagentGate.hostAware` mutable through `setHostAware`, which serves the queue when it changes, and call it from `applyConfig` and `adoptStore`. Add a read accessor for the current value.
- In `src/gui.tsx`, extract the Subagents section into an exported pure component taking `{ max, hostAware, onChange }`, add a `hostAware` checkbox to it, and have `ConfigForm` compose it. That gives the panel test a renderable seam, because `ConfigForm` fills its snapshot in an async effect that `renderToString` never runs. Also export a pure handler that returns the edited `subagents` object for a given checkbox value, so the edit payload is provable without event simulation. Rebuild `dist/gui.cjs` with `bun run build:gui` so the committed bundle carries the control, and add the checkbox to the README's dialog-field list.
- In `adoptStore`, adopt `adaptive` and a removed `subagents` section only on a genuine reload — capture the pending `disposeTimer` before the `existing` branch, meaning refcount had reached zero. A second live location leaves those unchanged, matching the documented first-instance-wins posture, and `setHostAware` follows the same rule.
- Keep `configSnapshot`'s `fileConfig` parameter and the `currentFileConfig()` re-read: the provider-ceiling-and-dialog task uses that input for the file-sourced provider set. Only the `tokens`, `scheduler`, and `subagents.hostAware` reads move to the store.
- Rewrite the superseded `test/config.test.ts` case against a store-sourced budget.

**Out of scope:** Adding provider add/remove controls to the dialog (owned by the sibling task [provider ceiling and dialog](plugin_rcq-provider-ceiling-and-dialog.md), which owns the wider loaded-form split for the provider rows), and changing the config-file schema.

## Acceptance

- A config test passes: a store created with an options-sourced budget of capacity 500000, refill 500000, and `safetyFactor` 1.2, a context cap of 900000, a ceiling of 1800000, `reserveShare` 0.3, `smallShare` 0.15, `agingMs` 45000, `queueDeadlineMs` 240000, and a breaker of threshold 4 / cooldown 90000 / mode `wait`, with no config file, returns every one of those literal constants, and a provider with no live budget reports no `tokens` entry.
- A config test passes: a store whose gate was built with `hostAware: true` and no config file reports `subagents: { max, hostAware: true }` from `configSnapshot`, proving the value comes from the gate rather than the file.
- A config test passes: a config file sourced budget reaches the store and is reported from it, so the file and options paths converge on one reported value.
- A config test passes: a store with no providers returns the zeroed scheduler defaults from `configSnapshot` rather than throwing.
- A config test passes: `configSnapshot` still accepts the file config input and the `currentFileConfig()` re-read still supplies it.
- A config test passes: saving that snapshot unchanged returns `ok: true`, writes the same capacity, refill, safety factor, cap, ceiling, `reserveShare`, `smallShare`, aging, deadline, and breaker to the file, and leaves the live budget capacity and context cap unchanged.
- A config test passes: after a refill change applied through `reconfigureBudget`, `configSnapshot` reports the new integer refill, and an unchanged save does not revert it.
- A config test passes: a config file holding a token budget for a provider the store does not gate keeps that entry after an unchanged save.
- A config test passes: a gate built with `hostAware: true` and a fixed probe allowing fewer than `max` reports the probe-derived `capacity()` and holds a queued waiter; saving `hostAware: false` raises `capacity()` to `max` and admits the waiter; saving `true` again returns `capacity()` to the probe-derived value.
- A panel test passes through the existing `renderToString` harness: the exported Subagents section renders a `hostAware` checkbox beside the `max` field, the checkbox's `checked` state follows the `hostAware` prop, and the exported pure handler returns the edited `subagents` object for a toggled value. `ConfigForm` composes the section with `set(["subagents", "hostAware"], …)`. The committed `dist/gui.cjs` matches a fresh build, and the README's dialog-field list names the checkbox.
- A store test passes: `adoptStore` on a genuine reload with `adaptive` flipped and a retained `subagents` section whose `hostAware` changed applies both.
- A store test passes: `adoptStore` on a genuine reload whose configuration carries no `subagents` section clears the gate.
- A store test passes: `adoptStore` for a second live location with no `subagents` section leaves the existing gate, its `hostAware`, and `adaptive` in place.
- The superseded `test/config.test.ts` case is rewritten to the store-sourced expectation, the `test/fixes.test.ts` case "the settings form reads the file as it is now" is renamed and its comment refreshed, and no test asserts the file-sourced token snapshot.
- The diff this task produces touches no tracked file outside `harness-plugins/opencode_v2/request-concurrency-queue/` and this task file.
