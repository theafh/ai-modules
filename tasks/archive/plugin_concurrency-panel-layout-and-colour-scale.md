---
description: "Rework the Concurrency panel from unseparated inline text into a labelled grid with tabular figures and a green-yellow-orange-red load colour scale."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-06T16:26:03
updated: 2026-11-06T16:26:03
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
---

# Lay out the Concurrency panel as a labelled grid with a load colour scale

## Goal

The Concurrency tab reads as a compact status table: one labelled header row,
one single-line row per provider, right-aligned tabular counts and percentages,
and a load colour scale on the numbers. The scale starts green at 0%, reaches
yellow near 100%, orange near 200%, and red from 300% on. Below the provider
rows, the recent-activity feed reads as aligned columns with a kind badge and a
truncated session ID instead of a wrapped run of text.

## Context

The panel body in `src/gui.tsx` renders each provider as adjacent inline
`<span>` elements with no separator text and no registered stylesheet. The host
does not load a plugin's CSS file, so values run together (`8 active2
queuedutilization 100%demand 125%`) and the row wraps onto a second line in the
side region.

The snapshot-to-row transform lives in `src/status.ts`, the panel tests in
`test/panel.test.ts` and `test/status.test.ts`, and the desktop loads the
prebuilt `dist/gui.cjs` bundle, never the source. The panel's own styles must be
contributed through the GUI host's `Style` registry, which takes a CSS string
with `ctx.add(Style, css)`.

The panel's state model and the side-region tab are described in
[Request concurrency queue](../../../wiki/concepts/request-concurrency-queue.md).

## Approach

Add `src/panel-style.ts` exporting one `PANEL_STYLE` CSS string for the panel's
own class names, and register it in the plugin's `setup` with
`ctx.add(Style, PANEL_STYLE)` beside the existing `ctx.add(Panel, panel)`. The
stylesheet gives the header and provider rows one shared grid template so the
columns line up, right-aligns the numeric columns in tabular figures, truncates
long provider names with an ellipsis, and gives the feed its own aligned grid.

Rewrite `StatusBody` in `src/gui.tsx` as a labelled table. The header carries
`Provider`, `Active`, `Queued`, `Util`, and `Demand`; each provider row shows the
provider name, `active / max` with the maximum muted, the queue depth, and the
utilization and demand percentages. Keep the full provider ID on a `title`
attribute so a truncated name remains readable on hover. Drop the old
`is-green`/`is-amber`/`is-red` row classes.

Replace the coarse three-state `StatusColor` in `src/status.ts` with a load
scale. Export `loadColor(percent)` with anchors at 0% green
(`hsl(145 65% 50%)`), 100% yellow (`hsl(48 95% 55%)`), 200% orange
(`hsl(28 95% 58%)`), and 300% red (`hsl(0 80% 62%)`), interpolating hue,
saturation, and lightness between anchors, holding red past 300%, and reading a
negative or non-finite value as zero. `ProviderRow` carries `utilizationColor`
and `demandColor`; the active count and utilization use the `active / max` load,
while the queued count and demand use `(active + queued) / max`. The row's left
accent bar uses the demand colour.

Render each feed row as a grid of timestamp, kind, provider, session, and counts.
Style the kind as an uppercase badge with a colour per kind, truncate provider
and session with an ellipsis and a `title`, and keep the counts on one line.

Update the README `## State and observability` passage to describe the labelled
columns and the load scale in place of the old green/amber/red sentence, then
rebuild the committed `dist/gui.cjs` with `bun run build:gui`.

**Out of scope:**

- Changing queue, retry, timeout, or slot-release behaviour.
- Making the colour thresholds configurable; the four anchors are fixed.
- Historical charts, persisted metrics, or alerting.

## Acceptance

- `bun test test/status.test.ts` asserts the exact anchor colours from
  `loadColor(0)`, `loadColor(100)`, `loadColor(200)`, and `loadColor(300)`, that
  hue falls monotonically across the anchors, that a value past 300% returns the
  red anchor, and that a negative or `NaN` value returns the zero anchor.
- `bun test test/status.test.ts` asserts a provider with `active: 2`,
  `queued: 1`, `max: 4` gets `utilizationColor` equal to `loadColor(50)` and
  `demandColor` equal to `loadColor(75)`.
- `bun test test/panel.test.ts` asserts the rendered body contains the five
  header labels, the provider name, the `50%` utilization cell, and an inline
  `hsl(` colour on a numeric cell.
- `bun test test/panel.test.ts` asserts a queued feed transition renders the
  `request-concurrency-feed-kind is-queued` badge class and the single-line
  `2 active · 1 queued` counts.
- `bun test test/panel.test.ts` rebuilds the GUI bundle from source and matches
  the committed `dist/gui.cjs`, so the shipped bundle carries the new layout.
- `bun run typecheck` passes with the new style module and row fields.
- The README `## State and observability` section states the labelled header and
  the green-to-red scale, and a grep for the superseded sentence `The row is
  green while` finds no match.
