import { For, Show, createEffect, createSignal, onCleanup } from "solid-js"
import { Panel, Plugin, type PanelProps, type PanelTab } from "@opencode/plugin/gui"
import { statusRpc } from "./rpc.js"
import { providerRows, subscribeStatus, type ProviderRow, type StatusClient } from "./status.js"

const statusTab: PanelTab = {
  id: "status",
  title: "Concurrency",
  pinned: true,
}

/** The text the panel shows when the status fetch fails. */
export const STATUS_UNAVAILABLE = "Status unavailable"

/** What the panel body shows: the outage notice, or the last provider rows. */
export interface StatusBodyState {
  readonly unavailable: boolean
  readonly rows: ProviderRow[]
}

/**
 * Decides the panel body's state. `null` means the status fetch failed, so the
 * body reports that instead of showing silent zeros; a later successful fetch
 * replaces it with provider rows.
 */
export function statusBodyState(rows: ProviderRow[] | null): StatusBodyState {
  return rows === null ? { unavailable: true, rows: [] } : { unavailable: false, rows }
}

/** Renders the panel body from the last delivered snapshot. */
export function StatusBody(props: { rows: ProviderRow[] | null }) {
  const state = () => statusBodyState(props.rows)
  return (
    <div class="request-concurrency-status">
      <Show
        when={!state().unavailable}
        fallback={<div class="request-concurrency-status-unavailable">{STATUS_UNAVAILABLE}</div>}
      >
        <For each={state().rows}>
          {(row) => (
            <div class={`request-concurrency-status-row is-${row.color}`}>
              <span class="request-concurrency-status-provider">{row.providerID}</span>
              <span class="request-concurrency-status-active">{`${row.active} / ${row.max} active`}</span>
              <span class="request-concurrency-status-queued">{`${row.queued} queued`}</span>
              <span class="request-concurrency-status-utilization">{`utilization ${row.utilization}`}</span>
              <span class="request-concurrency-status-demand">{`demand ${row.demand}`}</span>
            </div>
          )}
        </For>
      </Show>
    </div>
  )
}

/** One row per configured provider, with its absolute counts and percentages. */
function StatusView(props: PanelProps) {
  const [rows, setRows] = createSignal<ProviderRow[] | null>([])

  createEffect(() => {
    // The reactive reads below re-run this effect on a session switch, and the
    // cleanup drops the previous client's subscription.
    const client = props.session.server.client
    const directory = props.session.directory
    const unsubscribe = subscribeStatus(
      () => client.rpc(statusRpc) as unknown as StatusClient,
      (snapshot) => setRows(snapshot === null ? null : providerRows(snapshot)),
      { directory },
    )
    onCleanup(unsubscribe)
  })

  return <StatusBody rows={rows()} />
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
  },
})
