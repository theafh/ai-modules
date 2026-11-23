---
description: "Keep request-concurrency-queue status within its declared schema and render an exhausted token bucket red, so a saturated provider does not fail validation or show green."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-23T10:01:27Z
updated: 2026-11-23T15:47:30Z
status: implemented
reported-by: Andreas Hoffmann
implemented-by: "Andreas Hoffmann"
design-extended: false
---

# Status: clamp utilization, colour tokens by remaining

## Goal

`utilization` never exceeds the `maximum: 1` the RPC schema declares, including when adaptive has lowered the effective maximum below the active count, and the token-budget colour runs green when the bucket is full and dark red when it is empty.

## Context

`harness-plugins/opencode_v2/request-concurrency-queue/src/store.ts`: `snapshotOf` computes `utilization: max === 0 ? 0 : active / max` from the scheduler's effective maximum. Adaptive halving (`recordFailure` → `setMax(floor(max / 2))`) or a dialog reduction can leave `active > max`, producing a value above 1. `demand` uses the same ratio and the schema leaves it unbounded.

`src/rpc.ts`: `providerStatusSchema` declares `utilization: { type: "number", minimum: 0, maximum: 1 }`. The package carries no JSON-Schema validator, and `@opencode/plugin` re-exports only types, so the schema can be asserted against `statusRpc.methods.status.output` but not executed here.

`src/status.ts`: `tokensColor` is `loadColor((tokensAvailable / tokens) * 100)`, and the load scale runs dark green at 0% through light green, light yellow, orange, light red at 250%, dark red at 300%, dark pink at 350%, and magenta at 400% and beyond. An exhausted bucket (0%) therefore renders dark green, while the field's own comment says "green when full and red when nearly empty". The existing `test/status.test.ts` assertion for a 75%-full bucket expects `loadColor(75)`, which the old `share * 100` mapping and the new `(1 - share) * 300` mapping both produce, so it discriminates neither and must be kept and joined by full, half, and empty cases. `providerRow` also feeds `loadColor(provider.utilization * 100)` into `utilizationColor`, and the panel's Util cell renders `percent(provider.utilization)`. The Util cell's tooltip in `src/gui.tsx` reads `Utilization: active / max`.

`dist/gui.cjs` is tracked, is the GUI surface the desktop loads, and embeds the exact `tokensColor` expression, so it must be rebuilt with the source change.

The package README describes utilization as `active / max` in three passages, and the wiki concept page in two.

Verified by reading the code above; the review that produced this task recorded `4 / 2 = 2.0` for utilization and a dark-green colour at an exhausted bucket. Baseline: `bun test` and `bunx tsc --noEmit` pass in the package.

## Approach

- In `snapshotOf`, clamp `utilization` to `[0, 1]`. Keep `demand` as the unbounded demand ratio so the panel still shows an over-subscribed queue.
- In `src/status.ts`, change `providerRow`'s `utilizationColor` from `loadColor(provider.utilization * 100)` to the raw ratio `loadColor((provider.active / provider.max) * 100)`, yielding `loadColor(0)` when `max` is 0. The load scale is defined to 400% precisely so an over-subscribed provider renders hot rather than green; with the clamped field it would render `loadColor(100)`, light green. The Util cell's text still reads the clamped `utilization`, so it shows `100%` for an over-subscribed provider while its colour stays hot; that split is intended. Update the cell's tooltip to `Utilization: active / max, capped at 100%` and the `ProviderStatus.utilization` doc comment to `min(1, active / max), or 0 when max is 0`.
- In `src/status.ts`, map `tokensColor` from the remaining share onto the load scale by `loadColor((1 - share) * 300)`, so a full bucket is `loadColor(0)` and an empty one is `loadColor(300)` (dark red). Keep the `tokens === 0 ? ""` branch for a provider with no budget. Update the field's comment to describe the mapping.
- Join the existing 75%-full `test/status.test.ts` assertion with full, half, and empty cases that discriminate the two mappings.
- Rebuild `dist/gui.cjs` with `bun run build:gui`.
- Refresh the utilization passages to the split the panel actually renders: the snapshot field-list passage in the package README and in the wiki concept page describe the bounded `utilization` field, while the colour passages in both keep stating that the slot count and the Util cell's colour follow the raw `active / max` ratio and gain the note that the Util cell shows the bounded value. Add the token-colour mapping to the load-scale sentence in both the README and the wiki, and append the required entry to `wiki/log.md` for the page update.

**Out of scope:** Changing the load scale's anchor points, and changing the RPC schema's `demand` bound.

## Acceptance

- A store test passes: with `active` forced above the effective maximum by calling `setMax` below the active count, `snapshotOf(...).providers[0].utilization` is `1` and `demand` remains above `1`.
- A status test passes: the retained 75%-full assertion still passes, and it is joined by a full bucket rendering `loadColor(0)`, a half-full bucket rendering `loadColor(150)`, and an empty bucket rendering `loadColor(300)`, with the three new values distinct.
- The `tokensColor` field comment describes the remaining-share mapping.
- A status test passes: a fixture with `active: 4`, `max: 2`, and the clamped `utilization: 1` renders `utilizationColor` equal to `loadColor(200)`, proving the colour follows the raw ratio rather than the clamped field.
- A schema test passes: `statusRpc.methods.status.output` declares `utilization` with `maximum: 1`, and the clamped snapshot's value is at most 1.
- The committed `dist/gui.cjs` matches a fresh build of `src/gui.tsx`, proven by the existing bundle-drift test.
- The package README's snapshot field-list passage describes the bounded `utilization` field.
- The package README's colour passages still state that the slot count and the Util cell's colour follow the raw `active / max` ratio and note that the Util cell shows the bounded value.
- The package README's load-scale sentence carries the token-colour mapping.
- The wiki concept page's snapshot field-list passage describes the bounded `utilization` field.
- The wiki concept page's colour passages still state that the slot count and the Util cell's colour follow the raw `active / max` ratio and note that the Util cell shows the bounded value.
- The wiki concept page's load-scale sentence carries the token-colour mapping.
- The Util-cell tooltip reads `Utilization: active / max, capped at 100%`, and the `ProviderStatus.utilization` comment reads `min(1, active / max), or 0 when max is 0`.
- `wiki/log.md` carries the required entry for the page update.
- The diff this task produces touches no tracked file outside `harness-plugins/opencode_v2/request-concurrency-queue/`, `wiki/concepts/request-concurrency-queue.md`, `wiki/log.md`, and this task file.
