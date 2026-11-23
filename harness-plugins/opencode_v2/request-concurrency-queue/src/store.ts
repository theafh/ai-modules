import { TokenBudget, type TokenBudgetOptions } from "./budget.js"
import { RequestScheduler, type RequestSchedulerOptions } from "./scheduler.js"
import { SubagentGate, type SubagentGateOptions } from "./subagents.js"
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
 *
 * `maxConcurrency` is the configured ceiling, which a save writes; the
 * scheduler's `maxConcurrency` is the effective limit, which adaptive control
 * lowers after a failure and raises again after a run of successes. `successes`
 * counts that run.
 */
export interface ProviderLimit {
  /** The configured ceiling; `applyConfig` writes a saved maximum here. */
  maxConcurrency: number
  readonly scheduler: RequestScheduler
  successes: number
}

/** The admission scheduler's tuning: context cap and budget lanes. */
export interface SchedulerConfig {
  /** Total context tokens allowed in flight; 0 disables the cap. */
  contextCapacity?: number
  /** Upper bound the adaptive context cap grows back to. */
  contextCeiling?: number
  /** Fraction of the token budget kept for requests above the small threshold. */
  reserveShare?: number
  /** Fraction of budget capacity at or below which a request counts as small. */
  smallShare?: number
  /** A waiter older than this ignores the reserve. */
  agingMs?: number
  /** Longest a request may wait for admission before it is rejected. */
  queueDeadlineMs?: number
  /** Stalled-attempt circuit breaker. */
  breaker?: {
    threshold?: number
    cooldownMs?: number
    mode?: "fail" | "wait"
  }
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
  fingerprint: string
  readonly providers: Map<string, ProviderLimit>
  readonly subscribers: Set<() => void>
  /** Recent transitions shared by every location's status handler. */
  readonly transitions: TransitionBuffer
  /** The live-child-session gate, when fan-out gating is configured. */
  subagents?: SubagentGate
  /** Whether the request width reacts to provider capacity signals. */
  adaptive: boolean
  refcount: number
  /** Pending teardown after the last instance released the store. */
  disposeTimer?: ReturnType<typeof setTimeout>
}

/**
 * Versioned key for the `globalThis` slot that holds the one store. A version
 * suffix lets a later plugin release adopt a new shape without reading state a
 * different build wrote.
 */
export const STORE_KEY = Symbol.for("opencode.request-concurrency-queue.store.v12")

/**
 * Builds an isolated store with one limiter per provider. Tests call this
 * directly, so they exercise the shared state without the harness runtime.
 */
export function createStore(
  limits: Map<string, number>,
  budgets: Map<string, TokenBudgetOptions> = new Map(),
  schedulerConfig?: SchedulerConfig,
  subagents?: SubagentGateOptions,
  adaptive = false,
): Store {
  const store: Store = {
    fingerprint: fingerprintOf(limits),
    providers: new Map(),
    subscribers: new Set(),
    transitions: new TransitionBuffer(),
    subagents: subagents ? new SubagentGate(subagents) : undefined,
    adaptive,
    refcount: 0,
  }
  for (const [providerID, maxConcurrency] of limits) {
    const budgetOptions = budgets.get(providerID)
    const scheduler = new RequestScheduler(
      {
        maxSlots: maxConcurrency,
        budget: budgetOptions ? new TokenBudget(budgetOptions) : undefined,
        contextCapacity: schedulerConfig?.contextCapacity,
        contextCeiling: schedulerConfig?.contextCeiling,
        reserveShare: schedulerConfig?.reserveShare,
        smallShare: schedulerConfig?.smallShare,
        agingMs: schedulerConfig?.agingMs,
        queueDeadlineMs: schedulerConfig?.queueDeadlineMs,
        breaker: schedulerConfig?.breaker,
      },
      (changes) => {
        for (const change of changes) {
          store.transitions.append({
            timestamp: Date.now(),
            providerID,
            kind: change.kind,
            sessionID: change.sessionID,
            active: change.active,
            queued: change.queued,
          })
        }
        publish(store)
      },
    )
    store.providers.set(providerID, { maxConcurrency, scheduler, successes: 0 })
  }
  return store
}

