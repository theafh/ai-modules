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
  /** The active count immediately after this transition. */
  readonly active: number
  /** The queued count immediately after this transition. */
  readonly queued: number
}

export type SchedulerListener = (transitions: readonly SchedulerTransition[]) => void

/** How many waiting requests each admission gate is holding back. */
export interface BlockedCounts {
  /** Waiting for a free concurrency slot. */
  readonly slots: number
  /** Waiting for room under the in-flight context cap. */
  readonly context: number
  /** Waiting for the provider's new-token budget or its reserve. */
  readonly budget: number
  /** Waiting for the circuit breaker to allow a probe. */
  readonly breaker: number
  /** Waiting because a disposing instance paused admission. */
  readonly draining: number
}

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
  /**
   * Upper bound the adaptive context cap may grow back to. `0` keeps the cap
   * fixed: it never shrinks and never grows.
   */
  contextCeiling?: number
  /** Fraction of the budget kept available for requests above the small threshold. */
  reserveShare?: number
  /** Fraction of budget capacity at or below which a request counts as small. */
  smallShare?: number
  /** A waiter older than this ignores the reserve and the context cap. */
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
  /**
   * True for an auxiliary request: it waits for the provider's token budget but
   * takes no concurrency slot and no context room, because the runtime offers no
   * release path for one that dies before its response headers.
   */
  readonly budgetOnly?: boolean
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
  /** Active requests per session, so the panel can say who is calling the model. */
  private readonly activeSessions = new Map<string, number>()
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

  /** Sessions holding at least one model-request slot right now. */
  activeSessionIDs(): ReadonlySet<string> {
    return new Set(this.activeSessions.keys())
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

  /** How many waiting requests each gate is currently holding back. */
  blocked(): BlockedCounts {
    const now = this.now()
    const counts = { slots: 0, context: 0, budget: 0, breaker: 0, draining: 0 }
    for (const waiter of this.waiters) {
      if (this.draining) {
        counts.draining += 1
        continue
      }
      if (!this.breakerAllows(now)) {
        counts.breaker += 1
        continue
      }
      if (!waiter.budgetOnly && this.active >= this.maxSlots) {
        counts.slots += 1
        continue
      }
      if (!waiter.budgetOnly && !this.fitsContext(waiter, now)) {
        counts.context += 1
        continue
      }
      if (this.budget && (this.budget.waitFor(waiter.cost.newTokens) > 0 || this.holdsReserve(waiter, now))) {
        counts.budget += 1
      }
    }
    return counts
  }

  acquire(
    sessionID: string,
    cost: RequestCost = { newTokens: 0, contextTokens: 0 },
    signal?: AbortSignal,
  ): Promise<SchedulerSlot> {
    return this.enqueue(sessionID, cost, signal, false)
  }

  /**
   * Waits for the provider's new-token budget without taking a concurrency slot
   * or context room, for an auxiliary request such as compaction. The spend is
   * not refunded: a request that never reaches the provider only under-uses the
   * budget, which is the safe side.
   */
  acquireBudget(
    sessionID: string,
    cost: RequestCost = { newTokens: 0, contextTokens: 0 },
    signal?: AbortSignal,
  ): Promise<SchedulerSlot> {
    return this.enqueue(sessionID, cost, signal, true)
  }

  private enqueue(
    sessionID: string,
    cost: RequestCost,
    signal: AbortSignal | undefined,
    budgetOnly: boolean,
  ): Promise<SchedulerSlot> {
    if (signal?.aborted) return Promise.reject(cancelledError())

    const now = this.now()
    const state = this.breakerState(now)
    // While open, `fail` rejects at once so a dead provider cannot grow the
    // queue. Half-open does not reject: a slot-holding request queues behind
    // the single probe and is admitted when the probe settles or its lease runs
    // out, while a budget-only request is admitted at once when no probe is in
    // flight and queues behind one when a probe is running.
    if (this.breakerMode === "fail" && state === "open") {
      return Promise.reject(circuitOpenError(this.openUntil - now))
    }

    return new Promise<SchedulerSlot>((resolve, reject) => {
      const waiter: Waiter = {
        sessionID,
        cost: {
          newTokens: Math.max(0, Math.floor(cost.newTokens)),
          contextTokens: Math.max(0, Math.floor(cost.contextTokens)),
        },
        enqueuedAt: now,
        budgetOnly,
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
            this.onChange([this.transition("dequeued", sessionID)])
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
          this.onChange([this.transition("dequeued", sessionID)])
          reject(queueTimeoutError(this.queueDeadlineMs))
        }, this.queueDeadlineMs)
      }

      this.waiters.push(waiter)
      this.onChange([this.transition("queued", sessionID)])
      this.schedule()
    })
  }

  /**
   * Records one attempt that produced no response: a transport stall or a
   * header timeout. The cap shrinks only when the breaker opens, because a
   * single transient failure must not cut the whole fan-out's width; it then
   * grows back in quarters on clean completions.
   *
   * A stall recorded while the cooldown is still running is a straggler that
   * was admitted before the circuit opened: it neither extends the cooldown nor
   * shrinks the cap again. Only a stall at or after the cooldown — the probe's
   * own failure, or an auxiliary `5xx` that reaches this method on its own path
   * — reopens the circuit with a fresh cooldown.
   */
  recordStall(): void {
    const now = this.now()
    this.stalls += 1
    // The cooldown's own time key is the rule: nothing is admitted during it,
    // so a stall that lands then came from a request admitted before it opened.
    if (this.openUntil > now) return
    const halfOpen = this.openUntil > 0 && now >= this.openUntil
    if (halfOpen || this.stalls >= this.breakerThreshold) {
      this.open(now)
      this.shrinkContext()
    }
  }

  /**
   * Records one served request: the context cap grows on every success, and
   * only a success at or after the cooldown closes the circuit and serves the
   * queue. A success recorded before the cooldown ends is a straggler admitted
   * before the circuit opened, so it leaves the circuit as it is.
   */
  recordSuccess(): void {
    const now = this.now()
    this.stalls = 0
    // A straggler's success is real evidence that the provider serves again, so
    // it grows the cap; only a success at or after the cooldown — the probe's —
    // may close the circuit.
    if (!(this.openUntil > 0 && now < this.openUntil)) {
      this.openUntil = 0
      this.probeInFlight = false
      this.probeStartedAt = 0
    }
    if (this.contextCapacity !== 0 && this.contextCeiling !== 0) {
      const gap = this.contextCeiling - this.contextCapacity
      if (gap > 0) {
        const step = Math.max(1, Math.ceil(gap * 0.25))
        this.contextCapacity = Math.min(this.contextCeiling, this.contextCapacity + step)
      }
    }
    // A closed circuit frees anything that waited in `wait` mode, and a grown
    // cap frees a context-bound waiter, so this runs on every success.
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
    this.onChange(removed.map(() => this.transition("dequeued", sessionID)))
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
      this.onChange(removed.map((waiter) => this.transition("dequeued", waiter.sessionID)))
    }
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = undefined
    }
  }

  /** One count-changing transition, captured with the counts it produced. */
  private transition(kind: TransitionKind, sessionID: string): SchedulerTransition {
    return { kind, sessionID, active: this.active, queued: this.waiters.length }
  }

  /** Applies one admission and returns its transition; the caller emits it. */
  private applyAdmission(waiter: Waiter, now = this.now()): SchedulerTransition {
    if (waiter.signal && waiter.onAbort) waiter.signal.removeEventListener("abort", waiter.onAbort)
    this.clearDeadline(waiter)
    // Only a slot-holding request can be the probe: it has a release path, so a
    // probe that never reports back still frees the circuit. A budget-only
    // request admitted at half-open leaves the probe to the first slot waiter.
    if (!waiter.budgetOnly && this.openUntil > 0 && now >= this.openUntil) {
      this.probeSeq += 1
      this.probeInFlight = true
      this.probeStartedAt = now
      waiter.isProbe = true
      waiter.probeSeq = this.probeSeq
    }
    this.budget?.spend(waiter.cost.newTokens)
    if (!waiter.budgetOnly) {
      this.active += 1
      this.contextInFlight += waiter.cost.contextTokens
      this.activeSessions.set(waiter.sessionID, (this.activeSessions.get(waiter.sessionID) ?? 0) + 1)
    }
    waiter.resolve(waiter.budgetOnly ? { release() {} } : this.createSlot(waiter))
    return this.transition("acquired", waiter.sessionID)
  }

  private createSlot(waiter: Waiter): SchedulerSlot {
    let released = false
    return {
      release: () => {
        if (released) return
        released = true
        this.active -= 1
        this.contextInFlight = Math.max(0, this.contextInFlight - waiter.cost.contextTokens)
        const held = this.activeSessions.get(waiter.sessionID) ?? 0
        if (held <= 1) this.activeSessions.delete(waiter.sessionID)
        else this.activeSessions.set(waiter.sessionID, held - 1)
        // A probe that ends without a verdict — the session went idle, the
        // request was aborted, no response was recorded — must not keep the
        // circuit closed to everyone. Clear it so another probe can run.
        if (waiter.isProbe && this.probeInFlight && waiter.probeSeq === this.probeSeq) {
          this.probeInFlight = false
          this.probeStartedAt = 0
        }
        this.schedule([this.transition("released", waiter.sessionID)])
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
        // A budget-only waiter fits beside a full slot set, so the loop cannot
        // stop at the concurrency ceiling; `canAdmit` applies each gate.
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

  /**
   * Re-runs admission when the next time-driven gate lifts: the bucket refills,
   * the reserve stops holding a small request, the context aging window opens,
   * or the cooldown ends.
   *
   * A queued request must never depend on another request's release to be
   * checked again. In a fan-out every session can be waiting on its own queued
   * request, so no release comes, and a gate that lifts with time alone would
   * otherwise leave free slots and a full bucket idle. The recheck interval
   * bounds that idle time for any gate without a computed wake-up.
   */
  private armTimer(): void {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = undefined
    }
    if (this.waiters.length === 0) return

    const now = this.now()
    let soonest = RECHECK_MS
    if (this.openUntil > now) soonest = Math.min(soonest, this.openUntil - now)
    for (const waiter of this.waiters) {
      if (!waiter.budgetOnly && !this.fitsContext(waiter, now) && this.contextInFlight > 0) {
        const aging = waiter.enqueuedAt + this.agingMs - now
        if (aging > 0) soonest = Math.min(soonest, aging)
        continue
      }
      const wait = this.budgetDelay(waiter, now)
      if (wait > 0) soonest = Math.min(soonest, wait)
    }
    this.timer = setTimeout(() => {
      this.timer = undefined
      this.schedule()
    }, Math.max(1, Math.ceil(soonest)))
  }

  /**
   * Milliseconds until the budget lets this waiter through, the reserve
   * included; 0 when the budget already does.
   */
  private budgetDelay(waiter: Waiter, now: number): number {
    if (!this.budget) return 0
    const wait = this.budget.waitFor(waiter.cost.newTokens)
    if (wait > 0) return wait
    return this.reserveDelay(waiter, now)
  }

  private canAdmit(waiter: Waiter, now: number): boolean {
    if (this.draining) return false
    if (!this.breakerAllows(now)) return false
    if (!waiter.budgetOnly) {
      if (this.active >= this.maxSlots) return false
      if (!this.fitsContext(waiter, now)) return false
    }
    if (!this.budget) return true
    if (this.budget.waitFor(waiter.cost.newTokens) > 0) return false
    return !this.holdsReserve(waiter, now)
  }

  /**
   * The cap protects the provider from too much context at once. A single
   * request larger than the cap is still admitted when nothing is in flight,
   * and a waiter that has aged past `agingMs` is admitted anyway, so the cap
   * can neither deadlock the queue nor starve one large request behind a
   * stream of smaller ones.
   */
  private fitsContext(waiter: Waiter, now: number): boolean {
    if (this.contextCapacity === 0) return true
    if (this.contextInFlight === 0) return true
    if (this.contextInFlight + waiter.cost.contextTokens <= this.contextCapacity) return true
    return this.agingMs > 0 && now - waiter.enqueuedAt >= this.agingMs
  }

  /**
   * A small request stops once it would eat into the reserve, so a large one
   * behind it can still fit when the bucket refills. The reserve only applies
   * while a large request is actually waiting: with no such demand, holding a
   * lone request back would add latency and protect nobody. An aged waiter
   * ignores the reserve and competes for what is available.
   */
  private holdsReserve(waiter: Waiter, now: number): boolean {
    if (!this.budget) return false
    if (waiter.cost.newTokens > this.smallShare * this.budget.capacity) return false
    if (!this.hasLargeWaiter(waiter)) return false
    return this.reserveDelay(waiter, now) > 0
  }

  /** Whether a request above the small threshold is waiting behind this one. */
  private hasLargeWaiter(exclude: Waiter): boolean {
    if (!this.budget) return false
    const threshold = this.smallShare * this.budget.capacity
    return this.waiters.some((waiter) => waiter !== exclude && waiter.cost.newTokens > threshold)
  }

  /**
   * Milliseconds until the reserve stops holding this waiter back; 0 when it
   * does not hold it. The hold ends at whichever comes first: the waiter ages
   * past `agingMs`, or the bucket refills enough to cover the request and still
   * keep the reserve. A request that can never fit beside the reserve waits for
   * aging alone.
   */
  private reserveDelay(waiter: Waiter, now: number): number {
    if (!this.budget) return 0
    if (waiter.cost.newTokens > this.smallShare * this.budget.capacity) return 0
    const aging = waiter.enqueuedAt + this.agingMs - now
    if (aging <= 0) return 0
    const needed = waiter.cost.newTokens + this.reserveShare * this.budget.capacity
    const refill = needed > this.budget.capacity ? Number.POSITIVE_INFINITY : this.budget.waitFor(needed)
    if (refill <= 0) return 0
    return Math.min(aging, refill)
  }

  /**
   * Open blocks everything. Half-open admits one slot-holding probe, and
   * budget-only work while no probe is in flight.
   */
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
      this.onChange(removed.map((waiter) => this.transition("dequeued", waiter.sessionID)))
    }
    // In `wait` mode the queue stays; schedule so the cooldown timer is armed.
    this.schedule()
  }

  private shrinkContext(): void {
    if (this.contextCapacity === 0) return
    // `contextCeiling: 0` means the operator fixed the cap: never shrink it.
    if (this.contextCeiling === 0) return
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

/**
 * Longest a queued request goes without being checked again. It covers the
 * gates that lift without a release and carry no computed wake-up, such as a
 * probe lease running out.
 */
const RECHECK_MS = 2_000

function circuitOpenError(retryAfterMs: number): Error {
  const seconds = Math.max(1, Math.ceil(retryAfterMs / 1000))
  const error = new Error(
    `request-concurrency-queue: provider circuit open after repeated stalls; retry in ${seconds}s`,
  )
  error.name = "CircuitOpenError"
  return error
}
