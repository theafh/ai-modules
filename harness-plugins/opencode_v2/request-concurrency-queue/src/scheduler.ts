import { TokenBudget } from "./budget.js"
import type { TransitionKind } from "./rpc.js"

/** What one request costs on each admission dimension. */
export interface RequestCost {
  /** New, uncached tokens, charged to the provider's burst budget. */
  readonly newTokens: number
  /** Total context tokens the request occupies while it is in flight. */
  readonly contextTokens: number
}

export interface SchedulerSlot {
  release(): void
}

export interface SchedulerTransition {
  readonly kind: TransitionKind
  readonly sessionID: string
}

export type SchedulerListener = (transitions: readonly SchedulerTransition[]) => void

/** How a request behaves while the provider's circuit is open. */
export type BreakerMode = "fail" | "wait"

export interface BreakerOptions {
  /** Consecutive stalled attempts that open the circuit. */
  threshold?: number
  /** How long the circuit stays open before one probe is allowed. */
  cooldownMs?: number
  /** `fail` rejects immediately; `wait` holds the request until the cooldown ends. */
  mode?: BreakerMode
}

export interface RequestSchedulerOptions {
  /** Concurrency ceiling. */
  maxSlots: number
  /** New-context bucket, when the provider meters one. */
  budget?: TokenBudget
  /** Total context tokens allowed in flight; 0 or omitted disables the cap. */
  contextCapacity?: number
  /** Upper bound the adaptive context cap may grow back to. */
  contextCeiling?: number
  /** Fraction of the budget kept available for requests above the small threshold. */
  reserveShare?: number
  /** Fraction of budget capacity at or below which a request counts as small. */
  smallShare?: number
  /** A waiter older than this ignores the reserve check. */
  agingMs?: number
  /**
   * Longest a request may wait for admission before it is rejected. Kept below
   * the client's own header timeout, so a request is never killed silently
   * while it is still queued. 0 disables the deadline.
   */
  queueDeadlineMs?: number
  /** Stalled-attempt circuit breaker, per provider. */
  breaker?: BreakerOptions
  now?: () => number
}

export interface SchedulerStatus {
  readonly contextInFlight: number
  readonly contextCapacity: number
  /** `closed`, `open`, or `half-open` while a single probe is allowed. */
  readonly breaker: "closed" | "open" | "half-open"
  /** Milliseconds until the circuit allows a probe; 0 when closed. */
  readonly breakerRetryAfterMs: number
  /** Consecutive stalled attempts counted toward the threshold. */
  readonly stalls: number
}

interface Waiter {
  readonly sessionID: string
  readonly cost: RequestCost
  readonly enqueuedAt: number
  /** True when this admission is the single half-open test request. */
  isProbe?: boolean
  /** Identifies which probe this is, so a stale release cannot clear a newer one. */
  probeSeq?: number
  resolve(slot: SchedulerSlot): void
  reject(error: Error): void
  signal?: AbortSignal
  onAbort?: () => void
  deadlineTimer?: ReturnType<typeof setTimeout>
}

/**
 * Admits requests on four dimensions at once: concurrency slots, the
 * provider's new-token budget, the total context in flight, and the provider's
 * own health.
 *
 * The context dimension is what a large fan-out exhausts: a provider can accept
 * eight connections and still have no room for eight 150k-token contexts. A
 * request that cannot be admitted waits here, before it takes a slot, so a
 * large burst cannot park on the slots and starve small requests behind it.
 *
 * The queue deadline exists because the client's header timeout keeps running
 * while a request waits: without a shorter deadline, a request dies inside the
 * queue and looks like a provider fault. The circuit breaker exists because a
 * provider that serves nothing turns every new request into queue depth; after
 * a run of stalls it stops admitting, so the queue cannot grow without bound.
 */
export class RequestScheduler {
  private maxSlots: number
  private budget?: TokenBudget
  private contextCeiling: number
  private contextCapacity: number
  private reserveShare: number
  private smallShare: number
  private agingMs: number
  private queueDeadlineMs: number
  private breakerThreshold: number
  private breakerCooldownMs: number
  private breakerMode: BreakerMode
  private readonly now: () => number
  private readonly waiters: Waiter[] = []
  private active = 0
  private contextInFlight = 0
  private timer?: ReturnType<typeof setTimeout>
  private scheduling = false
  private stalls = 0
  private openUntil = 0
  private probeInFlight = false
  private probeSeq = 0
  private probeStartedAt = 0
  private draining = false