/** One edited configuration, ready to apply to a running store. */
export interface LiveConfig {
  readonly providers: Map<string, number>
  readonly tokens: Map<string, TokenBudgetOptions>
  readonly scheduler?: SchedulerConfig
  readonly subagents?: SubagentGateOptions
  readonly adaptive: boolean
}

/**
 * Applies an edited configuration to the running store.
 *
 * Every in-place edit is applied for the providers both sides share: maximums,
 * token budgets, scheduler settings, the subagent gate, and `adaptive`. Adding
 * or removing a provider would require rebuilding the limiters those requests
 * are already using, so that one change is deferred and reported through
 * `restartRequired`; the file already holds it and the store adopts it on the
 * next launch. An existing token bucket keeps its current fill; only its limits
 * change.
 *
 * A saved maximum becomes the provider's configured ceiling, so the status
 * snapshot, `config()`, the fingerprint, and adaptive recovery all agree with
 * the value the file holds. The ceiling is written only after the scheduler
 * accepted the new settings, and the fingerprint is recomputed from the
 * providers this call actually applied, so a deferred provider never enters it.
 */
export function applyConfig(store: Store, config: LiveConfig): { restartRequired: boolean } {
  const existing = [...store.providers.keys()].sort().join(",")
  const configured = [...config.providers.keys()].sort().join(",")
  const restartRequired = existing !== configured

  // Each provider's new ceiling is collected here and written after the loop:
  // a scheduler that throws part-way through must leave every limit describing
  // the configuration it still runs, so a failed save moves no ceiling and the
  // fingerprint below stays accurate.
  const ceilings: Array<[ProviderLimit, number]> = []
  for (const [providerID, maxConcurrency] of config.providers) {
    const limit = store.providers.get(providerID)
    if (!limit) continue
    const budgetOptions = config.tokens.get(providerID)
    const current = limit.scheduler.budgetSnapshot
    // Both are read before the reconfigure below writes the new width: the
    // clamp compares the pre-save effective width against the ceiling it ran
    // under, not the one this save installs.
    const previousCeiling = limit.maxConcurrency
    const effectiveBefore = limit.scheduler.maxConcurrency

    // A store created by an older build may hold a scheduler without the newer
    // in-place method, so fall back to replacing the bucket.
    // Changing a budget keeps what is left in it: an edit must not hand back
    // tokens the provider has already been asked for. Adding one starts full,
    // because there is no earlier fill to keep.
    if (budgetOptions && current && typeof limit.scheduler.reconfigureBudget === "function") {
      limit.scheduler.reconfigureBudget(budgetOptions)
    } else if (budgetOptions) {
      limit.scheduler.reconfigure({ budget: new TokenBudget(budgetOptions) })
    } else if (current) {
      limit.scheduler.clearBudget()
    }

    limit.scheduler.reconfigure({
      maxSlots: savedMax(config.adaptive, effectiveBefore, previousCeiling, maxConcurrency),
      contextCapacity: config.scheduler?.contextCapacity,
      contextCeiling: config.scheduler?.contextCeiling,
      reserveShare: config.scheduler?.reserveShare,
      smallShare: config.scheduler?.smallShare,
      agingMs: config.scheduler?.agingMs,
      queueDeadlineMs: config.scheduler?.queueDeadlineMs,
      breaker: config.scheduler?.breaker,
    })
    // The ceiling is recorded here and written once every reconfigure returned:
    // a throwing scheduler must leave the limit describing the configuration it
    // still runs.
    ceilings.push([limit, maxConcurrency])
  }

  for (const [limit, ceiling] of ceilings) limit.maxConcurrency = ceiling

  if (config.subagents) {
    if (store.subagents) {
      store.subagents.setMax(config.subagents.max)
      store.subagents.setHostAware(config.subagents.hostAware ?? false)
    } else {
      store.subagents = new SubagentGate(config.subagents)
    }
  } else if (store.subagents) {
    // A cleared setting turns fan-out gating off for the next launch.
    store.subagents = undefined
  }

  // Recompute from the store's own provider map, so the fingerprint records the
  // values this process applied and not a provider the file added and the store
  // deferred to a restart.
  store.fingerprint = fingerprintOf(
    new Map([...store.providers].map(([providerID, limit]) => [providerID, limit.maxConcurrency])),
  )
  store.adaptive = config.adaptive
  publish(store)
  return { restartRequired }
}

