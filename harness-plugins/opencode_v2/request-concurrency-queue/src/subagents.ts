import { execFileSync } from "node:child_process"
import os from "node:os"

/** The host measurements the capacity decision reads. */
export interface HostMetrics {
  readonly cores: number
  /** One-minute load average, which includes every process on the machine. */
  readonly load1: number
  /** Free plus inactive memory in GiB. */
  readonly freeMemoryGB: number
}

export interface SubagentGateOptions {
  /** Hard ceiling: the most child sessions allowed to run at once. */
  readonly max: number
  /** Reduce the ceiling from host load. When false, `max` always applies. */
  readonly hostAware?: boolean
  /** Host probe override for tests. */
  readonly probe?: () => HostMetrics
}

/** One child session's permission to run. */
export interface SubagentPermit {
  /** Binds the permit to the child session that will hold it until idle. */
  bind(sessionID: string): void
  /** Frees the permit, whether or not it was bound. Idempotent. */
  release(): void
}

/** The gate's state as the status panel renders it. */
export interface SubagentStatus {
  /** Child sessions currently holding a permit. */
  readonly live: number
  /** Live child sessions that are calling the model right now. */
  readonly calling?: number
  /** Launches waiting for a permit. */
  readonly queued: number
  /** The configured ceiling. */
  readonly max: number
  /** The ceiling the host currently allows, at most `max`. */
  readonly capacity: number
}

interface Waiter {
  resolve(permit: SubagentPermit): void
  reject(error: Error): void
  readonly sessionID: string
  signal?: AbortSignal
  onAbort?: () => void
}

/**
 * The capacity the host allows for live child sessions.
 *
 * CPU load is the primary signal: a machine already running at its core count
 * has no room for another agent, however idle the model provider is. Memory is
 * a floor only when the machine is critically short, so a healthy Mac with a
 * large inactive cache is not mistaken for a full one.
 */
export function hostCapacity(max: number, metrics: HostMetrics): number {
  const byCpu = Math.floor(metrics.cores - metrics.load1)
  const byMemory = metrics.freeMemoryGB < 1 ? 1 : max
  return Math.max(1, Math.min(max, byCpu, byMemory))
}

let cachedMetrics: { at: number; value: HostMetrics } | undefined

/** Reads the host once, caching briefly so a launch burst cannot spam `vm_stat`. */
export function readHostMetrics(now = Date.now()): HostMetrics {
  if (cachedMetrics && now - cachedMetrics.at < 2_000) return cachedMetrics.value
  const value: HostMetrics = {
    cores: os.availableParallelism?.() ?? os.cpus().length,
    load1: os.loadavg()[0] ?? 0,
    freeMemoryGB: readFreeMemoryGB(),
  }
  cachedMetrics = { at: now, value }
  return value
}

/** The page size `vm_stat` prints in its header, e.g. `page size of 16384 bytes`. */
const PAGE_SIZE_IN_HEADER = /page size of (\d+) bytes/

/** A whole line counting free or inactive pages, e.g. `Pages free:  74469.`. */
const FREE_OR_INACTIVE_PAGE_LINE = /^Pages (free|inactive):/

/**
 * Free plus inactive memory from a `vm_stat` capture.
 *
 * The page size comes from the capture's own header, because Apple Silicon
 * reports 16384-byte pages and assuming 4096 would undercount fourfold. A
 * capture without a parseable header falls back to the injected page size.
 */
export function freeMemoryGBFromVmStat(vmStatOutput: string, fallbackPageSize: number): number {
  const header = vmStatOutput.match(PAGE_SIZE_IN_HEADER)
  const pageSize = header ? Number(header[1]) : fallbackPageSize
  let pages = 0
  for (const line of vmStatOutput.split("\n")) {
    if (!FREE_OR_INACTIVE_PAGE_LINE.test(line)) continue
    const match = line.match(/(\d+)\.?\s*$/)
    if (match) pages += Number(match[1])
  }
  return (pages * pageSize) / 1024 ** 3
}

/** Runs one host command and returns its standard output. */
export type CommandRunner = (file: string, args: string[]) => string

/** Test seams for `readFreeMemoryGB`; production uses the process defaults. */
export interface FreeMemoryProbeOptions {
  /** Replaces `execFileSync` for both the `vm_stat` and `sysctl` reads. */
  readonly run?: CommandRunner
  /** Replaces `process.platform`. */
  readonly platform?: NodeJS.Platform
}

const defaultCommandRunner: CommandRunner = (file, args) =>
  execFileSync(file, args, { encoding: "utf8" })

/**
 * Free plus inactive memory. Node's `os.freemem()` reports only truly free
 * pages on macOS and reads near zero on a healthy machine, so Darwin reads
 * `vm_stat` instead.
 */
