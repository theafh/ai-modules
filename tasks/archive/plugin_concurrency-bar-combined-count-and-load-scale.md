---
description: "Drop the Concurrency side tab, show the window-bottom bar as (active + queued)/max, and recolour that count on a six-anchor dark-green-to-dark-red scale."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-11T20:07:23Z
updated: 2026-11-12T04:24:13Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Make the concurrency bar the only desktop surface with a combined load count

## Goal

The window-bottom status bar becomes the plugin's one persistent desktop
surface: the pinned **Concurrency** side tab disappears, so the same state is
not shown in two places at once. Each provider item on the bar collapses to a
single `X/Y` count, where `X` is `active + queued` and `Y` is `max`, so a fully
loaded provider reads `8/8` and an overloaded one reads `12/8`. The `X queued`
segment and the separator before it are gone from the bar.

That `X/Y` string is coloured by its own load, `(active + queued) / max`, on a
six-anchor scale: dark green at 0% warming to light green at 100%, light yellow
at 150%, orange at 200%, light red at 250%, and dark red at 300%, held at dark
red above 300%. Clicking the bar still opens the `Concurrency` dialog with the
full provider table and activity feed, which follows the same scale.

## Context

The plugin lives at `harness-plugins/opencode_v2/request-concurrency-queue/`.
The desktop part is `src/gui.tsx`: it exports `panel` (the pinned side tab),
`StatusBarBody` (the bar), `StatusBar` (the bar's snapshot subscription),
`StatusBody` (the shared table and feed), and `StatusDialog`. The bar currently
renders each provider as `provider · active/max · N queued`, with the two counts
coloured separately.

The snapshot-to-row transform and the colour scale live in `src/status.ts`:
`providerRow` builds `ProviderRow`, and `loadColor(percent)` interpolates HSL
between the four anchors in `LOAD_ANCHORS`. `demand` is already
`(active + queued) / max`, so `demandColor` is the colour the combined count
needs. Styles are in `src/panel-style.ts`, and the desktop loads the prebuilt
`dist/gui.cjs` bundle, never the source.

The bar and its dialog were added by [Add a window-bottom concurrency status
bar](plugin_concurrency-window-bottom-status-bar.md), and the table's
current four-anchor scale by [Lay out the Concurrency panel as a labelled grid
with a load colour scale](plugin_concurrency-panel-layout-and-colour-scale.md).
The wiki concept page `wiki/concepts/request-concurrency-queue.md` and
`wiki/index.md` still describe the side tab and the old scale.

## Approach

**Remove the side tab.** In `src/gui.tsx` delete `statusTab`, `StatusView`, the
exported `panel`, the `Panel`, `PanelProps`, and `PanelTab` imports, and the
`ctx.add(Panel, panel)` call in the default plugin's `setup`. Leave the `Slot`
and `Style` registrations in place, and keep `StatusBody` because the dialog
renders it.

**Show the combined count.** Add `total: active + queued` to `ProviderRow` and
its `providerRow` mapping in `src/status.ts`. In `StatusBarBody`, render each
item as the provider name followed by `${row.total}/${row.max}`, coloured with
`row.demandColor`, and drop the queued span and the separator span. Keep the
full detail in the item's `title` as `${row.total} of ${row.max} slots in
demand`, for example `12 of 8 slots in demand`, so a hover still explains the
number without naming the queued segment the bar no longer shows. Remove the now-unused
`.request-concurrency-bar-sep` rule from `src/panel-style.ts`.

**Recolour the load scale.** Replace `LOAD_ANCHORS` in `src/status.ts` with six
anchors, interpolating hue, saturation, and lightness between neighbours:

| Percent | Colour | HSL |
| --- | --- | --- |
| 0 | dark green | `hsl(145 60% 28%)` |
| 100 | light green | `hsl(120 60% 60%)` |
| 150 | light yellow | `hsl(60 85% 70%)` |
| 200 | orange | `hsl(32 95% 55%)` |
| 250 | light red | `hsl(12 90% 68%)` |
| 300 | dark red | `hsl(0 70% 35%)` |

Hold the 300% anchor for every value at or above 300, and read a negative or
non-finite value as 0. Because `utilizationColor` and `demandColor` both come
from `loadColor`, the bar and the dialog table stay on one scale.

**Update the tests and the shipped bundle.** In `test/status.test.ts`, assert
the six exact anchor colours, the held dark red above 300, the dark green floor
for a negative or `NaN` input, monotonic falling hue across the six anchors, and
`total` on `providerRows`. In `test/panel.test.ts`, replace the side-tab test
with one asserting the module exports no `panel` and that `setup` records no
`Panel` contribution; assert the bar renders `12/8` for `active: 8`,
`queued: 4`, `max: 8` and `8/8` for `active: 6`, `queued: 2`, `max: 8`, contains
no `queued` segment, and carries an inline `hsl(` colour. Change the bundle-load
assertion from `panel: true` to `panel: false`. Run `bun run build:gui` so the
committed `dist/gui.cjs` matches source, and bump `package.json` from `0.5.0` to
`0.6.0`.

**Rewrite the docs in place.** In the plugin `README.md`, rewrite in place every sentence under
`## State and observability` that names the Concurrency tab or the four-anchor
scale: the passage opening "The desktop GUI part ships as the prebuilt
`./gui-experimental` bundle" (the bar is the only persistent surface and shows
the combined `X/Y` count), the sentence "The panel feed is the desktop
observability surface: it shows recent concurrency transitions in the Concurrency
tab" (the bar and its dialog feed are the desktop observability surface), and the
passage opening "The side tab reads the routed session's server with the
session's directory as the RPC location", whose "green at 0%, yellow at 100%,
orange at 200%, and red from 300% on" becomes the six-anchor scale. Keep the log,
snapshot, and "When a status fetch fails, the panel shows `Status unavailable`"
sentences as they are. In
`wiki/concepts/request-concurrency-queue.md`, rewrite in place every passage
that names the Concurrency tab: the feed sentence "The panel feed is the desktop
observability surface: the Concurrency tab lists recent transitions, while `log`
remains for terminal runs", the desktop paragraph opening "A desktop GUI part
ships as the prebuilt `./gui-experimental` bundle", and the `Panel`/`Slot`
passage opening "A desktop status view ships through the V2 GUI plugin `Panel`
and `Slot` APIs". Replace each stale sentence where it stands rather than adding a new paragraph, and bump the page's `updated` date. In `wiki/index.md`, drop the side-tab mention from the request-concurrency-queue entry and advance the header's `Last updated` date. Then append one `update` entry to `wiki/log.md` in its existing `## [YYYY-MM-DD HH:MM] update | <subject>` form, listing `concepts/request-concurrency-queue.md` and `index.md`.

**Out of scope:**

- Changing queue, limiter, retry, timeout, or slot-release behaviour.
- Making the colour anchors or the combined-count formula configurable.
- Changing the dialog's columns; it keeps separate active, queued,
  utilization, and demand cells.

## Acceptance

- `bun test test/status.test.ts` asserts `loadColor(0)`, `(100)`, `(150)`,
  `(200)`, `(250)`, and `(300)` equal the six anchor strings in the table, that
  `loadColor(450)` equals `loadColor(300)`, that `loadColor(-10)` and
  `loadColor(Number.NaN)` equal `loadColor(0)`, and that hue strictly falls
  from anchor to anchor.
- `bun test test/status.test.ts` asserts a provider with `active: 2`,
  `queued: 1`, `max: 4` gets `total: 3`, `demandColor` equal to `loadColor(75)`,
  and `utilizationColor` equal to `loadColor(50)`.
- `bun test test/panel.test.ts` asserts the GUI module has no `panel` export and
  that the plugin `setup` records no `Panel` contribution while still recording
  one `window.bottom` slot and one `Style`.
- `bun test test/panel.test.ts` renders the bar for `active: 8`, `queued: 4`,
  `max: 8` and asserts the item contains `12/8`, contains no `queued` text, and
  that the element whose text is `12/8` carries a colour equal to
  `loadColor(150)` (`hsl(60 85% 70%)`); it renders `active: 6`, `queued: 2`,
  `max: 8` and asserts the item contains `8/8` and that the element whose text
  is `8/8` carries a colour equal to `loadColor(100)` (`hsl(120 60% 60%)`).
- `bun test test/panel.test.ts` asserts the rendered bar markup for a provider
  item contains neither `request-concurrency-bar-sep` nor `·`.
- `bun test test/panel.test.ts` renders the bar for a `null` snapshot and sees
  `Status unavailable`, and for an empty provider list sees no bar element.
- `bun test test/panel.test.ts` imports the prebuilt `dist/gui.cjs` and reads
  `{ setup: "function", panel: false }`, and its rebuild check matches the
  committed bundle after `bun run build:gui`.
- `bun run typecheck` passes with the removed panel types and the new
  `ProviderRow.total`.
- `make plugin-test` passes at the repository root.
- The plugin `README.md` and `wiki/concepts/request-concurrency-queue.md`
  describe the bar as the only persistent surface, the combined `X/Y` count,
  and the six-anchor scale; a case-insensitive whole-word search for `tab`
  finds no match in either file, and `wiki/index.md` no longer names a side tab
  for this plugin.
- `wiki/log.md`'s newest entry is an `update` entry naming
  `concepts/request-concurrency-queue.md` and `index.md`, and the `Last updated`
  date in `wiki/index.md`'s header matches that entry's date.
- The files this task changes stay inside
  `harness-plugins/opencode_v2/request-concurrency-queue/`,
  `wiki/concepts/request-concurrency-queue.md`, `wiki/index.md`, `wiki/log.md`,
  and this task file: with `git status --porcelain` recorded before the first
  edit, `git status --porcelain` afterwards adds no path outside those five
  locations.