/**
 * The effective width one provider runs after a save.
 *
 * Adaptive control may have lowered the width below the ceiling it ran under.
 * That lowering survives a save, so a raise cannot push a provider straight back
 * to a width it had already backed away from; the width still never exceeds the
 * new ceiling, so a lowering cannot leave it above the ceiling either. A save
 * that turns adaptive off restores the configured ceiling, and an ordinary
 * raise — the width sitting at its ceiling — applies at once.
 */
function savedMax(
  adaptive: boolean,
  effectiveBefore: number,
  previousCeiling: number,
  ceiling: number,
): number {
  if (!adaptive || effectiveBefore >= previousCeiling) return ceiling
  return Math.min(ceiling, effectiveBefore)
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
  budgets: Map<string, TokenBudgetOptions> = new Map(),
  schedulerConfig?: SchedulerConfig,
  subagents?: SubagentGateOptions,
  adaptive = false,
  onMismatch: (existing: string, configured: string) => void = () => {},
): Store {
  const existing = globalStore()
  if (existing) {
    // A pending dispose timer means the last instance had already released the
    // store and this instance is the reload arriving inside the grace period.
    // Only then may the process-wide settings the first instance owns follow the
    // new configuration; a second live location keeps the first one's values.
    const genuineReload = existing.disposeTimer !== undefined
    // A reload lands here within the grace period: keep the store, its queued
    // requests, and its live child sessions instead of cancelling them.
    if (existing.disposeTimer) {
      clearTimeout(existing.disposeTimer)
      existing.disposeTimer = undefined
    }
    // A disposing instance stopped admission so freeing its slots would not
    // dispatch work it could not gate; this instance now takes over. A store
    // from an older build may lack the method, which must never stop the plugin
    // from loading.
    try {
      for (const limit of existing.providers.values()) {
        if (typeof limit.scheduler.endDrain === "function") limit.scheduler.endDrain()
      }
      if (existing.subagents && typeof existing.subagents.endDrain === "function") {
        existing.subagents.endDrain()
      }
    } catch {
      // An incompatible store is replaced rather than allowed to break loading.
      delete registry()[STORE_KEY]
    }
    const configured = fingerprintOf(limits)
    if (configured !== existing.fingerprint) onMismatch(existing.fingerprint, configured)
    // The fan-out ceiling follows the current configuration on every reload,
    // so changing it does not need a process restart. The provider ceilings
    // still keep the first instance's value.
    if (subagents) {
      // A store from an older build may hold a gate without the newer method,
      // so replace an incompatible instance instead of calling into it.
      if (existing.subagents && typeof existing.subagents.setMax === "function") {
        existing.subagents.setMax(subagents.max)
        // `hostAware` changes the effective ceiling the first instance owns, so
        // only a genuine reload adopts it; a second live location leaves it.
        if (genuineReload && typeof existing.subagents.setHostAware === "function") {
          existing.subagents.setHostAware(subagents.hostAware ?? false)
        }
      } else {
        existing.subagents = new SubagentGate(subagents)
      }
    } else if (genuineReload) {
      // A genuine reload whose configuration dropped the section turns gating off.
      existing.subagents = undefined
    }
    if (genuineReload) existing.adaptive = adaptive
    existing.refcount += 1
    return existing
  }

  const store = createStore(limits, budgets, schedulerConfig, subagents, adaptive)
  store.refcount = 1
  registry()[STORE_KEY] = store
  return store
}

/**
 * Releases one instance's hold. Returns `true` when it was the last holder and
 * the process-wide registry was cleared.
 */