export function readFreeMemoryGB(options: FreeMemoryProbeOptions = {}): number {
  const platform = options.platform ?? process.platform
  if (platform === "darwin") {
    const run = options.run ?? defaultCommandRunner
    try {
      const vmStat = run("vm_stat", [])
      const header = vmStat.match(PAGE_SIZE_IN_HEADER)
      // The header is the canonical page-size statement. Ask sysctl only when
      // it is absent or unparseable, and fall back to 4 KiB when both fail.
      let pageSize = header ? Number(header[1]) : undefined
      if (pageSize === undefined) {
        try {
          const fromSysctl = Number.parseInt(run("sysctl", ["-n", "hw.pagesize"]).trim(), 10)
          if (Number.isFinite(fromSysctl) && fromSysctl > 0) pageSize = fromSysctl
        } catch {
          // Neither source answered; the last resort below applies.
        }
      }
      return freeMemoryGBFromVmStat(vmStat, pageSize ?? 4096)
    } catch {
      // Fall through to the portable value.
    }
  }
  return os.freemem() / 1024 ** 3
}

/**
 * A FIFO gate for live child sessions.
 *
 * A subagent tool call returns as soon as the child is launched, so a permit
 * held around the call alone would not bound concurrency. The permit is bound
 * to the child's session ID and released when that session goes idle.
 */
export class SubagentGate {
  private max: number
  private readonly hostAware: boolean
  private readonly probe: () => HostMetrics
  private readonly live = new Set<string>()
  private readonly waiters: Waiter[] = []
  private draining = false
  /** Invalidates permits handed out before a `cancelAll`. */
  private generation = 0
  /**
   * Children that reported idle before their launch bound a permit. A fast or
   * instantly failing child can end first, and without this its permit would
   * never be released.
   */
  private readonly endedEarly = new Set<string>()
  /** Permits acquired by a launch that has not bound a child yet. */
  private pending = 0
  /** Re-runs admission while waiters exist, so a host that frees capacity admits them. */
  private recheckTimer?: ReturnType<typeof setTimeout>

  constructor(options: SubagentGateOptions) {
    if (!Number.isInteger(options.max) || options.max < 1) {
      throw new Error(`subagents.max must be a positive integer, got ${String(options.max)}`)
    }
    this.max = options.max
    this.hostAware = options.hostAware ?? false
    this.probe = options.probe ?? (() => readHostMetrics())
  }

  /** Stops admitting while a disposing instance frees its permits. */
  beginDrain(): void {
    this.draining = true
  }

  /** Resumes admission after a reload adopted this gate. */
  endDrain(): void {
    if (!this.draining) return
    this.draining = false
    this.serve()
  }

  /** Child sessions holding a permit, including launches not yet bound. */
  get liveCount(): number {
    return this.live.size + this.pending
  }

  get queuedCount(): number {
    return this.waiters.length
  }

  /**
   * Whether a capacity recheck is armed. Not part of `SubagentStatus`, so the
   * published RPC schema stays unchanged.
   */
  get recheckArmed(): boolean {
    return this.recheckTimer !== undefined
  }

  /** The child sessions holding a permit, excluding launches not yet bound. */
  liveSessionIDs(): ReadonlySet<string> {
    return new Set(this.live)
  }

  /** Changes the hard ceiling; raising it serves waiting launches at once. */
  setMax(max: number): void {
    if (!Number.isInteger(max) || max < 1) {
      throw new Error(`subagents.max must be a positive integer, got ${String(max)}`)
    }
    if (max === this.max) return
    this.max = max
    this.serve()
  }

  /** The ceiling the host currently allows. */
  capacity(): number {
    return this.hostAware ? hostCapacity(this.max, this.probe()) : this.max
  }

  status(): SubagentStatus {
    return {
      live: this.liveCount,
      queued: this.waiters.length,
      max: this.max,
      capacity: this.capacity(),
    }
  }

  acquire(sessionID: string, signal?: AbortSignal): Promise<SubagentPermit> {
    if (signal?.aborted) return Promise.reject(cancelledError())

    // A launch behind a waiter joins the queue instead of overtaking it, and a
    // launch during a drain is held even when capacity looks free.
    if (this.waiters.length === 0 && !this.draining && this.liveCount < this.capacity()) {
      this.pending += 1
      return Promise.resolve(this.createPermit())
    }

    return new Promise<SubagentPermit>((resolve, reject) => {
      const waiter: Waiter = { resolve, reject, sessionID, signal }
      if (signal) {
        waiter.onAbort = () => {
          const index = this.waiters.indexOf(waiter)
          if (index !== -1) this.waiters.splice(index, 1)
          // The last waiter's abort leaves nothing to recheck.
          if (this.waiters.length === 0) this.clearRecheck()
          reject(cancelledError())
        }
        signal.addEventListener("abort", waiter.onAbort, { once: true })
      }
      this.waiters.push(waiter)
      // Admission still happens on the queue path, so a launch that fits is
      // served at once rather than waiting for a release.
      this.serve()
    })
  }

  /** Releases the permit bound to `sessionID`, if any, and serves the queue. */
  releaseSession(sessionID: string): void {
    if (this.live.delete(sessionID)) {
      this.serve()
      return
    }
    // No permit is bound yet. If a launch is outstanding, the child may have
    // ended before `bind` ran, so remember it for that bind.
    if (this.pending > 0) {
      this.endedEarly.add(sessionID)
      if (this.endedEarly.size > 256) {
        const oldest = this.endedEarly.values().next()
        if (!oldest.done) this.endedEarly.delete(oldest.value)
      }
    }
  }

