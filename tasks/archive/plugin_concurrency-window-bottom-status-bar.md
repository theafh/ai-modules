---
description: "Add a window-bottom status bar that shows per-provider concurrency load on every screen, including Home, and opens the full panel in a dialog."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-06T20:04:34
updated: 2026-11-06T20:04:34
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
---

# Add a window-bottom concurrency status bar

## Goal

A full-width status bar in the window's bottom slot shows the current
concurrency state on every screen, including Home and drafts, without requiring
a session or the side region. It shows each configured provider's
`active / max` count and queue depth in the same green-to-red load colours as
the side panel, and clicking it opens an `x-large` **Concurrency** dialog with
the full provider table and recent-activity feed.

## Context

The Concurrency view currently exists only as a pinned tab in a session's side
region. The GUI plugin API has no registry for a Home navigation item or a
top-level route, so a Settings page or a main-sidebar entry cannot serve as a
discoverable global entry point. The `Slot` registry offers one global surface:
`window.bottom`, a full-width strip under the window content, above toasts.

The status RPC is process-wide: every location's handler reads the same queue,
and a snapshot request with no location returns the same data. A global view can
therefore read the built-in server without a routed session. The GUI context
provides `ctx.servers` to reach that server, `ctx.dialogs` to open a dialog, and
`ctx.ui.Dialog` for the app's dialog frame.

The existing pieces to reuse are `StatusBody` and `statusBodyState` in
`src/gui.tsx`, `subscribeStatus` in `src/status.ts`, the `statusRpc` definition
in `src/rpc.ts`, and the registered `PANEL_STYLE` stylesheet.

## Approach

Add `StatusBarBody` as a pure presentational component that takes a snapshot and
an `onOpen` callback. It renders a `<button>` only when the status is unavailable
or at least one provider exists, so an inactive plugin adds no strip. Each
provider renders as a compact `provider · active/max · queued` item, with the
counts carrying `utilizationColor` and `demandColor` from the existing row
transform.

Add `StatusBar` as the context-aware wrapper. It reads `ctx.servers.list()`,
prefers the built-in server, and falls back to the first listed server, then
subscribes through `subscribeStatus` to that server's
`client.rpc(statusRpc)`. A `loaded` signal keeps the bar hidden until the first
fetch settles, so it never flashes empty rows. Clicking the bar calls
`ctx.dialogs.open` with a `StatusDialog` that wraps `StatusBody` in
`ctx.ui.Dialog` at `size: "x-large"`. The dialog reads the same snapshot
accessor, so it keeps updating while open.

Register the bar with `ctx.add(Slot, { at: "window.bottom", render: () => <StatusBar /> })`
beside the existing panel and style registrations. Add the bar and dialog styles
to `PANEL_STYLE`: a 28px strip with a top border, a hover state, a right-edge
chevron, horizontal overflow for many providers, and a zero-padding override for
`StatusBody` inside the dialog.

Bind the click with Solid's native `on:click` rather than `onClick`. The
delegated event form makes Solid call `delegateEvents` at module evaluation,
which needs `window`; the package's bundle-load test imports `dist/gui.cjs` in a
bare Bun process with no DOM, so the native form keeps that check passing.

Update the README `## State and observability` passage and the wiki concept page
to describe the bar, its global placement, and the dialog. Rebuild the committed
`dist/gui.cjs`, bump the plugin to `0.5.0`, and add panel tests for the bar's
rendered content, its unavailable state, its hidden state, and the slot
registration.

**Out of scope:**

- Adding a Home navigation item or a main-sidebar entry; the GUI API exposes no
  registry for either.
- Adding a composer pill or titlebar pill as an alternative entry point.
- Changing queue, retry, timeout, or slot-release behaviour.
- Making the load thresholds configurable.

## Acceptance

- `bun test test/panel.test.ts` renders the bar for a snapshot with provider
  `acme`, `active: 1`, `queued: 0`, `max: 2`, and asserts the bar class, the
  `Concurrency` label, the provider name, `1/2`, `0 queued`, the open-action
  title, and an inline `hsl(` colour.
- `bun test test/panel.test.ts` renders the bar for a `null` snapshot and asserts
  it reports `Status unavailable`.
- `bun test test/panel.test.ts` renders the bar for an empty provider list and
  asserts no bar element is emitted.
- `bun test test/panel.test.ts` calls the plugin's `setup` with a recording
  `add` and asserts one contribution has `at: "window.bottom"`.
- `bun test test/panel.test.ts` still imports the prebuilt `dist/gui.cjs` in a
  bare Bun process and finds the setup and panel exports, proving the native
  click binding introduced no module-evaluation `window` dependency.
- `bun test test/panel.test.ts` rebuilds the bundle from source and matches the
  committed `dist/gui.cjs`, so the shipped bundle carries the bar.
- `bun run typecheck` passes with the new components, accessor prop, and slot
  registration.
- The README `## State and observability` section and the wiki concept page
  describe the window-bottom bar and its dialog; `grep -n "status bar"` finds a
  match in each file.
