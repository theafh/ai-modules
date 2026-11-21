/**
 * A token bucket for a provider's new-context allowance.
 *
 * Providers meter *new, uncached* context: a budget that can
 * be spent all at once and refills at a fixed rate. The bucket refills lazily on
 * read, so a waiting request costs no timer and no background work.
 */
export interface TokenBudgetOptions {
  /** Tokens that may be spent at once, e.g. 500000. */
  readonly capacity: number
  /** Tokens added back per minute, e.g. 500000. */
  readonly refillPerMinute: number
  /** Multiplier applied by `estimateTokens`; 1 means no extra margin. */
  readonly safetyFactor?: number
  /** Clock override for tests. */
  readonly now?: () => number
}

/** The bucket's state as the status panel renders it. */
export interface TokenBudgetSnapshot {
  /** Whole tokens currently available; never negative. */
  readonly available: number
  readonly capacity: number
  /** Epoch milliseconds until which the provider asked us to wait; 0 when not paused. */
  readonly pausedUntil: number
}

export class TokenBudget {
  capacity: number
  refillPerMs: number
  safetyFactor: number
  private readonly now: () => number
  private available: number
  private lastRefill: number
  private pausedUntil = 0

  constructor(options: TokenBudgetOptions) {
    if (!Number.isFinite(options.capacity) || options.capacity <= 0) {
      throw new Error(`token budget capacity must be positive, got ${String(options.capacity)}`)
    }
    if (!Number.isFinite(options.refillPerMinute) || options.refillPerMinute <= 0) {
      throw new Error(
        `token budget refillPerMinute must be positive, got ${String(options.refillPerMinute)}`,
      )
    }
    this.capacity = options.capacity
    this.refillPerMs = options.refillPerMinute / 60_000
    this.safetyFactor = options.safetyFactor ?? 1
    this.now = options.now ?? Date.now
    this.available = this.capacity
    this.lastRefill = this.now()
  }

  /**
   * Applies new limits without losing the bucket's current fill. A larger
   * capacity is available at once; a smaller one clamps what is available.
   */
  reconfigure(options: { capacity: number; refillPerMinute: number; safetyFactor?: number }): void {
    if (!Number.isFinite(options.capacity) || options.capacity <= 0) {
      throw new Error(`token budget capacity must be positive, got ${String(options.capacity)}`)
    }
    if (!Number.isFinite(options.refillPerMinute) || options.refillPerMinute <= 0) {
      throw new Error(
        `token budget refillPerMinute must be positive, got ${String(options.refillPerMinute)}`,
      )
    }
    this.capacity = options.capacity
    this.refillPerMs = options.refillPerMinute / 60_000
    this.safetyFactor = options.safetyFactor ?? 1
    this.available = Math.min(this.available, this.capacity)
  }

  /** Milliseconds until `tokens` can be spent; 0 when they can be spent now. */
  waitFor(tokens: number, now = this.now()): number {
    this.refill(now)
    if (now < this.pausedUntil) return this.pausedUntil - now
    if (tokens <= this.available) return 0
    // A request larger than the bucket can never be covered by waiting: the
    // bucket never holds more than its capacity. Admitting it lets the provider
    // answer (and reject it) instead of parking it in the queue forever.
    if (tokens > this.capacity) return 0
    return Math.ceil((tokens - this.available) / this.refillPerMs)
  }

  /** Spends `tokens`. Call only when `waitFor` returned 0. */
  spend(tokens: number, now = this.now()): void {
    this.refill(now)
    this.available = Math.max(0, this.available - tokens)
  }

  /** Pauses every request for `seconds`, as a provider `Retry-After` asks. */
  pause(seconds: number, now = this.now()): void {
    if (!Number.isFinite(seconds) || seconds <= 0) return
    this.pausedUntil = Math.max(this.pausedUntil, now + seconds * 1000)
  }

  snapshot(now = this.now()): TokenBudgetSnapshot {
    this.refill(now)
    return {
      available: Math.max(0, Math.floor(this.available)),
      capacity: this.capacity,
      pausedUntil: this.pausedUntil,
    }
  }

  private refill(now: number): void {
    if (now <= this.lastRefill) return
    this.available = Math.min(this.capacity, this.available + (now - this.lastRefill) * this.refillPerMs)
    this.lastRefill = now
  }
}

/**
 * Bytes per token used to turn a request size into a token estimate. A value
 * below the usual 4 bytes per token deliberately over-estimates: the gate then
 * waits slightly longer than strictly needed instead of overshooting the
 * provider's budget.
 */
export const BYTES_PER_TOKEN = 3.5

/** Estimates a token count from a byte count, over-estimating on purpose. */
export function estimateTokens(bytes: number, safetyFactor = 1): number {
  if (!Number.isFinite(bytes) || bytes <= 0) return 0
  return Math.ceil((bytes / BYTES_PER_TOKEN) * safetyFactor)
}

/** Parses a `Retry-After` header, in seconds or as an HTTP date. */
export function parseRetryAfter(value: string | null, now = Date.now()): number {
  if (!value) return 0
  const seconds = Number(value)
  if (Number.isFinite(seconds)) return Math.max(0, seconds)
  const at = Date.parse(value)
  if (Number.isNaN(at)) return 0
  return Math.max(0, Math.ceil((at - now) / 1000))
}
