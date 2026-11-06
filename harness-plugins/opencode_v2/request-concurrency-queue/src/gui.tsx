import { For, createEffect, createSignal, onCleanup } from "solid-js"
import { Panel, Plugin, type PanelProps, type PanelTab } from "@opencode/plugin/gui"
import { statusRpc } from "./rpc.js"
import { providerRows, subscribeStatus, type ProviderRow, type StatusClient } from "./status.js"

const statusTab: PanelTab = {
  id: "status",
  title: "Concurrency",
  pinned: true,
}

/** One row per configured provider, with its absolute counts and percentages. */
function StatusView(props: PanelProps) {
  const [rows, setRows] = createSignal<ProviderRow[]>([])

  createEffect(() => {
    // The only reactive read: a session switch re-runs this effect, and the
    // cleanup below drops the previous client's subscription.
    const client = props.session.server.client
    const unsubscribe = subscribeStatus(
      () => client.rpc(statusRpc) as unknown as StatusClient,
      (snapshot) => setRows(providerRows(snapshot)),
    )
    onCleanup(unsubscribe)
  })

  return (
    <div class="request-concurrency-status">
      <For each={rows()}>
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
    </div>
  )
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