  constructor(
    options: RequestSchedulerOptions,
    private readonly onChange: SchedulerListener = () => {},
  ) {
    assertSlots(options.maxSlots)
    this.maxSlots = options.maxSlots
    this.budget = options.budget
    this.contextCapacity = options.contextCapacity ?? 0
    this.contextCeiling = options.contextCeiling ?? this.contextCapacity
    this.reserveShare = options.reserveShare ?? 0.25
    this.smallShare = options.smallShare ?? 0.1
    this.agingMs = options.agingMs ?? 30_000
    this.queueDeadlineMs = Math.max(0, options.queueDeadlineMs ?? 0)
    this.breakerThreshold = Math.max(1, options.breaker?.threshold ?? 3)
    this.breakerCooldownMs = Math.max(0, options.breaker?.cooldownMs ?? 60_000)
    this.breakerMode = options.breaker?.mode ?? "fail"
    this.now = options.now ?? Date.now
  }

  get activeCount(): number {
    return this.active
  }

  get queuedCount(): number {
    return this.waiters.length
  }

  get maxConcurrency(): number {
    return this.maxSlots
  }

  setMax(max: number): void {
    assertSlots(max)
    if (max === this.maxSlots) return
    this.maxSlots = max
    this.schedule()
  }

  /** The bucket's state, or undefined when the provider has no budget. */
  get budgetSnapshot() {
    return this.budget?.snapshot()
  }

  /** Reconfigures the existing bucket in place, keeping its current fill. */
  reconfigureBudget(options: { capacity: number; refillPerMinute: number; safetyFactor?: number }): void {
    this.budget?.reconfigure(options)
  }

  /**
   * Stops admitting while a disposing instance releases its slots. Without
   * this, freeing a slot would hand it to a waiter the unloaded plugin can no
   * longer gate. A reload clears the flag when it adopts the store.
   */
  beginDrain(): void {
    this.draining = true
  }

  /** Resumes admission after a reload adopted this scheduler. */
  endDrain(): void {
    if (!this.draining) return
    this.draining = false
    this.schedule()
  }

  /** Removes the token budget, so admission stops metering new tokens. */
  clearBudget(): void {
    this.budget = undefined
  }

  /** Whether admission needs the request's size at all. */
  costEstimateRequired(): boolean {
    return this.budget !== undefined || this.contextCapacity > 0
  }

  /** The estimate margin the configured budget carries. */
  get budgetSafetyFactor(): number {
    return this.budget?.safetyFactor ?? 1
  }

  /**
   * Applies edited settings without rebuilding the scheduler, so in-flight
   * requests and queued waiters survive a save. Values left undefined keep
   * their current setting.
   */
  reconfigure(options: {
    maxSlots?: number
    budget?: TokenBudget
    contextCapacity?: number
    contextCeiling?: number
    reserveShare?: number
    smallShare?: number
    agingMs?: number
    queueDeadlineMs?: number
    breaker?: BreakerOptions
  }): void {
    if (options.maxSlots !== undefined) {
      assertSlots(options.maxSlots)
      this.maxSlots = options.maxSlots
    }
    if (options.budget !== undefined) this.budget = options.budget
    if (options.contextCapacity !== undefined) this.contextCapacity = Math.max(0, options.contextCapacity)
    if (options.contextCeiling !== undefined) {
      this.contextCeiling = Math.max(0, options.contextCeiling)
      if (this.contextCeiling > 0) this.contextCapacity = Math.min(this.contextCapacity, this.contextCeiling)
    }
    if (options.reserveShare !== undefined) this.reserveShare = options.reserveShare
    if (options.smallShare !== undefined) this.smallShare = options.smallShare
    if (options.agingMs !== undefined) this.agingMs = Math.max(0, options.agingMs)
    if (options.queueDeadlineMs !== undefined) this.queueDeadlineMs = Math.max(0, options.queueDeadlineMs)
    if (options.breaker) {
      if (options.breaker.threshold !== undefined) this.breakerThreshold = Math.max(1, options.breaker.threshold)
      if (options.breaker.cooldownMs !== undefined) this.breakerCooldownMs = Math.max(0, options.breaker.cooldownMs)
      if (options.breaker.mode !== undefined) this.breakerMode = options.breaker.mode
    }
    this.schedule()
  }