/**
 * Releases one instance's hold on the store.
 *
 * The last release does not tear the store down immediately: a plugin reload
 * disposes the old instance and creates a new one a moment later, and tearing
 * down at once would cancel every queued request and subagent launch in the
 * middle of a run. Instead the store is kept for `graceMs` so the next
 * instance can adopt it; only after that does it clear the registry and cancel
 * whatever is still waiting.
 */
export function releaseStore(store: Store, graceMs = 5_000): boolean {
  store.refcount = Math.max(0, store.refcount - 1)
  if (store.refcount > 0) return false

  store.subscribers.clear()
  if (store.disposeTimer) clearTimeout(store.disposeTimer)

  const teardown = () => {
    if (globalStore() === store) delete registry()[STORE_KEY]
    for (const limit of store.providers.values()) {
      limit.scheduler.cancelAll("the queue plugin was unloaded")
    }
    store.subagents?.cancelAll("the fan-out gate was unloaded")
  }

  // No grace requested: tear down now, which is what tests and tooling want.
  if (graceMs <= 0) {
    store.disposeTimer = undefined
    teardown()
    return true
  }

  store.disposeTimer = setTimeout(() => {
    store.disposeTimer = undefined
    if (store.refcount > 0) return
    teardown()
  }, graceMs)
  return true
}

/** The process-wide store, when an instance holds one. */
export function globalStore(): Store | undefined {
  return registry()[STORE_KEY]
}

/** Clears the process-wide slot. Test isolation and tooling use this. */
export function clearGlobalStore(): void {
  const store = globalStore()
  if (store?.disposeTimer) clearTimeout(store.disposeTimer)
  if (store) store.subscribers.clear()
  delete registry()[STORE_KEY]
}

/** Reads the shared state every location's status handler serves. */
export function snapshotOf(store: Store): StatusSnapshot {
  const calling = new Set<string>()
  const providers = [...store.providers].map(([providerID, limit]): ProviderStatus => {
    const active = limit.scheduler.activeCount
    const queued = limit.scheduler.queuedCount
    const max = limit.scheduler.maxConcurrency
    const tokens = limit.scheduler.budgetSnapshot
    const context = limit.scheduler.status()
    const activeSessions = limit.scheduler.activeSessionIDs()
    for (const sessionID of activeSessions) calling.add(sessionID)
    return {
      providerID,
      active,
      queued,
      max,
      ceiling: limit.maxConcurrency,
      sessions: activeSessions.size,
      activeSessionIDs: [...activeSessions],
      utilization: max === 0 ? 0 : Math.min(1, active / max),
      demand: max === 0 ? 0 : (active + queued) / max,
      tokensAvailable: tokens?.available ?? 0,
      tokensCapacity: tokens?.capacity ?? 0,
      tokensPausedUntil: tokens?.pausedUntil ?? 0,
      blocked: limit.scheduler.blocked(),
      breaker: context.breaker,
      breakerRetryAfterMs: context.breakerRetryAfterMs,
      stalls: context.stalls,
      ...(context.contextCapacity > 0
        ? { contextInFlight: context.contextInFlight, contextCapacity: context.contextCapacity }
        : {}),
    }
  })

  // A live child that is running a tool holds a permit but no model slot, so
  // the panel reports how many of the live children are calling the model. That
  // is the number that should agree with the provider's active count.
  const subagents = store.subagents
  const live = subagents?.liveSessionIDs()
  const subagentStatus = subagents?.status()
  const subagentSnapshot =
    subagentStatus === undefined
      ? undefined
      : {
          ...subagentStatus,
          calling: live === undefined ? 0 : [...live].filter((sessionID) => calling.has(sessionID)).length,
        }

  return {
    providers,
    transitions: store.transitions.recent(),
    ...(subagentSnapshot ? { subagents: subagentSnapshot } : {}),
  }
}

function registry(): Record<symbol, Store | undefined> {
  return globalThis as unknown as Record<symbol, Store | undefined>
}
