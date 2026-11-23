---
description: "Make a saved provider maximum the new ceiling in the request-concurrency-queue store, and expose provider add/remove in the config dialog the README already documents."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-23T10:01:27Z
updated: 2026-11-23T17:57:34Z
status: implemented
reported-by: Andreas Hoffmann
implemented-by: "Andreas Hoffmann"
design-extended: true
---

# Provider ceiling and dialog provider editing

## Goal

Saving a provider maximum updates the running limit's configured ceiling, so the status snapshot, `config()`, the store fingerprint, and adaptive recovery all agree with the saved value. The config dialog can add and remove a provider, making the existing `restartRequired` path reachable.

## Context

`harness-plugins/opencode_v2/request-concurrency-queue/src/store.ts`:

- `ProviderLimit.maxConcurrency` is `readonly`, and `applyConfig` reconfigures the scheduler but never writes the limit's configured ceiling.
- `snapshotOf` reports `ceiling: limit.maxConcurrency`, so after a save it still shows the old configured value while `max` shows the new one.
- `Store.fingerprint` is `readonly` and set once in `createStore`, so `adoptStore` compares a reload against the load-time value.

`src/index.ts`:

- `configSnapshot` reports `providers[providerID] = limit.maxConcurrency`, so the dialog re-shows the old maximum after a successful save.
- `recordSuccess` caps adaptive recovery at `limit.maxConcurrency`; after lowering `8 → 2` the scheduler walks back up to 8.

`src/gui.tsx`: the provider section iterates `Object.keys(current().providers)` with a number field per provider and offers no way to add or remove one. The form starts at `form() === null` and fills from an async effect, and Solid does not run effects under `renderToString`, so the existing `test/panel.test.ts` harness cannot render the provider section as it stands. The token-budget section iterates `Object.keys(current().tokens)` separately, so removing a provider would leave its budget behind.

README's "Configuring from the window" section states that adding or removing a provider reports `restartRequired`, which no dialog control reaches today.

Verified by reading the code above and by a store reproduction: after `applyConfig` from `8` to `4`, `limit.maxConcurrency` is 8, `scheduler.maxConcurrency` is 4, `snapshotOf(...).ceiling` is 8, and `store.fingerprint` is `acme=8`. Baseline: `bun test` and `bunx tsc --noEmit` pass in the package.

The archived task [config validation and save](archive/plugin_rcq-config-validation-and-save.md) changes `applyConfig` so in-place edits apply before a provider-set change reports `restartRequired`. That change supersedes the early return; this task builds on the post-change behaviour and must not restore it.

The archived task [live config reporting](archive/plugin_rcq-live-config-reporting.md) also edits `src/gui.tsx`, `test/panel.test.ts`, and `configSnapshot`, and its Subagents-section extraction shares `ConfigForm`'s composition site with this task's loaded-form split. It has landed: `configSnapshot` now reports the store's settings, `saveConfig` merges the file's token entries the store does not cover into a file-only map, and `SubagentsSection` is an exported component.

That landed merge runs on every save, so it now defeats this task's provider removal at the persistence layer: with `beta` removed from `input.providers` and `input.tokens`, `saveConfig` returns `restartRequired: true`, writes `providers {acme: 2}`, and restores `tokens.beta` from the file. Scope the merge so a removed provider's budget is not written back — for example, merge only entries whose provider is still in the saved provider set — and prove the removal drops both the maximum and the token entry, while the ungated-provider preservation the sibling task added still holds.

## Approach

