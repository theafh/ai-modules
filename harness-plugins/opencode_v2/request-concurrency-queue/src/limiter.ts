import type { TransitionKind } from "./rpc.js"

export interface Slot {
  release(): void
}

/** One transition a limiter site reports, carrying the affected session ID. */
export interface LimiterTransition {
  readonly kind: TransitionKind
  readonly sessionID: string
}

/**
 * Receives one notification per count-changing transition. A handoff reports
 * both of its buffer entries in a single call, so a listener still emits one
 * `changed` event and the releasing and acquiring sessions both appear.
 */
export type TransitionListener = (transitions: readonly LimiterTransition[]) => void

interface Waiter {
  resolve(slot: Slot): void
  reject(error: Error): void
  readonly sessionID: string
  signal?: AbortSignal
  onAbort?: () => void
}

export class FifoLimiter {
  private active = 0
  private waiters: Waiter[] = []
  private max: number

  constructor(
    max: number,
    private readonly onChange: TransitionListener = () => {},
  ) {
    assertMax(max)
    this.max = max
  }

  get activeCount(): number {
    return this.active
  }

  get queuedCount(): number {
    return this.waiters.length
  }

  /** The effective maximum, which adaptive control may lower and raise. */
  get maxConcurrency(): number {
    return this.max
  }

  /**
   * Changes the effective maximum. Raising it serves waiting requests at once;
   * lowering it admits nothing new until the active count drops below it.
   */
  setMax(max: number): void {
    assertMax(max)
    if (max === this.max) return
    this.max = max
    this.serveWaiters()
  }

  acquire(sessionID: string, signal?: AbortSignal): Promise<Slot> {
    if (signal?.aborted) return Promise.reject(abortError())

    if (this.active < this.max) {
      this.active += 1
      this.onChange([{ kind: "acquired", sessionID }])
      return Promise.resolve(this.createSlot(sessionID))
    }

    return new Promise<Slot>((resolve, reject) => {
      const waiter: Waiter = { resolve, reject, sessionID, signal }

      if (signal) {
        waiter.onAbort = () => {
          const index = this.waiters.indexOf(waiter)
          if (index !== -1) {
            this.waiters.splice(index, 1)
            this.onChange([{ kind: "dequeued", sessionID }])
          }
          reject(abortError())
        }
        signal.addEventListener("abort", waiter.onAbort, { once: true })
      }

      this.waiters.push(waiter)
      this.onChange([{ kind: "queued", sessionID }])
    })
  }

  /**
   * Removes and rejects every waiter belonging to `sessionID`.
   *
   * A waiting request is not in the caller's running set, so a session that
   * ends while its request still waits would otherwise be dispatched later,
   * for a session nobody is listening to. Returns how many waiters were
   * removed.
   */
  cancelSession(sessionID: string): number {
    const removed: Waiter[] = []
    this.waiters = this.waiters.filter((waiter) => {
      if (waiter.sessionID !== sessionID) return true
      removed.push(waiter)
      return false
    })
    if (removed.length === 0) return 0

    for (const waiter of removed) {
      if (waiter.signal && waiter.onAbort) {
        waiter.signal.removeEventListener("abort", waiter.onAbort)
      }
      waiter.reject(cancelledError())
    }
    this.onChange(removed.map(() => ({ kind: "dequeued" as const, sessionID })))
    return removed.length
  }

  /** Removes and rejects every waiter, whatever its session. */
  cancelAll(): number {
    const removed = this.waiters
    this.waiters = []
    for (const waiter of removed) {
      if (waiter.signal && waiter.onAbort) {
        waiter.signal.removeEventListener("abort", waiter.onAbort)
      }
      waiter.reject(cancelledError())
    }
    if (removed.length > 0) {
      this.onChange(removed.map((waiter) => ({ kind: "dequeued" as const, sessionID: waiter.sessionID })))
    }
    return removed.length
  }

  private createSlot(sessionID: string): Slot {
    let released = false
    return {
      release: () => {
        if (released) return
        released = true
        this.release(sessionID)
      },
    }
  }

  private release(sessionID: string): void {
    this.active -= 1

    // Adaptive control may have lowered the maximum below the number of
    // requests already running. In that case the freed slot is not handed out
    // until enough of them finish to drop below the new maximum.
    if (this.active >= this.max) {
      this.onChange([{ kind: "released", sessionID }])
      return
    }

    const next = this.waiters.shift()
    if (!next) {
      this.onChange([{ kind: "released", sessionID }])
      return
    }

    if (next.signal && next.onAbort) {
      next.signal.removeEventListener("abort", next.onAbort)
    }
    this.active += 1
    next.resolve(this.createSlot(next.sessionID))
    // One notification carries both entries: the releasing session frees the
    // slot and the waiter takes it, while the active count stays the same.
    this.onChange([
      { kind: "released", sessionID },
      { kind: "acquired", sessionID: next.sessionID },
    ])
  }

  /** Admits waiters while the effective maximum allows it. */
  private serveWaiters(): void {
    while (this.active < this.max && this.waiters.length > 0) {
      const next = this.waiters.shift()
      if (!next) return
      if (next.signal && next.onAbort) {
        next.signal.removeEventListener("abort", next.onAbort)
      }
      this.active += 1
      next.resolve(this.createSlot(next.sessionID))
      this.onChange([{ kind: "acquired", sessionID: next.sessionID }])
    }
  }
}

function assertMax(max: number): void {
  if (!Number.isInteger(max) || max < 1) {
    throw new Error(`maxConcurrency must be a positive integer, got ${String(max)}`)
  }
}

function abortError(): Error {
  const error = new Error("request concurrency queue acquire aborted")
  error.name = "AbortError"
  return error
}

function cancelledError(): Error {
  const error = new Error("request concurrency queue waiter cancelled: session ended")
  error.name = "AbortError"
  return error
}
