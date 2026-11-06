import { FifoLimiter } from "./limiter.js"
import type { ProviderStatus, StatusSnapshot, TransitionRecord } from "./rpc.js"

/** How many recent transitions the process-wide store keeps. */
export const TRANSITION_LIMIT = 50

/**
 * A bounded ring buffer of the most recent transitions. Appending past the
 * limit drops the oldest entry, so memory stays constant however long the
 * process runs.
 */
export class TransitionBuffer {
  private readonly entries: TransitionRecord[] = []

  append(entry: TransitionRecord): void {
    this.entries.push(entry)
    if (this.entries.length > TRANSITION_LIMIT) this.entries.shift()
  }

  /** The retained entries in append order, oldest first, as a copy. */
  recent(): TransitionRecord[] {
    return [...this.entries]
  }
}

/**
 * One provider's shared limit. Every plugin instance in the process, one per
 * open location, gates its requests through these same limiter objects.
 */
export interface ProviderLimit {
  readonly maxConcurrency: number
  readonly limiter: FifoLimiter
}

/**
 * The process-wide limiter registry. The first plugin instance creates it and
 * every later instance reuses it, so one provider maximum caps the whole
 * server process rather than each open location separately.
 *
 * `subscribers` holds each instance's `changed` emitter, so a transition under
 * one location reaches every location's event stream. `refcount` counts the
 * instances holding the store; the last release clears the `globalThis` slot.
 */
export interface Store {
  /** Canonical rendering of the configured provider set and maximums. */
  readonly fingerprint: string
  readonly providers: Map<string, ProviderLimit>
  readonly subscribers: Set<() => void>
  /** Recent transitions shared by every location's status handler. */
  readonly transitions: TransitionBuffer
  refcount: number
}

/**
 * Versioned key for the `globalThis` slot that holds the one store. A version
 * suffix lets a later plugin release adopt a new shape without reading state a
 * different build wrote.
 */
export const STORE_KEY = Symbol.for("opencode.request-concurrency-queue.store.v1")

/**
 * Builds an isolated store with one limiter per provider. Tests call this
 * directly, so they exercise the shared state without the harness runtime.
 */
export function createStore(limits: Map<string, number>): Store {
  const store: Store = {
    fingerprint: fingerprintOf(limits),
    providers: new Map(),
    subscribers: new Set(),
    transitions: new TransitionBuffer(),
    refcount: 0,
  }
  for (const [providerID, maxConcurrency] of limits) {
    const limiter = new FifoLimiter(maxConcurrency, (changes) => {
      for (const change of changes) {
        store.transitions.append({
          timestamp: Date.now(),
          providerID,
          kind: change.kind,
          sessionID: change.sessionID,
          active: limiter.activeCount,
          queued: limiter.queuedCount,
        })
      }
      publish(store)
    })
    store.providers.set(providerID, { maxConcurrency, limiter })
  }
  return store
}

/** Renders a provider set and its maximums in a stable, order-independent form. */
export function fingerprintOf(limits: Map<string, number>): string {
  return [...limits]
    .sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0))
    .map(([providerID, maxConcurrency]) => `${providerID}=${maxConcurrency}`)
    .join(",")
}

/** Runs every subscriber, isolating one broken emitter from the others. */
export function publish(store: Store): void {
  for (const subscriber of [...store.subscribers]) {
    try {
      subscriber()
    } catch {
      // A failing emitter must not stop the other locations from updating.
    }
  }
}

/** Adds one instance's `changed` emitter; returns its unsubscribe function. */
export function subscribeStore(store: Store, subscriber: () => void): () => void {
  store.subscribers.add(subscriber)
  return () => {
    store.subscribers.delete(subscriber)
  }
}

/**
 * Adopts the process-wide store, creating it when no instance holds one yet.
 *
 * A later instance whose provider set or maximums differ keeps the existing
 * registry unchanged and reports the mismatch through `onMismatch`: the first
 * instance's configuration wins for the process, and no location can silently
 * add a provider or raise a cap behind the others.
 */
export function adoptStore(
  limits: Map<string, number>,
  onMismatch: (existing: string, configured: string) => void = () => {},
): Store {
  const existing = globalStore()
  if (existing) {
    const configured = fingerprintOf(limits)
    if (configured !== existing.fingerprint) onMismatch(existing.fingerprint, configured)
    existing.refcount += 1
    return existing
  }

  const store = createStore(limits)
  store.refcount = 1
  registry()[STORE_KEY] = store
  return store
}

/**
 * Releases one instance's hold. Returns `true` when it was the last holder and
 * the process-wide registry was cleared.
 */
export function releaseStore(store: Store): boolean {
  store.refcount = Math.max(0, store.refcount - 1)
  if (store.refcount > 0) return false

  if (globalStore() === store) delete registry()[STORE_KEY]
  store.subscribers.clear()
  return true
}

/** The process-wide store, when an instance holds one. */
export function globalStore(): Store | undefined {
  return registry()[STORE_KEY]
}

/** Clears the process-wide slot. Test isolation and tooling use this. */
export function clearGlobalStore(): void {
  const store = globalStore()
  if (store) store.subscribers.clear()
  delete registry()[STORE_KEY]
}

/** Reads the shared state every location's status handler serves. */
export function snapshotOf(store: Store): StatusSnapshot {
  const providers = [...store.providers].map(([providerID, limit]): ProviderStatus => {
    const active = limit.limiter.activeCount
    const queued = limit.limiter.queuedCount
    const max = limit.maxConcurrency
    return {
      providerID,
      active,
      queued,
      max,
      utilization: max === 0 ? 0 : active / max,
      demand: max === 0 ? 0 : (active + queued) / max,
    }
  })
  return { providers, transitions: store.transitions.recent() }
}

function registry(): Record<symbol, Store | undefined> {
  return globalThis as unknown as Record<symbol, Store | undefined>
}