- In `src/store.ts`, make `ProviderLimit.maxConcurrency` and `Store.fingerprint` assignable. In `applyConfig`, write the ceiling and the fingerprint only after the scheduler `reconfigure` call has succeeded, and recompute the fingerprint from the store's own provider map after the loop, so it records only the providers actually applied.
- Keep the server-side provider-set deferral: a changed set still reports `restartRequired`, with the in-place edits applied first per the sibling task.
- In `src/gui.tsx`, extract the provider add/remove edit into an exported pure helper that takes the current `providers` and `tokens` maps and returns the edited pair, and extract the provider section into an exported component so the rows and the add row render under `renderToString` without the fetch effect. Adding a provider appends only its maximum and no `tokens` entry, because `saveConfig` and the RPC token schema both require a capacity of at least 1 and a token budget is optional per provider. Removing a provider drops both its maximum and its `tokens` entry. Refuse an empty or duplicate provider ID in the helper, before a save is attempted.
- Have `configSnapshot` report the provider set from the config file only when `options.providers` is unset and the file carries a `providers` value — matching the `options.providers ?? fileConfig?.providers ?? envProviders()` order — and from the store otherwise. Take that condition as a parameter so the config test can call the function directly. Resolve the file's provider value through `resolveProviderLimits` at the same shared default the store loaded with (`options.maxConcurrency`, then the file's `maxConcurrency`, then the environment), passing that value or `options` into `configSnapshot` beside the condition, since the file value may be a `string[]` and the snapshot needs a `Record<string, number>`.
- Clamp the effective scheduler maximum to the lower of the new ceiling and the pre-save effective value, only when that pre-save value sat below the previous ceiling **and** the save keeps adaptive on, reading both before `reconfigure` assigns the new one. An adaptive-lowered limit then survives a raise, a lowering cannot leave the effective maximum above the new ceiling, an ordinary raise takes effect immediately, and a save that turns adaptive off restores the configured ceiling.
- Add a pure save-disabled predicate exported from `src/gui.tsx` that takes the last save result and returns whether Save is disabled, and drive the button's `disabled` binding from it, so the panel harness can assert the state.
- Name the rebuild: `src/gui.tsx` is bundled to `dist/gui.cjs`, and `test/panel.test.ts` fails until that bundle is regenerated with `bun run build:gui`. Add the new controls' styles to `src/panel-style.ts`. The add row takes a provider ID and a maximum, both required, with the maximum a positive integer.
- Settle the post-save display: the notice states that the provider set needs a restart, and Save is disabled from the predicate until the dialog is reopened against the file's set.

**Out of scope:** Applying a changed provider set without a restart, changing the adaptive recovery streak, and adding a DOM test dependency.

## Acceptance

- A store test passes: `applyConfig` from `8` to `4` sets `limit.maxConcurrency` to 4, `scheduler.maxConcurrency` to 4, `snapshotOf(store).providers[0].ceiling` to 4, and `store.fingerprint` to `acme=4`.
- A store test passes: a save that only raises the ceiling `2 → 8` with `adaptive: false` sets `scheduler.maxConcurrency` to 8 and `snapshotOf(...).providers[0].max` to 8.
- A store test passes: with `adaptive` on and the effective maximum lowered to 4 under a ceiling of 8, a save raises the ceiling to 12, the effective maximum stays 4, and `snapshotOf(...).providers[0].ceiling` is 12.
- A plugin test passes: after that save, a recovery streak through the `http.response` harness climbs the effective maximum back to 12.
- A store test passes: with adaptive on and the effective maximum lowered to 4 under a ceiling of 8, a save with `adaptive: false` and the ceiling still 8 sets `scheduler.maxConcurrency` and `snapshotOf(...).providers[0].max` to 8.
- A plugin test passes: after a save lowers the ceiling `8 → 2`, adaptive recovery steps stop at 2, and after a save raises it `2 → 8` recovery reaches 8.
- A config test passes: `configSnapshot` after a save reports the saved maximum, and a second save with no further edit leaves it unchanged.
- A config test passes: with `options.providers` set, `configSnapshot` reports the store's provider set even when the file carries a different one; a file whose `providers` is a `string[]` resolves to a `Record<string, number>` at the shared default the store loaded with, so `options.maxConcurrency: 4` with a file list `["acme", "beta"]` reports `{ acme: 4, beta: 4 }`; and a plugin test through the RPC handler observes the file branch when `options.providers` is unset and the current file carries `providers`.
- A store test passes: with `adaptive` on and the effective maximum equal to the ceiling of 8, a save raises the ceiling to 12 and `scheduler.maxConcurrency` is 12 immediately.
- A pure-helper test passes: adding a provider appends its maximum and no `tokens` entry, removing a provider drops both its maximum and its token entry, and an empty or duplicate ID is refused before a save is attempted.
- A save-flow test passes: adding a provider and saving yields `restartRequired: true`; `configSnapshot` then reports the file's pending provider set, and saving again leaves the file's provider set intact.
- A predicate test passes: the exported save-disabled predicate returns disabled after a `restartRequired` result and enabled otherwise.
- A panel test passes through the existing `renderToString` harness, using a pending-set snapshot as its fixture: the provider section renders one row per provider, a remove control per row, and an add row.
- A store test passes: a save that adds a provider while lowering a shared provider's ceiling leaves `store.fingerprint` at the shared providers' applied values, so a later reload still reports the mismatch.
- `dist/gui.cjs` is rebuilt, the bundle-match test in `test/panel.test.ts` passes, and the new controls' styles are present in `src/panel-style.ts`.
- README's "Configuring from the window" paragraph and the rendered form agree: every edit the README names is present in the form.
- The diff this task produces touches no tracked file outside `harness-plugins/opencode_v2/request-concurrency-queue/` and this task file.
