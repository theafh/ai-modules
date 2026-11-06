import type { ProviderStatus, StatusSnapshot } from "./rpc.js"

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

/**
 * The part of a routed server's RPC client that status reads. It mirrors
 * `client.rpc(statusRpc)` without pulling the GUI bundle into this module.
 */
export interface StatusClient {
  status(input: unknown): Promise<StatusSnapshot>
  readonly events: {
    on(name: "changed", handler: () => void | Promise<void>): () => void
  }
}

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

/**
 * Reads a fresh snapshot, then refetches on every `changed` event. The
 * returned function is that registration's unsubscribe function.
 */
export function subscribeStatus(
  getClient: () => StatusClient,
  onChange: (snapshot: StatusSnapshot) => void,
): () => void {
  const client = getClient()
  let cancelled = false
  let latest = 0
  const publish = async (): Promise<void> => {
    const request = ++latest
    let snapshot: StatusSnapshot
    try {
      snapshot = await client.status({})
    } catch {
      // A failed fetch keeps the last snapshot; the next changed event retries.
      return
    }
    // A response older than the newest one started must not overwrite it.
    if (!cancelled && request === latest) onChange(snapshot)
  }
  void publish()
  const unsubscribe = client.events.on("changed", () => {
    void publish()
  })
  return () => {
    cancelled = true
    unsubscribe()
  }
}

function colorFor(provider: ProviderStatus): StatusColor {
  if (provider.queued > 0) return "red"
  if (provider.active === provider.max) return "amber"
  return "green"
}

function percent(value: number): string {
  return `${Math.round(value * 100)}%`
}
