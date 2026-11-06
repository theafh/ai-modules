import { For, Show, createEffect, createSignal, onCleanup, type Accessor } from "solid-js"
import {
  Panel,
  Plugin,
  Slot,
  Style,
  usePlugin,
  type PanelProps,
  type PanelTab,
} from "@opencode/plugin/gui"
import { PANEL_STYLE } from "./panel-style.js"
import { statusRpc, type StatusSnapshot } from "./rpc.js"
import {
  providerRows,
  subscribeStatus,
  transitionRows,
  type ProviderRow,
  type StatusClient,
  type TransitionRow,
} from "./status.js"

const statusTab: PanelTab = {
  id: "status",
  title: "Concurrency",
  pinned: true,
}

/** The text the panel shows when the status fetch fails. */
export const STATUS_UNAVAILABLE = "Status unavailable"

/** The snapshot the panel shows before the first fetch resolves. */
const EMPTY_SNAPSHOT: StatusSnapshot = { providers: [], transitions: [] }

/** What the panel body shows: the outage notice, or the last delivered state. */
export interface StatusBodyState {
  readonly unavailable: boolean
  readonly rows: ProviderRow[]
  readonly transitions: TransitionRow[]
}

/**
 * Decides the panel body's state. `null` means the status fetch failed, so the
 * body reports that instead of showing silent zeros; a later successful fetch
 * replaces it with provider rows and the recent transition feed.
 */
export function statusBodyState(snapshot: StatusSnapshot | null): StatusBodyState {
  if (snapshot === null) return { unavailable: true, rows: [], transitions: [] }
  return {
    unavailable: false,
    rows: providerRows(snapshot),
    transitions: transitionRows(snapshot),
  }
}

/** Renders the panel body from the last delivered snapshot. */
export function StatusBody(props: { snapshot: StatusSnapshot | null }) {
  const state = () => statusBodyState(props.snapshot)
  return (
    <div class="request-concurrency-status">
      <Show
        when={!state().unavailable}
        fallback={<div class="request-concurrency-status-unavailable">{STATUS_UNAVAILABLE}</div>}
      >
        <Show when={state().rows.length > 0}>
          <div class="request-concurrency-status-header" aria-hidden="true">
            <span>Provider</span>
            <span>Active</span>
            <span>Queued</span>
            <span>Util</span>
            <span>Demand</span>
          </div>
        </Show>
        <For each={state().rows}>
          {(row) => (
            <div
              class="request-concurrency-status-row"
              style={{ "border-left-color": row.demandColor }}
            >
              <span class="request-concurrency-status-provider" title={row.providerID}>
                {row.providerID}
              </span>
              <span
                class="request-concurrency-status-active"
                title={`${row.active} of ${row.max} slots in use`}
              >
                <span style={{ color: row.utilizationColor }}>{row.active}</span>
                <span class="request-concurrency-status-max">{` / ${row.max}`}</span>
              </span>
              <span
                class="request-concurrency-status-queued"
                style={{ color: row.demandColor }}
                title={`${row.queued} waiting`}
              >
                {row.queued}
              </span>
              <span
                class="request-concurrency-status-utilization"
                style={{ color: row.utilizationColor }}
                title="Utilization: active / max"
              >
                {row.utilization}
              </span>
              <span
                class="request-concurrency-status-demand"
                style={{ color: row.demandColor }}
                title="Demand: (active + queued) / max"
              >
                {row.demand}
              </span>
            </div>
          )}
        </For>
        <Show when={state().transitions.length > 0}>
          <div class="request-concurrency-feed">
            <div class="request-concurrency-feed-title">Recent activity</div>
            <For each={state().transitions}>
              {(transition) => (
                <div class="request-concurrency-feed-row">
                  <span class="request-concurrency-feed-time">{transition.time}</span>
                  <span class={`request-concurrency-feed-kind is-${transition.kind}`}>
                    {transition.kind}
                  </span>
                  <span class="request-concurrency-feed-provider" title={transition.providerID}>
                    {transition.providerID}
                  </span>
                  <span class="request-concurrency-feed-session" title={transition.sessionID}>
                    {transition.sessionID}
                  </span>
                  <span class="request-concurrency-feed-counts">
                    {`${transition.active} active · ${transition.queued} queued`}
                  </span>
                </div>
              )}
            </For>
          </div>
        </Show>
      </Show>
    </div>
  )
}