  /** Pauses every admission for `seconds`, as a provider `Retry-After` asks. */
  pauseBudget(seconds: number): void {
    this.budget?.pause(seconds)
  }

  status(): SchedulerStatus {
    const now = this.now()
    return {
      contextInFlight: this.contextInFlight,
      contextCapacity: this.contextCapacity,
      breaker: this.breakerState(now),
      breakerRetryAfterMs: this.openUntil > now ? this.openUntil - now : 0,
      stalls: this.stalls,
    }
  }

  acquire(
    sessionID: string,
    cost: RequestCost = { newTokens: 0, contextTokens: 0 },
    signal?: AbortSignal,
  ): Promise<SchedulerSlot> {
    if (signal?.aborted) return Promise.reject(cancelledError())

    const now = this.now()
    const state = this.breakerState(now)
    // While half-open, the single probe owns the circuit: another request is
    // rejected rather than queued, because nothing would wake it when the probe
    // settles.
    if (this.breakerMode === "fail") {
      if (state === "open") return Promise.reject(circuitOpenError(this.openUntil - now))
      if (state === "half-open" && this.probeBlocks(now)) return Promise.reject(probeInFlightError())
    }

    return new Promise<SchedulerSlot>((resolve, reject) => {
      const waiter: Waiter = {
        sessionID,
        cost: {
          newTokens: Math.max(0, Math.floor(cost.newTokens)),
          contextTokens: Math.max(0, Math.floor(cost.contextTokens)),
        },
        enqueuedAt: now,
        resolve,
        reject,
        signal,
      }

      // A request that fits and finds no one waiting is admitted at once, so a
      // free slot is not reported as a queue transition.
      if (this.waiters.length === 0 && this.canAdmit(waiter, now)) {
        this.onChange([this.applyAdmission(waiter, now)])
        return
      }

      if (signal) {
        waiter.onAbort = () => {
          const index = this.waiters.indexOf(waiter)
          if (index !== -1) {
            this.waiters.splice(index, 1)
            this.onChange([{ kind: "dequeued", sessionID }])
          }
          this.clearDeadline(waiter)
          reject(cancelledError())
        }
        signal.addEventListener("abort", waiter.onAbort, { once: true })
      }

      if (this.queueDeadlineMs > 0) {
        waiter.deadlineTimer = setTimeout(() => {
          const index = this.waiters.indexOf(waiter)
          if (index === -1) return
          this.waiters.splice(index, 1)
          if (waiter.signal && waiter.onAbort) {
            waiter.signal.removeEventListener("abort", waiter.onAbort)
          }
          this.onChange([{ kind: "dequeued", sessionID }])
          reject(queueTimeoutError(this.queueDeadlineMs))
        }, this.queueDeadlineMs)
      }

      this.waiters.push(waiter)
      this.onChange([{ kind: "queued", sessionID }])
      this.schedule()
    })
  }

  /**
   * Records one attempt that produced no response: a transport stall, a header
   * timeout, or a 5xx. Consecutive stalls open the circuit; the context cap
   * also shrinks, because the same stall means the provider ran out of room.
   */
  recordStall(): void {
    const now = this.now()
    this.stalls += 1
    const halfOpen = this.openUntil > 0 && now >= this.openUntil
    if (halfOpen || this.stalls >= this.breakerThreshold) this.open(now)
    this.shrinkContext()
  }

  /** Records one served request: the circuit closes and the context cap grows. */
  recordSuccess(): void {
    this.stalls = 0
    this.openUntil = 0
    this.probeInFlight = false
    this.probeStartedAt = 0
    if (this.contextCapacity === 0) return
    const step = Math.max(1, Math.floor(this.contextCeiling * 0.1))
    const next = Math.min(this.contextCeiling, this.contextCapacity + step)
    if (next > this.contextCapacity) this.contextCapacity = next
    // Closing the circuit frees anything that waited in `wait` mode.
    this.schedule()
  }

  /** Kept for callers that only want the context cap to react. */
  recordTimeout(): void {
    this.shrinkContext()
  }

  cancelSession(sessionID: string): number {
    const removed: Waiter[] = []
    for (let index = this.waiters.length - 1; index >= 0; index -= 1) {
      if (this.waiters[index].sessionID !== sessionID) continue
      removed.push(...this.waiters.splice(index, 1))
    }
    if (removed.length === 0) return 0
    for (const waiter of removed) {
      if (waiter.signal && waiter.onAbort) waiter.signal.removeEventListener("abort", waiter.onAbort)
      this.clearDeadline(waiter)
      waiter.reject(cancelledError("the session ended while the request was waiting"))
    }
    this.onChange(removed.map(() => ({ kind: "dequeued" as const, sessionID })))
    return removed.length
  }

