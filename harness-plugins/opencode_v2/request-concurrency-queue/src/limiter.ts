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
  private readonly waiters: Waiter[] = []

  constructor(
    private readonly max: number,
    private readonly onChange: TransitionListener = () => {},
  ) {
    if (!Number.isInteger(max) || max < 1) {
      throw new Error(`maxConcurrency must be a positive integer, got ${String(max)}`)
    }
  }

  get activeCount(): number {
    return this.active
  }

  get queuedCount(): number {
    return this.waiters.length
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
    const next = this.waiters.shift()
    if (!next) {
      this.active -= 1
      this.onChange([{ kind: "released", sessionID }])
      return
    }

    if (next.signal && next.onAbort) {
      next.signal.removeEventListener("abort", next.onAbort)
    }
    next.resolve(this.createSlot(next.sessionID))
    // One notification carries both entries: the releasing session frees the
    // slot and the waiter takes it, while the active count stays the same.
    this.onChange([
      { kind: "released", sessionID },
      { kind: "acquired", sessionID: next.sessionID },
    ])
  }
}

function abortError(): Error {
  const error = new Error("request concurrency queue acquire aborted")
  error.name = "AbortError"
  return error
}
