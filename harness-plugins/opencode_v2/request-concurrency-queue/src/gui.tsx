import { For, Show, createEffect, createSignal, onCleanup } from "solid-js"
import { Panel, Plugin, type PanelProps, type PanelTab } from "@opencode/plugin/gui"
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
        <Show when={state().transitions.length > 0}>
          <div
            class="request-concurrency-feed"
            style={{ "font-family": "monospace", "max-height": "12em", "overflow-y": "auto" }}
          >
            <For each={state().transitions}>
              {(transition) => (
                <div class="request-concurrency-feed-row">
                  <span class="request-concurrency-feed-time">{transition.time}</span>
                  <span class="request-concurrency-feed-kind">{transition.kind}</span>
                  <span class="request-concurrency-feed-provider">{transition.providerID}</span>
                  <span class="request-concurrency-feed-session">{transition.sessionID}</span>
                  <span class="request-concurrency-feed-counts">{`${transition.active} active / ${transition.queued} queued`}</span>
                </div>
              )}
            </For>
          </div>
        </Show>
      </Show>
    </div>
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
  },
})