  /** Rejects every waiter and frees every permit. */
  cancelAll(reason = "the fan-out gate was unloaded"): void {
    this.generation += 1
    this.endedEarly.clear()
    this.clearRecheck()
    for (const waiter of this.waiters.splice(0)) {
      if (waiter.signal && waiter.onAbort) {
        waiter.signal.removeEventListener("abort", waiter.onAbort)
      }
      waiter.reject(cancelledError(reason))
    }
    this.live.clear()
    this.pending = 0
    // A teardown is `beginDrain()` then `cancelAll()` with no `endDrain`, so
    // the drain must end here or a post-cancel launch would queue forever.
    this.draining = false
  }

  private createPermit(): SubagentPermit {
    let state: "pending" | "bound" | "released" = "pending"
    let child: string | undefined
    const generation = this.generation

    const release = () => {
      if (state === "released") return
      // A permit from before a `cancelAll` no longer counts toward the gate.
      if (generation !== this.generation) {
        state = "released"
        return
      }
      if (state === "pending") this.pending -= 1
      else if (child) this.live.delete(child)
      state = "released"
      this.serve()
    }

    return {
      bind: (sessionID: string) => {
        if (state !== "pending" || generation !== this.generation) return
        this.pending -= 1
        child = sessionID
        state = "bound"
        // The child already went idle before this launch could bind: do not
        // hold a slot for a session that is finished.
        if (this.endedEarly.delete(sessionID)) {
          state = "released"
          this.serve()
          return
        }
        this.live.add(sessionID)
      },
      release,
    }
  }

  private serve(): void {
    if (this.draining) return
    while (this.waiters.length > 0 && this.liveCount < this.capacity()) {
      const next = this.waiters.shift()
      if (!next) return
      if (next.signal && next.onAbort) {
        next.signal.removeEventListener("abort", next.onAbort)
      }
      this.pending += 1
      next.resolve(this.createPermit())
    }
    this.armRecheck()
  }

  /**
   * Re-checks capacity on a timer while waiters exist, so a host that frees a
   * slot admits them without another permit being released. The scheduler's
   * `armTimer` bounds the same idle time for its gates.
   */
  private armRecheck(): void {
    if (!this.hostAware || this.waiters.length === 0) {
      this.clearRecheck()
      return
    }
    // Already armed; the callback re-arms itself after each probe.
    if (this.recheckTimer) return
    const timer = setTimeout(() => {
      this.recheckTimer = undefined
      if (this.waiters.length === 0) return
      this.serve()
    }, RECHECK_MS)
    timer.unref?.()
    this.recheckTimer = timer
  }

  private clearRecheck(): void {
    if (!this.recheckTimer) return
    clearTimeout(this.recheckTimer)
    this.recheckTimer = undefined
  }
}

/** A whole string that is a session ID, never a fragment of prose. */
const SESSION_ID = /^ses_[A-Za-z0-9]+$/

/** How often a queued launch re-checks the host while `hostAware` is set. */
const RECHECK_MS = 2_000

/**
 * Finds the child session ID in a subagent tool result.
 *
 * Only a string that is entirely a session ID counts. Matching the first
 * `ses_…` anywhere in the result would pick up an ID the tool merely mentions,
 * bind the permit to the wrong child, and hold that slot until the session ends.
 *
 * An explicit `sessionID` key wins over the whole-string walk, at the top level
 * and under `metadata`. A result may name the parent session alongside the
 * child's own ID, and the walk follows insertion order, so leaving the choice
 * to it can bind the permit to the parent and hold that slot until it ends.
 */
export function extractSessionID(result: unknown): string | undefined {
  const record = result !== null && typeof result === "object"
    ? (result as Record<string, unknown>)
    : undefined
  if (record) {
    if (typeof record.sessionID === "string" && SESSION_ID.test(record.sessionID)) {
      return record.sessionID
    }
    const metadata = record.metadata
    if (metadata !== null && typeof metadata === "object") {
      const nested = (metadata as Record<string, unknown>).sessionID
      if (typeof nested === "string" && SESSION_ID.test(nested)) return nested
    }
  }
  return findSessionID(result, 0)
}

function findSessionID(value: unknown, depth: number): string | undefined {
  if (depth > 4 || value === null || value === undefined) return undefined
  if (typeof value === "string") return SESSION_ID.test(value) ? value : undefined
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findSessionID(item, depth + 1)
      if (found) return found
    }
    return undefined
  }
  if (typeof value === "object") {
    for (const item of Object.values(value as Record<string, unknown>)) {
      const found = findSessionID(item, depth + 1)
      if (found) return found
    }
  }
  return undefined
}

function cancelledError(reason = "the session was interrupted"): Error {
  const error = new Error(`subagent launch cancelled: ${reason}`)
  error.name = "AbortError"
  return error
}