  cancelAll(reason = "the queue plugin was unloaded"): void {
    const removed = this.waiters.splice(0)
    for (const waiter of removed) {
      if (waiter.signal && waiter.onAbort) waiter.signal.removeEventListener("abort", waiter.onAbort)
      this.clearDeadline(waiter)
      waiter.reject(cancelledError(reason))
    }
    if (removed.length > 0) {
      this.onChange(removed.map((waiter) => ({ kind: "dequeued" as const, sessionID: waiter.sessionID })))
    }
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = undefined
    }
  }

  /** Applies one admission and returns its transition; the caller emits it. */
  private applyAdmission(waiter: Waiter, now = this.now()): SchedulerTransition {
    if (waiter.signal && waiter.onAbort) waiter.signal.removeEventListener("abort", waiter.onAbort)
    this.clearDeadline(waiter)
    if (this.openUntil > 0 && now >= this.openUntil) {
      this.probeSeq += 1
      this.probeInFlight = true
      this.probeStartedAt = now
      waiter.isProbe = true
      waiter.probeSeq = this.probeSeq
    }
    this.active += 1
    this.contextInFlight += waiter.cost.contextTokens
    this.budget?.spend(waiter.cost.newTokens)
    waiter.resolve(this.createSlot(waiter))
    return { kind: "acquired", sessionID: waiter.sessionID }
  }

  private createSlot(waiter: Waiter): SchedulerSlot {
    let released = false
    return {
      release: () => {
        if (released) return
        released = true
        this.active -= 1
        this.contextInFlight = Math.max(0, this.contextInFlight - waiter.cost.contextTokens)
        // A probe that ends without a verdict — the session went idle, the
        // request was aborted, no response was recorded — must not keep the
        // circuit closed to everyone. Clear it so another probe can run.
        if (waiter.isProbe && this.probeInFlight && waiter.probeSeq === this.probeSeq) {
          this.probeInFlight = false
          this.probeStartedAt = 0
        }
        this.schedule([{ kind: "released", sessionID: waiter.sessionID }])
      },
    }
  }

  /**
   * Admits every waiter that fits, oldest first. `initial` carries transitions
   * from the caller so a release-and-handoff reaches subscribers as one change.
   */
  private schedule(initial: SchedulerTransition[] = []): void {
    if (this.scheduling) {
      if (initial.length > 0) this.onChange(initial)
      return
    }
    const transitions = [...initial]
    this.scheduling = true
    try {
      for (;;) {
        const now = this.now()
        if (this.active >= this.maxSlots) break
        const index = this.waiters.findIndex((waiter) => this.canAdmit(waiter, now))
        if (index === -1) break
        const [waiter] = this.waiters.splice(index, 1)
        transitions.push(this.applyAdmission(waiter, now))
      }
    } finally {
      this.scheduling = false
    }
    if (transitions.length > 0) this.onChange(transitions)
    this.armTimer()
  }

  /** Re-runs admission when the bucket refills or the cooldown ends. */
  private armTimer(): void {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = undefined
    }
    if (this.waiters.length === 0) return

    const now = this.now()
    let soonest = Number.POSITIVE_INFINITY
    if (this.openUntil > now) soonest = this.openUntil - now
    if (this.budget) {
      for (const waiter of this.waiters) {
        if (!this.fitsContext(waiter) && this.contextInFlight > 0) continue
        soonest = Math.min(soonest, this.budget.waitFor(waiter.cost.newTokens))
      }
    }
    if (!Number.isFinite(soonest) || soonest <= 0) return
    this.timer = setTimeout(() => {
      this.timer = undefined
      this.schedule()
    }, soonest)
  }

  private canAdmit(waiter: Waiter, now: number): boolean {
    if (this.draining) return false
    if (this.active >= this.maxSlots) return false
    if (!this.breakerAllows(now)) return false
    if (!this.fitsContext(waiter)) return false
    if (!this.budget) return true
    if (this.budget.waitFor(waiter.cost.newTokens) > 0) return false
    return !this.holdsReserve(waiter)
  }

  /**
   * The cap protects the provider from too much context at once. A single
   * request larger than the cap is still admitted when nothing is in flight,
   * so a shrink can never deadlock the queue.
   */
  private fitsContext(waiter: Waiter): boolean {
    if (this.contextCapacity === 0) return true
    if (this.contextInFlight === 0) return true
    return this.contextInFlight + waiter.cost.contextTokens <= this.contextCapacity
  }

  /**
   * A small request stops once it would eat into the reserve, so a large one
   * behind it can still fit when the bucket refills. An aged waiter ignores
   * the reserve and competes for what is available.
   */
  private holdsReserve(waiter: Waiter): boolean {
    if (!this.budget) return false
    if (waiter.cost.newTokens > this.smallShare * this.budget.capacity) return false
    if (this.now() - waiter.enqueuedAt >= this.agingMs) return false
    const available = this.budget.snapshot().available
    return available - waiter.cost.newTokens < this.reserveShare * this.budget.capacity
  }

  /** Open blocks everything; half-open admits exactly one probe. */
  private breakerAllows(now: number): boolean {
    if (this.openUntil === 0) return true
    if (now < this.openUntil) return false
    return !this.probeBlocks(now)
  }

  /**
   * Whether a running probe still owns the circuit. A probe that never reports
   * back must not wedge it, so after its lease it counts as inconclusive and a
   * new probe may run.
   */
  private probeBlocks(now: number): boolean {
    if (!this.probeInFlight) return false
    if (now - this.probeStartedAt >= PROBE_LEASE_MS) {
      this.probeInFlight = false
      this.probeStartedAt = 0
      return false
    }
    return true
  }

  private breakerState(now: number): SchedulerStatus["breaker"] {
    if (this.openUntil === 0) return "closed"
    if (now < this.openUntil) return "open"
    return "half-open"
  }

  /**
   * Opens the circuit. In fail mode every queued request is rejected at once,
   * so a dead provider cannot keep the queue deep; in wait mode they stay and
   * are admitted when the cooldown ends.
   */
  private open(now: number): void {
    this.openUntil = now + this.breakerCooldownMs
    this.probeInFlight = false
    this.probeStartedAt = 0
    if (this.breakerMode !== "fail") return
    const removed = this.waiters.splice(0)
    for (const waiter of removed) {
      if (waiter.signal && waiter.onAbort) waiter.signal.removeEventListener("abort", waiter.onAbort)
      this.clearDeadline(waiter)
      waiter.reject(circuitOpenError(this.openUntil - now))
    }
    if (removed.length > 0) {
      this.onChange(removed.map((waiter) => ({ kind: "dequeued" as const, sessionID: waiter.sessionID })))
    }
    // In `wait` mode the queue stays; schedule so the cooldown timer is armed.
    this.schedule()
  }

  private shrinkContext(): void {
    if (this.contextCapacity === 0) return
    const next = Math.max(1, Math.floor(this.contextCapacity / 2))
    if (next < this.contextCapacity) {
      this.contextCapacity = next
      this.schedule()
    }
  }

  private clearDeadline(waiter: Waiter): void {
    if (!waiter.deadlineTimer) return
    clearTimeout(waiter.deadlineTimer)
    waiter.deadlineTimer = undefined
  }
}

