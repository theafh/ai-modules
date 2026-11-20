import { For, Show, createEffect, createSignal, onCleanup, type Accessor } from "solid-js"
import { Plugin, Slot, Style, usePlugin } from "@opencode/plugin/gui"
import { CONFIG_STYLE, PANEL_STYLE } from "./panel-style.js"
import {
  statusRpc,
  type ConfigSnapshot,
  type SaveResult,
  type StatusSnapshot,
} from "./rpc.js"
import {
  providerRows,
  subscribeStatus,
  transitionRows,
  type ProviderRow,
  type StatusClient,
  type TransitionRow,
} from "./status.js"

/** The text the bar and dialog show when the status fetch fails. */
export const STATUS_UNAVAILABLE = "Status unavailable"

/** The snapshot the bar shows before the first fetch resolves. */
const EMPTY_SNAPSHOT: StatusSnapshot = { providers: [], transitions: [] }

/** What the status body shows: the outage notice, or the last delivered state. */
export interface StatusBodyState {
  readonly unavailable: boolean
  readonly rows: ProviderRow[]
  readonly transitions: TransitionRow[]
}

/**
 * Decides the status body's state. `null` means the status fetch failed, so the
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

/** Renders the status body from the last delivered snapshot. */
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
            <span>Tokens</span>
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
                class="request-concurrency-status-tokens"
                style={{ color: row.tokensColor }}
                title={
                  row.tokensCapacity > 0
                    ? `${row.tokensAvailable} of ${row.tokensCapacity} new-context tokens available`
                    : "No token budget configured"
                }
              >
                {row.tokensCapacity > 0 ? row.tokensLabel : "—"}
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

/** The settings methods the dialog calls on the routed server. */
export interface ConfigClient {
  /** The RPC client requires the method's input object, even when it is empty. */
  config(input: Record<string, never>): Promise<ConfigSnapshot>
  save(input: ConfigSnapshot): Promise<SaveResult>
}

/** One immutable edit of a nested config field. */
function editConfig(root: ConfigSnapshot, path: readonly string[], value: unknown): ConfigSnapshot {
  if (path.length === 0) return value as ConfigSnapshot
  const [head, ...rest] = path
  const clone = { ...(root as unknown as Record<string, unknown>) }
  const current = clone[head] as unknown
  clone[head] = rest.length === 0 ? value : editConfig(current as ConfigSnapshot, rest, value)
  return clone as unknown as ConfigSnapshot
}

function NumberField(props: {
  label: string
  value: number
  step?: number
  help?: string
  onChange: (value: number) => void
}) {
  return (
    <label class="request-concurrency-field">
      <span class="request-concurrency-field-text">
        <span class="request-concurrency-field-label">{props.label}</span>
        <Show when={props.help}>
          <span class="request-concurrency-field-help">{props.help}</span>
        </Show>
      </span>
      <input
        class="request-concurrency-input"
        type="number"
        step={props.step ?? 1}
        value={String(props.value)}
        on:input={(event) => {
          const next = Number((event.currentTarget as HTMLInputElement).value)
          if (Number.isFinite(next)) props.onChange(next)
        }}
      />
    </label>
  )
}

function CheckField(props: { label: string; help?: string; value: boolean; onChange: (v: boolean) => void }) {
  return (
    <label class="request-concurrency-field request-concurrency-field-inline">
      <span class="request-concurrency-field-text">
        <span class="request-concurrency-field-label">{props.label}</span>
        <Show when={props.help}>
          <span class="request-concurrency-field-help">{props.help}</span>
        </Show>
      </span>
      <input
        type="checkbox"
        checked={props.value}
        on:change={(event) => props.onChange((event.currentTarget as HTMLInputElement).checked)}
      />
    </label>
  )
}

