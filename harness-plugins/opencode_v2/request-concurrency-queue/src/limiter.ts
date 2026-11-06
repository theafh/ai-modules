export interface Slot {
  release(): void
}

interface Waiter {
  resolve(slot: Slot): void
  reject(error: Error): void
  signal?: AbortSignal
  onAbort?: () => void
}

export class FifoLimiter {
  private active = 0
  private readonly waiters: Waiter[] = []

  constructor(
    private readonly max: number,
    private readonly onChange: () => void = () => {},
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

  acquire(signal?: AbortSignal): Promise<Slot> {
    if (signal?.aborted) return Promise.reject(abortError())

    if (this.active < this.max) {
      this.active += 1
      this.onChange()
      return Promise.resolve(this.createSlot())
    }

    return new Promise<Slot>((resolve, reject) => {
      const waiter: Waiter = { resolve, reject, signal }

      if (signal) {
        waiter.onAbort = () => {
          const index = this.waiters.indexOf(waiter)
          if (index !== -1) {
            this.waiters.splice(index, 1)
            this.onChange()
          }
          reject(abortError())
        }
        signal.addEventListener("abort", waiter.onAbort, { once: true })
      }

      this.waiters.push(waiter)
      this.onChange()
    })
  }

  private createSlot(): Slot {
    let released = false
    return {
      release: () => {
        if (released) return
        released = true
        this.release()
      },
    }
  }

  private release(): void {
    const next = this.waiters.shift()
    if (!next) {
      this.active -= 1
      this.onChange()
      return
    }

    if (next.signal && next.onAbort) {
      next.signal.removeEventListener("abort", next.onAbort)
    }
    next.resolve(this.createSlot())
    this.onChange()
  }
}

function abortError(): Error {
  const error = new Error("request concurrency queue acquire aborted")
  error.name = "AbortError"
  return error
}