/** The compact bar the window-bottom slot shows, and the whole control that opens details. */
export function StatusBarBody(props: { snapshot: StatusSnapshot | null; onOpen: () => void }) {
  const state = () => statusBodyState(props.snapshot)
  return (
    <Show when={state().unavailable || state().rows.length > 0}>
      <button
        type="button"
        class="request-concurrency-bar"
        title="Open concurrency details"
        aria-label="Open concurrency details"
        on:click={() => props.onOpen()}
      >
        <span class="request-concurrency-bar-label">Concurrency</span>
        <Show
          when={!state().unavailable}
          fallback={<span class="request-concurrency-bar-muted">{STATUS_UNAVAILABLE}</span>}
        >
          <span class="request-concurrency-bar-items">
            <For each={state().rows}>
              {(row) => (
                <span class="request-concurrency-bar-item">
                  <span class="request-concurrency-bar-provider">{row.providerID}</span>
                  <span
                    style={{ color: row.utilizationColor }}
                    title={`${row.active} of ${row.max} slots in use`}
                  >
                    {`${row.active}/${row.max}`}
                  </span>
                  <span class="request-concurrency-bar-sep" aria-hidden="true">
                    ·
                  </span>
                  <span
                    style={{ color: row.demandColor }}
                    title={`${row.queued} waiting`}
                  >
                    {`${row.queued} queued`}
                  </span>
                </span>
              )}
            </For>
          </span>
        </Show>
      </button>
    </Show>
  )
}

/** The larger view the status bar opens, with the full table and the activity feed. */
function StatusDialog(props: { snapshot: Accessor<StatusSnapshot | null> }) {
  const ctx = usePlugin()
  return (
    <ctx.ui.Dialog title="Concurrency" size="x-large">
      <div class="request-concurrency-dialog">
        <StatusBody snapshot={props.snapshot()} />
      </div>
    </ctx.ui.Dialog>
  )
}

/**
 * The window-bottom status bar. It reads the process-wide snapshot from the
 * built-in server, so it shows the same state on Home as in a session, and
 * stays hidden until the first fetch settles so it never flashes empty rows.
 */
export function StatusBar() {
  const ctx = usePlugin()
  const [snapshot, setSnapshot] = createSignal<StatusSnapshot | null>(EMPTY_SNAPSHOT)
  const [loaded, setLoaded] = createSignal(false)

  createEffect(() => {
    // The status is process-wide, so the built-in server serves the same
    // snapshot as any session.
    const servers = ctx.servers.list().map((id) => ctx.servers.get(id))
    const server = servers.find((candidate) => candidate?.builtin) ?? servers.find(Boolean)
    if (!server) return
    const unsubscribe = subscribeStatus(
      () => server.client.rpc(statusRpc) as unknown as StatusClient,
      (next) => {
        setSnapshot(next)
        setLoaded(true)
      },
    )
    onCleanup(unsubscribe)
  })

  const open = () => {
    ctx.dialogs.open(() => <StatusDialog snapshot={snapshot} />)
  }

  return (
    <Show when={loaded()}>
      <StatusBarBody snapshot={snapshot()} onOpen={open} />
    </Show>
  )
}

/** One row per configured provider plus the recent transition feed. */
function StatusView(props: PanelProps) {
  const [snapshot, setSnapshot] = createSignal<StatusSnapshot | null>(EMPTY_SNAPSHOT)

  createEffect(() => {
    // The reactive reads below re-run this effect on a session switch, and the
    // cleanup drops the previous client's subscription.
    const client = props.session.server.client
    const directory = props.session.directory
    const unsubscribe = subscribeStatus(
      () => client.rpc(statusRpc) as unknown as StatusClient,
      (next) => setSnapshot(next),
      { directory },
    )
    onCleanup(unsubscribe)
  })

  return <StatusBody snapshot={snapshot()} />
}

/** The pinned status tab in the desktop side region. */
export const panel: Panel = {
  id: "status",
  region: "side",
  list: () => [statusTab],
  render: (props) => <StatusView tab={props.tab} session={props.session} screen={props.screen} />,
}

export default Plugin.define({
  setup(ctx) {
    ctx.add(Panel, panel)
    ctx.add(Slot, { at: "window.bottom", render: () => <StatusBar /> })
    ctx.add(Style, PANEL_STYLE)
  },
})
