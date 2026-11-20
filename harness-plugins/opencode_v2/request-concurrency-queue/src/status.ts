import type { ProviderStatus, StatusSnapshot, TransitionKind, TransitionRecord } from "./rpc.js"

/** One provider row as the dialog renders it. */
export interface ProviderRow {
  readonly providerID: string
  readonly active: number
  readonly queued: number
  /** The effective maximum, which adaptive control may lower and raise. */
  readonly max: number
  /** The configured maximum that adaptive control never exceeds. */
  readonly ceiling: number
  /** Active plus queued, the bar's combined load count. */
  readonly total: number
  /** Utilization as a whole-percent string, e.g. `50%`. */
  readonly utilization: string
  /** Demand as a whole-percent string, e.g. `75%`. */
  readonly demand: string
  /** CSS color for the active count and utilization, by `active / max`. */
  readonly utilizationColor: string
  /**
   * CSS color for the combined count, the queued count, and demand, by
   * `(active + queued) / max`.
   */
  readonly demandColor: string
  /** Whole tokens the new-context bucket holds. */
  readonly tokensAvailable: number
  /** The bucket's capacity; 0 when the provider has no token budget. */
  readonly tokensCapacity: number
  /** Epoch milliseconds until which a `Retry-After` pauses requests; 0 when not paused. */
  readonly tokensPausedUntil: number
  /** Compact `available / capacity` label, or an empty string when there is no budget. */
  readonly tokensLabel: string
  /** CSS color for the token count, green when full and red when nearly empty. */
  readonly tokensColor: string
}

/**
 * The load scale's eight anchor points: dark green at zero, light green at
 * 100%, light yellow at 150%, orange at 200%, light red at 250%, dark red at
 * 300%, dark pink at 350%, and magenta at 400% and beyond. Between anchors the
 * color is interpolated, so a row warms up as its load climbs instead of
 * snapping between bands. Past dark red the hue keeps falling below zero —
 * dark pink at -24 is 336°, magenta at -40 is 320° — so interpolation travels
 * the short way around the wheel instead of jumping back through green.
 */
const LOAD_ANCHORS = [
  { percent: 0, hue: 145, saturation: 60, lightness: 28 },
  { percent: 100, hue: 120, saturation: 60, lightness: 60 },
  { percent: 150, hue: 60, saturation: 85, lightness: 70 },
  { percent: 200, hue: 32, saturation: 95, lightness: 55 },
  { percent: 250, hue: 12, saturation: 90, lightness: 68 },
  { percent: 300, hue: 0, saturation: 70, lightness: 35 },
  { percent: 350, hue: -24, saturation: 75, lightness: 42 },
  { percent: 400, hue: -40, saturation: 70, lightness: 30 },
] as const

/**
 * The color for a load percentage on the dark-green-to-magenta scale. A value
 * below zero or one that is not a number reads as no load; a value at or past
 * 400% holds the magenta anchor.
 */
export function loadColor(percent: number): string {
  const value = Number.isFinite(percent) ? Math.max(0, percent) : 0
  const last = LOAD_ANCHORS[LOAD_ANCHORS.length - 1]
  if (value >= last.percent) return anchorColor(last)
  for (let index = 1; index < LOAD_ANCHORS.length; index += 1) {
    const lower = LOAD_ANCHORS[index - 1]
    const upper = LOAD_ANCHORS[index]
    if (value > upper.percent) continue
    const progress = (value - lower.percent) / (upper.percent - lower.percent)
    return `hsl(${Math.round(lerp(lower.hue, upper.hue, progress))} ${Math.round(
      lerp(lower.saturation, upper.saturation, progress),
    )}% ${Math.round(lerp(lower.lightness, upper.lightness, progress))}%)`
  }
  return anchorColor(last)
}

function anchorColor(anchor: (typeof LOAD_ANCHORS)[number]): string {
  return `hsl(${anchor.hue} ${anchor.saturation}% ${anchor.lightness}%)`
}

function lerp(from: number, to: number, progress: number): number {
  return from + (to - from) * progress
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
  const tokens = provider.tokensCapacity
  return {
    providerID: provider.providerID,
    active: provider.active,
    queued: provider.queued,
    max: provider.max,
    ceiling: provider.ceiling,
    total: provider.active + provider.queued,
    utilization: percent(provider.utilization),
    demand: percent(provider.demand),
    utilizationColor: loadColor(provider.utilization * 100),
    demandColor: loadColor(provider.demand * 100),
    tokensAvailable: provider.tokensAvailable,
    tokensCapacity: provider.tokensCapacity,
    tokensPausedUntil: provider.tokensPausedUntil,
    tokensLabel:
      tokens === 0
        ? ""
        : `${formatTokens(provider.tokensAvailable)} / ${formatTokens(tokens)}`,
    tokensColor: tokens === 0 ? "" : loadColor((provider.tokensAvailable / tokens) * 100),
  }
}

/** Formats a token count compactly, e.g. `400k` or `1.2m`. */
export function formatTokens(tokens: number): string {
  const value = Number.isFinite(tokens) ? Math.max(0, tokens) : 0
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1).replace(/\.0$/, "")}m`
  if (value >= 1_000) return `${Math.round(value / 1_000)}k`
  return String(Math.round(value))
}

/** Turns every provider in a snapshot into its rendered row, in snapshot order. */
export function providerRows(snapshot: StatusSnapshot): ProviderRow[] {
  return snapshot.providers.map(providerRow)
}

/** The newest transitions the dialog renders; the store keeps more history. */
export const PANEL_TRANSITION_LIMIT = 20

/** One recent transition as the dialog renders it. */
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
 * the dialog without bound.
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
 * `null`, so the bar reports that status is unavailable instead of leaving
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

function percent(value: number): string {
  return `${Math.round(value * 100)}%`
}

function formatClock(timestamp: number): string {
  const date = new Date(timestamp)
  const pad = (value: number): string => String(value).padStart(2, "0")
  return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`
}