function SelectField(props: {
  label: string
  help?: string
  value: string
  options: { value: string; label: string }[]
  onChange: (value: string) => void
}) {
  return (
    <label class="request-concurrency-field">
      <span class="request-concurrency-field-text">
        <span class="request-concurrency-field-label">{props.label}</span>
        <Show when={props.help}>
          <span class="request-concurrency-field-help">{props.help}</span>
        </Show>
      </span>
      <select
        class="request-concurrency-input"
        value={props.value}
        on:change={(event) => props.onChange((event.currentTarget as HTMLSelectElement).value)}
      >
        <For each={props.options}>
          {(option) => <option value={option.value}>{option.label}</option>}
        </For>
      </select>
    </label>
  )
}

/** The editable settings, with server-side validation and a save action. */
export function ConfigForm(props: { client: ConfigClient }) {
  const [form, setForm] = createSignal<ConfigSnapshot | null>(null)
  const [errors, setErrors] = createSignal<string[]>([])
  const [notice, setNotice] = createSignal("")
  const [saving, setSaving] = createSignal(false)
  const [loading, setLoading] = createSignal(true)

  createEffect(() => {
    let cancelled = false
    // Deferring the call keeps a synchronous throw inside the promise chain, so
    // a broken client shows an error instead of leaving the form on "Loading".
    void Promise.resolve()
      .then(() => props.client.config({}))
      .then((next) => {
        if (cancelled) return
        setForm(next)
        setLoading(false)
      })
      .catch((error: unknown) => {
        if (cancelled) return
        setErrors([
          `Could not read the plugin settings: ${error instanceof Error ? error.message : String(error)}`,
        ])
        setLoading(false)
      })
    onCleanup(() => {
      cancelled = true
    })
  })

  const set = (path: readonly string[], value: unknown) => {
    const current = form()
    if (!current) return
    setForm(editConfig(current, path, value))
    setNotice("")
  }

  const save = async () => {
    const current = form()
    if (!current) return
    setSaving(true)
    setErrors([])
    setNotice("")
    try {
      const result = await props.client.save(current)
      if (result.ok) {
        setNotice(
          result.restartRequired
            ? "Saved. Changing the provider set needs a restart."
            : "Saved and applied to the running server.",
        )
      } else {
        setErrors(result.errors)
      }
    } catch (error: unknown) {
      setErrors([`The save request failed: ${error instanceof Error ? error.message : String(error)}`])
    } finally {
      setSaving(false)
    }
  }

  return (
    <>
      <Show
        when={form()}
        fallback={
          <div class="request-concurrency-status-unavailable">
            {loading() ? "Loading settings…" : "Settings unavailable"}
          </div>
        }
      >
        {(current) => (
          <div class="request-concurrency-config">
            <p class="request-concurrency-config-intro">
              These settings decide how many requests may run at once and what happens when a
              provider is slow or stops answering. Save applies the change to the running server
              immediately. Only adding or removing a provider needs a restart.
            </p>

            <div class="request-concurrency-config-title">Providers</div>
            <p class="request-concurrency-config-help">
              How many requests may be sent to each provider at the same time. Anything beyond
              that waits in a queue rather than failing. Set this to the number of parallel
              requests your plan allows; a higher number is not served by the provider.
            </p>
            <For each={Object.keys(current().providers)}>
              {(providerID) => (
                <NumberField
                  label={`${providerID} · max concurrent`}
                  value={current().providers[providerID]}
                  onChange={(value) => set(["providers", providerID], value)}
                />
              )}
            </For>

            <div class="request-concurrency-config-title">Token budget</div>
            <p class="request-concurrency-config-help">
              Some providers cap how much brand-new text you may send in a short burst — text
              they have not already cached from earlier turns. This allowance refills over time.
              When it is used up, new requests wait for it to refill instead of being rejected.
            </p>
            <For each={Object.keys(current().tokens)}>
              {(providerID) => (
                <div class="request-concurrency-config-group">
                  <div class="request-concurrency-config-subtitle">{providerID}</div>
                  <NumberField
                    label="Capacity"
                    help="Brand-new tokens that may be sent in one burst before requests have to wait. Seibert allows 400000."
                    value={current().tokens[providerID].capacity}
                    onChange={(value) => set(["tokens", providerID, "capacity"], value)}
                  />
                  <NumberField
                    label="Refill per minute"
                    help="How many brand-new tokens become available again each minute. Seibert refills 400000 per minute."
                    value={current().tokens[providerID].refillPerMinute}
                    onChange={(value) => set(["tokens", providerID, "refillPerMinute"], value)}
                  />
                  <NumberField
                    label="Safety factor"
                    step={0.05}
                    help="How much to over-estimate a request before charging it. 1.1 adds a 10% margin, so the allowance is reached slightly early rather than exceeded."
                    value={current().tokens[providerID].safetyFactor}
                    onChange={(value) => set(["tokens", providerID, "safetyFactor"], value)}
                  />
                </div>
              )}
            </For>

            <div class="request-concurrency-config-title">Admission</div>
            <p class="request-concurrency-config-help">
              These decide how many requests run at once and in what order waiting ones are
              served. The context cap matters most for big fan-outs: it counts the full prompt of
              every running request, not just the new text, so many long conversations at once can
              overload a provider even when the request count is within its limit.
            </p>
            <NumberField
              label="Context in flight (tokens)"
              help="The sum of the full prompts of all running requests. A request waits if sending it would push that total over this number. 0 turns the cap off."
              value={current().scheduler.contextCapacity}
              onChange={(value) => set(["scheduler", "contextCapacity"], value)}
            />
            <NumberField
              label="Context ceiling (tokens)"
              help="After a provider stall the cap above is halved. This is the largest value it may grow back to. 0 keeps the cap fixed at the value above."
              value={current().scheduler.contextCeiling}
              onChange={(value) => set(["scheduler", "contextCeiling"], value)}
            />
            <NumberField
              label="Reserve share"
              step={0.05}
              help="The part of the token budget that small requests may not use, so a large request is not blocked by a stream of small ones. 0.25 keeps 25% free."
              value={current().scheduler.reserveShare}
              onChange={(value) => set(["scheduler", "reserveShare"], value)}
            />
            <NumberField
              label="Small-request share"
              step={0.05}
              help="A request whose cost is at most this fraction of the budget counts as small and must leave the reserve alone. Anything larger may use the reserve."
              value={current().scheduler.smallShare}
              onChange={(value) => set(["scheduler", "smallShare"], value)}
            />
            <NumberField
              label="Queue aging (ms)"
              help="After this many milliseconds a waiting request stops respecting the reserve, so a large request cannot be blocked forever by smaller ones."
              value={current().scheduler.agingMs}
              onChange={(value) => set(["scheduler", "agingMs"], value)}
            />
            <NumberField
              label="Queue deadline (ms)"
              help="How long a request may wait before the plugin gives up and reports a queue timeout. 0 waits as long as needed. Note that the client already abandons a request after 300000 ms, so a larger deadline never fires."
              value={current().scheduler.queueDeadlineMs}
              onChange={(value) => set(["scheduler", "queueDeadlineMs"], value)}
            />

            <div class="request-concurrency-config-title">Circuit breaker</div>
            <p class="request-concurrency-config-help">
              If a provider accepts a request but never answers, every request would sit until it
              times out and the queue would keep growing. The breaker notices repeated silent
              failures and stops sending new requests for a while, so the queue stays small and
              you see the problem quickly.
            </p>
            <NumberField
              label="Stalls before opening"
              help="How many failed attempts in a row, with no response at all, open the breaker. 2 gives the provider two chances."
              value={current().scheduler.breaker.threshold}
              onChange={(value) => set(["scheduler", "breaker", "threshold"], value)}
            />
            <NumberField
              label="Cooldown (ms)"
              help="How long the breaker stays open. After this, one test request is allowed: if it succeeds the breaker closes, if it stalls the breaker reopens."
              value={current().scheduler.breaker.cooldownMs}
              onChange={(value) => set(["scheduler", "breaker", "cooldownMs"], value)}
            />
            <SelectField
              label="When open"
              help="fail fast: new requests are rejected immediately, so you notice the outage now. wait: they stay queued and resume when the cooldown ends."
              value={current().scheduler.breaker.mode}
              options={[
                { value: "fail", label: "fail fast" },
                { value: "wait", label: "wait for cooldown" },
              ]}
              onChange={(value) => set(["scheduler", "breaker", "mode"], value)}
            />

            <div class="request-concurrency-config-title">Subagents</div>
            <p class="request-concurrency-config-help">
              Separate from model requests: this limits how many child sessions (subagents) may
              be running at the same time. A child that is waiting for a tool still counts, so
              this is the number of subagents alive at once, not the number calling the model.
            </p>
            <NumberField
              label="Live child sessions"
              help="Maximum subagents running at once. 0 turns this limit off."
              value={current().subagents.max}
              onChange={(value) => set(["subagents", "max"], value)}
            />

            <div class="request-concurrency-config-title">Behaviour</div>
            <CheckField
              label="Adaptive request width"
              help="When on, the number of concurrent requests is halved after a failure and raised by one after four successful requests in a row. When off, the provider maximum above is always used."
              value={current().adaptive}
              onChange={(value) => set(["adaptive"], value)}
            />

            <div class="request-concurrency-config-actions">
              <button type="button" class="request-concurrency-save" disabled={saving()} on:click={save}>
                {saving() ? "Saving…" : "Save"}
              </button>
              <Show when={notice()}>
                <span class="request-concurrency-config-notice">{notice()}</span>
              </Show>
            </div>
          </div>
        )}
      </Show>
      <For each={errors()}>
        {(error) => <div class="request-concurrency-config-error">{error}</div>}
      </For>
    </>
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
                    style={{ color: row.demandColor }}
                    title={`${row.total} of ${row.max} slots in demand${
                      row.tokensCapacity > 0 ? ` · ${row.tokensAvailable} new-context tokens` : ""
                    }`}
                  >
                    {`${row.total}/${row.max}`}
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
function StatusDialog(props: {
  snapshot: Accessor<StatusSnapshot | null>
  client: ConfigClient | null
}) {
  const ctx = usePlugin()
  const [tab, setTab] = createSignal<"queue" | "config">("queue")
  return (
    <ctx.ui.Dialog title="Concurrency" size="x-large">
      <div class="request-concurrency-dialog">
        <div class="request-concurrency-tabs" role="tablist">
          <button
            type="button"
            role="tab"
            aria-selected={tab() === "queue"}
            class={`request-concurrency-tab${tab() === "queue" ? " is-active" : ""}`}
            on:click={() => setTab("queue")}
          >
            Queue
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={tab() === "config"}
            class={`request-concurrency-tab${tab() === "config" ? " is-active" : ""}`}
            on:click={() => setTab("config")}
          >
            Config
          </button>
        </div>
        <Show when={tab() === "queue"}>
          <StatusBody snapshot={props.snapshot()} />
        </Show>
        <Show when={tab() === "config"}>
          <Show
            when={props.client}
            fallback={<div class="request-concurrency-status-unavailable">Settings unavailable</div>}
          >
            {(client) => <ConfigForm client={client()} />}
          </Show>
        </Show>
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
  const [configClient, setConfigClient] = createSignal<ConfigClient | null>(null)

  createEffect(() => {
    // The status is process-wide, so the built-in server serves the same
    // snapshot as any session.
    const servers = ctx.servers.list().map((id) => ctx.servers.get(id))
    const server = servers.find((candidate) => candidate?.builtin) ?? servers.find(Boolean)
    if (!server) return
    setConfigClient(server.client.rpc(statusRpc) as unknown as ConfigClient)
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
    ctx.dialogs.open(() => <StatusDialog snapshot={snapshot} client={configClient()} />)
  }

  return (
    <Show when={loaded()}>
      <StatusBarBody snapshot={snapshot()} onOpen={open} />
    </Show>
  )
}

export default Plugin.define({
  setup(ctx) {
    ctx.add(Slot, { at: "window.bottom", render: () => <StatusBar /> })
    ctx.add(Style, PANEL_STYLE + CONFIG_STYLE)
  },
})