function assertSlots(max: number): void {
  if (!Number.isInteger(max) || max < 1) {
    throw new Error(`maxConcurrency must be a positive integer, got ${String(max)}`)
  }
}

function cancelledError(reason = "the request was aborted"): Error {
  const error = new Error(`request cancelled: ${reason}`)
  error.name = "AbortError"
  return error
}

function queueTimeoutError(deadlineMs: number): Error {
  const error = new Error(
    `request-concurrency-queue: no slot within ${Math.round(deadlineMs / 1000)}s; ` +
      "the provider is not draining, so the request was rejected instead of dying in the queue",
  )
  error.name = "QueueTimeoutError"
  return error
}

/** How long a half-open probe may run before it is treated as inconclusive. */
const PROBE_LEASE_MS = 330_000

function probeInFlightError(): Error {
  const error = new Error(
    "request-concurrency-queue: a test request is already checking whether the provider recovered; retry shortly",
  )
  error.name = "CircuitOpenError"
  return error
}

function circuitOpenError(retryAfterMs: number): Error {
  const seconds = Math.max(1, Math.ceil(retryAfterMs / 1000))
  const error = new Error(
    `request-concurrency-queue: provider circuit open after repeated stalls; retry in ${seconds}s`,
  )
  error.name = "CircuitOpenError"
  return error
}
