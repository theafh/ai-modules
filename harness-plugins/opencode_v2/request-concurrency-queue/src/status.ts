import type { ProviderStatus, StatusSnapshot, TransitionKind, TransitionRecord } from "./rpc.js"

/** The three color states a provider row can show. */
export type StatusColor = "green" | "amber" | "red"

/** One provider row as the panel renders it. */
export interface ProviderRow {
  readonly providerID: string
  readonly active: number
  readonly queued: number
  readonly max: number
  /** Utilization as a whole-percent string, e.g. `50%`. */
  readonly utilization: string
  /** Demand as a whole-percent string, e.g. `75%`. */
  readonly demand: string
  readonly color: StatusColor
}

/** The `location` option the status RPC accepts, selecting the routed instance. */
export interface StatusCallOptions {
  readonly location?: { readonly directory: string }
}

/**
 * The part of a routed server's RPC client that status reads. It mirrors
 * `client.rpc(statusRpc)` without pulling the GUI bundle into this module.
 */
export interface StatusClient {
  status(input: unknown, options?: StatusCallOptions): Promise<StatusSnapshot>
  readonly events: {
    on(name: "changed", handler: () => void | Promise<void>): () => void
  }
}

/** How `subscribeStatus` reads and refreshes the shared snapshot. */
export interface SubscribeStatusOptions {
  /**
   * The mounted session's workspace directory, sent as the RPC location so the
   * call reaches that location's instance. The shared store makes every
   * instance return the same snapshot.
   */
  readonly directory?: string
  /** How often to refetch even without a `changed` event. */
  readonly refetchIntervalMs?: number
}

/** Slow refetch that recovers a snapshot when a `changed` event was missed. */
export const DEFAULT_REFETCH_INTERVAL_MS = 5000

/** Turns one provider's snapshot record into its rendered row. */
export function providerRow(provider: ProviderStatus): ProviderRow {
  return {
    providerID: provider.providerID,
    active: provider.active,
    queued: provider.queued,
    max: provider.max,
    utilization: percent(provider.utilization),
    demand: percent(provider.demand),
    color: colorFor(provider),
  }
}

/** Turns every provider in a snapshot into its rendered row, in snapshot order. */
export function providerRows(snapshot: StatusSnapshot): ProviderRow[] {
  return snapshot.providers.map(providerRow)
}

/** The newest transitions the panel renders; the store keeps more history. */
export const PANEL_TRANSITION_LIMIT = 20

/** One recent transition as the panel renders it. */
export interface TransitionRow {
  /** Local clock time, `HH:MM:SS`. */
  readonly time: string
  readonly providerID: string
  readonly kind: TransitionKind
  readonly sessionID: string
  readonly active: number
  readonly queued: number
}

/**
 * Turns the snapshot's recent transitions into rendered rows, newest first.
 * The rendered window is capped so a long history scrolls instead of growing
 * the panel without bound.
 */
export function transitionRows(
  snapshot: StatusSnapshot,
  limit = PANEL_TRANSITION_LIMIT,
): TransitionRow[] {
  return snapshot.transitions
    .slice(-limit)
    .reverse()
    .map(transitionRow)
}

/** Turns one transition record into its rendered row. */
export function transitionRow(transition: TransitionRecord): TransitionRow {
  return {
    time: formatClock(transition.timestamp),
    providerID: transition.providerID,
    kind: transition.kind,
    sessionID: transition.sessionID,
    active: transition.active,
    queued: transition.queued,
  }
}

/**
 * Reads a fresh snapshot, then refetches on every `changed` event and on a
 * slow interval. The returned function is that registration's unsubscribe
 * function.
 *
 * A successful fetch delivers a `StatusSnapshot`. A rejected fetch delivers
 * `null`, so the panel reports that status is unavailable instead of leaving
 * stale or zeroed rows on screen; a later successful fetch restores the rows.
 */
export function subscribeStatus(
  getClient: () => StatusClient,
  onChange: (snapshot: StatusSnapshot | null) => void,
  options: SubscribeStatusOptions = {},
): () => void {
  const client = getClient()
  const interval = options.refetchIntervalMs ?? DEFAULT_REFETCH_INTERVAL_MS
  let cancelled = false
  let latest = 0
  const publish = async (): Promise<void> => {
    const request = ++latest
    let snapshot: StatusSnapshot
    try {
      snapshot = await client.status({}, locationOption(options.directory))
    } catch {
      // A failed fetch reports the outage; the next event or interval retries.
      if (!cancelled && request === latest) onChange(null)
      return
    }
    // A response older than the newest one started must not overwrite it.
    if (!cancelled && request === latest) onChange(snapshot)
  }
  void publish()
  const unsubscribe = client.events.on("changed", () => {
    void publish()
  })
  const timer = setInterval(() => {
    void publish()
  }, interval)
  return () => {
    cancelled = true
    clearInterval(timer)
    unsubscribe()
  }
}

function locationOption(directory: string | undefined): StatusCallOptions | undefined {
  return directory === undefined ? undefined : { location: { directory } }
}

function colorFor(provider: ProviderStatus): StatusColor {
  if (provider.queued > 0) return "red"
  if (provider.active === provider.max) return "amber"
  return "green"
}

function percent(value: number): string {
  return `${Math.round(value * 100)}%`
}

function formatClock(timestamp: number): string {
  const date = new Date(timestamp)
  const pad = (value: number): string => String(value).padStart(2, "0")
  return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`
}
