import { Plugin } from "@opencode/plugin"
import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"
import { estimateTokens, parseRetryAfter, type TokenBudgetOptions } from "./budget.js"
import type { Slot } from "./limiter.js"
import { statusRpc, type ConfigSnapshot, type SaveResult } from "./rpc.js"
import {
  adoptStore,
  applyConfig,
  releaseStore,
  snapshotOf,
  subscribeStore,
  type SchedulerConfig,
  type ProviderLimit,
  type Store,
} from "./store.js"
import { extractSessionID, type SubagentGateOptions } from "./subagents.js"

/** How many clean completions restore one adaptive concurrency step. */
const RECOVERY_STREAK = 4

export interface TokenBudgetConfig {
  capacity: number
  refillPerMinute: number
  safetyFactor?: number
}

export interface SubagentConfig {
  /** Hard ceiling on live child sessions. */
  max: number
  /** Reduce the ceiling from host load; defaults to false. */
  hostAware?: boolean
}

export interface RequestConcurrencyQueueOptions {
  maxConcurrency?: number
  providers?: string[] | Record<string, number>
  tokens?: Record<string, TokenBudgetConfig>
  scheduler?: SchedulerConfig
  subagents?: SubagentConfig
  adaptive?: boolean
  /** How long a disposed store stays adoptable by a reload, in milliseconds. */
  reloadGraceMs?: number
  log?: boolean
}

export interface RequestConcurrencyQueueFileConfig {
  maxConcurrency?: number
  providers?: string[] | Record<string, number>
  tokens?: Record<string, TokenBudgetConfig>
  scheduler?: SchedulerConfig
  subagents?: SubagentConfig
  adaptive?: boolean
  /** How long a disposed store stays adoptable by a reload, in milliseconds. */
  reloadGraceMs?: number
  log?: boolean
}

type RequestKind = "primary" | "compaction" | "title" | "generate"

interface Entry {
  readonly sessionID: string
  readonly providerID: string
  readonly kind: RequestKind
  readonly slot: Slot
  released: boolean
}

const DEFAULT_MAX_CONCURRENCY = 1

export default Plugin.define({
  id: "request-concurrency-queue",
  async setup(ctx) {
    const options = (ctx.options ?? {}) as RequestConcurrencyQueueOptions
    const fileConfig = loadConfigFile()
    const logEnabled = options.log ?? fileConfig?.log ?? envLog()
    const log = logEnabled
      ? (...args: unknown[]) => console.log("[request-concurrency-queue]", ...args)
      : () => {}

    // One limiter set per server process, shared by every location. The first
    // instance creates it; a later instance with a different configuration
    // keeps the existing set and logs the mismatch instead of reconfiguring
    // the process behind the other locations.
    const store = adoptStore(
      resolveProviderLimits(options, fileConfig),
      resolveTokenBudgets(options, fileConfig),
      resolveScheduler(options, fileConfig),
      resolveSubagents(options, fileConfig),
      options.adaptive ?? fileConfig?.adaptive ?? false,
      (existing, configured) => {
        log("config mismatch: keeping the process-wide store", { existing, configured })
      },
    )
    const limits = store.providers

    const registration = await ctx.rpc.register(statusRpc, {
      status: async () => snapshotOf(store),
      config: async () => configSnapshot(store, fileConfig),
      save: async (input) => saveConfig(store, input as ConfigSnapshot),
    })
    // A transition anywhere in the process must reach every location's event
    // stream, so each instance forwards the shared store's changes.
    const unsubscribeStore = subscribeStore(store, () => {
      void Promise.resolve(registration.events.emit("changed", {})).catch(() => {})
    })

    const bySession = new Map<string, Set<Entry>>()
    const byRequest = new WeakMap<Request, Entry>()
    // Total request-body bytes seen for each session's last request. The delta
    // between two requests is that turn's new context, which is what a
    // provider's token budget meters. Counting bytes while streaming the body
    // avoids buffering a multi-megabyte request just to size it.
    const bodyBytes = new Map<string, number>()

    log("initialized", {
      providers: Object.fromEntries([...limits].map(([providerID, limit]) => [providerID, limit.maxConcurrency])),
      tokens: Object.fromEntries([...limits].map(([providerID, limit]) => [providerID, limit.scheduler.budgetSnapshot?.capacity ?? 0])),
      adaptive: store.adaptive,
      subagents: store.subagents?.status(),
    })

    const addEntry = (
      sessionID: string,
      providerID: string,
      kind: RequestKind,
      slot: Slot,
      request: Request,
    ): Entry => {
      const entry: Entry = { sessionID, providerID, kind, slot, released: false }
      let entries = bySession.get(sessionID)
      if (!entries) {
        entries = new Set()
        bySession.set(sessionID, entries)
      }
      entries.add(entry)
      byRequest.set(request, entry)

      const limit = limits.get(providerID)
      log("acquired", {
        sessionID,
        providerID,
        active: limit?.scheduler.activeCount,
        queued: limit?.scheduler.queuedCount,
      })
      return entry
    }

    // A response error releases the failed attempt's own slot, and the runtime
    // reports the retry afterwards. Record that release per session and
    // provider so the retry spends it instead of freeing a newer entry that
    // belongs to a request still in flight.
    const retryCredits = new Map<string, Map<string, number>>()

    const recordRetryCredit = (sessionID: string, providerID: string): void => {
      let byProvider = retryCredits.get(sessionID)
      if (!byProvider) {
        byProvider = new Map()
        retryCredits.set(sessionID, byProvider)
      }
      byProvider.set(providerID, (byProvider.get(providerID) ?? 0) + 1)
    }

    const consumeRetryCredit = (sessionID: string, providerID: string): boolean => {
      const byProvider = retryCredits.get(sessionID)
      const count = byProvider?.get(providerID) ?? 0
      if (!byProvider || count === 0) return false
      if (count === 1) byProvider.delete(providerID)
      else byProvider.set(providerID, count - 1)
      if (byProvider.size === 0) retryCredits.delete(sessionID)
      return true
    }

    const releaseEntry = (entry: Entry, reason: string): void => {
      if (entry.released) return
      entry.released = true
      entry.slot.release()

      const entries = bySession.get(entry.sessionID)
      if (entries) {
        entries.delete(entry)
        if (entries.size === 0) bySession.delete(entry.sessionID)
      }

      if (entry.kind === "primary" && reason === "response-error") {
        recordRetryCredit(entry.sessionID, entry.providerID)
      }

      const limit = limits.get(entry.providerID)
      log("released", {
        sessionID: entry.sessionID,
        providerID: entry.providerID,
        reason,
        active: limit?.scheduler.activeCount,
        queued: limit?.scheduler.queuedCount,
      })
    }

    const releaseSession = (sessionID: string, reason: string): void => {
      // A child session going idle frees the fan-out permit it held.
      store.subagents?.releaseSession(sessionID)
      // Credits belong to a live session's in-flight retry, so they never
      // outlive the session that earned them.
      retryCredits.delete(sessionID)
      // The body cursor must survive a turn boundary. Deleting it on idle made
      // the next request charge its whole body as new tokens instead of the
      // delta, draining the budget every turn.
      if (reason === "session.deleted" || reason === "dispose") bodyBytes.delete(sessionID)
      // A waiting request is not in `bySession` until it holds a slot, so it
      // must be cancelled here or it is dispatched later for a session that
      // has already ended.
      for (const limit of limits.values()) limit.scheduler.cancelSession(sessionID)
      const entries = bySession.get(sessionID)
      if (!entries) return
      for (const entry of [...entries]) releaseEntry(entry, reason)
    }

    // A retry names only the session and provider, so it releases that
    // session's oldest unreleased primary entry: the attempt that failed. When
    // that attempt already released its slot on a response error, the retry
    // spends the recorded release and touches nothing. A newer request's slot,
    // including one queued behind it, stays held either way.
    /**
     * Releases the attempt a retry is replacing and reports whether that
     * attempt had actually been dispatched. A request that died while still
     * queued never reached the provider, so its failure must not be counted as
     * provider pressure.
     */
    const releaseRetried = (sessionID: string, providerID: string, reason: string): boolean => {
      if (consumeRetryCredit(sessionID, providerID)) return true
      const entries = bySession.get(sessionID)
      if (!entries) return false
      for (const entry of entries) {
        if (entry.released || entry.kind !== "primary" || entry.providerID !== providerID) continue
        releaseEntry(entry, reason)
        return true
      }
      return false
    }

    // Adaptive concurrency follows the provider's real capacity from outcomes:
    // a rate limit or a retry halves the effective maximum, and a run of clean
    // completions raises it one step at a time back to the configured ceiling.
    const recordFailure = (limit: ProviderLimit | undefined): void => {
      if (!store.adaptive || !limit) return
      limit.successes = 0
      const next = Math.max(1, Math.floor(limit.scheduler.maxConcurrency / 2))
      if (next < limit.scheduler.maxConcurrency) limit.scheduler.setMax(next)
    }

    const recordSuccess = (limit: ProviderLimit | undefined): void => {
      if (!store.adaptive || !limit) return
      limit.successes += 1
      if (limit.successes < RECOVERY_STREAK) return
      limit.successes = 0
      const next = limit.scheduler.maxConcurrency + 1
      if (next <= limit.maxConcurrency) limit.scheduler.setMax(next)
    }

    /**
     * Sizes one request on both admission dimensions without buffering its
     * body. The body is streamed through a clone while its bytes are counted;
     * the difference from the same session's previous request is this turn's
     * new context, and the total is what the request occupies in flight.
     */
    const estimateRequestCost = async (
      request: Request,
      sessionID: string,
      safetyFactor: number,
    ): Promise<{ newTokens: number; contextTokens: number }> => {
      let total = 0
      const declared = Number(request.headers.get("content-length"))
      if (Number.isFinite(declared) && declared > 0) total = declared
      try {
        if (total > 0) {
          const previous = bodyBytes.get(sessionID) ?? 0
          bodyBytes.set(sessionID, total)
          return {
            newTokens: estimateTokens(Math.max(0, total - previous), safetyFactor),
            contextTokens: estimateTokens(total, safetyFactor),
          }
        }
        const body = request.clone().body
        if (!body) return { newTokens: 0, contextTokens: 0 }
        const reader = body.getReader()
        try {
          for (;;) {
            const { done, value } = await reader.read()
            if (done) break
            total += value?.byteLength ?? 0
          }
        } finally {
          reader.releaseLock()
        }
      } catch (error) {
        log("token estimate skipped", error)
        return { newTokens: 0, contextTokens: 0 }
      }
      const previous = bodyBytes.get(sessionID) ?? 0
      bodyBytes.set(sessionID, total)
      return {
        newTokens: estimateTokens(Math.max(0, total - previous), safetyFactor),
        contextTokens: estimateTokens(total, safetyFactor),
      }
    }

    await ctx.session.hook("http.request", async (event) => {
      // Auxiliary requests (title, compaction, generate) acquire no provider
      // slot. The runtime reports no failure signal for one that dies before
      // its response headers, so a held slot would have no release path and
      // could stall the session's primary request.
      if (event.kind !== "primary") return
      const limit = limits.get(event.model.providerID)
      if (!limit) return

      // Cost first, admission second: the scheduler waits without holding a
      // slot, so a large request cannot park on a slot and starve small ones.
      // A store from an older build may hold a scheduler without this method;
      // estimating is always safe, so it is the fallback.
      const needsEstimate =
        typeof limit.scheduler.costEstimateRequired === "function"
          ? limit.scheduler.costEstimateRequired()
          : true
      const cost = needsEstimate
        ? await estimateRequestCost(
            event.request,
            event.sessionID,
            limit.scheduler.budgetSafetyFactor,
          )
        : { newTokens: 0, contextTokens: 0 }
      const slot = await limit.scheduler.acquire(event.sessionID, cost, event.request.signal)
      addEntry(event.sessionID, event.model.providerID, event.kind, slot, event.request)
    })

    /**
     * Distinguishes a slot shortage from a token-budget rejection. A
     * `burst_protection` 429 is answered by pausing the bucket; the other 429
     * codes mean the provider has no free concurrent slot. An unreadable body
     * is treated as capacity pressure, the conservative choice.
     */
    const isCapacityPressure = async (response: Response): Promise<boolean> => {
      try {
        const body = response.clone().body
        if (!body) return true
        const reader = body.getReader()
        const decoder = new TextDecoder()
        let text = ""
        try {
          while (text.length < 8_192) {
            const { done, value } = await reader.read()
            if (done) break
            text += decoder.decode(value, { stream: true })
          }
        } finally {
          await reader.cancel().catch(() => {})
        }
        // Too large to classify: treat it as capacity pressure, the safe side.
        if (text.length >= 8_192) return true
        const code = (JSON.parse(text) as { error?: { code?: string } })?.error?.code
        return code !== "burst_protection"
      } catch {
        return true
      }
    }

    await ctx.session.hook("http.response", async (event) => {
      // An auxiliary response must not fall through to the session's primary
      // entry while that primary body is still streaming.
      if (event.kind !== "primary") return
      const entry = byRequest.get(event.request) ?? firstEntry(bySession.get(event.sessionID))
      if (!entry) return

      const limit = limits.get(event.model.providerID)
      const response = event.response

      // Every 429 asks for a pause. Only a slot shortage asks for a narrower
      // width: a token-budget rejection is answered by the bucket, and halving
      // concurrency for it would throttle throughput the bucket already gates.
      if (response.status === 429) {
        const seconds = parseRetryAfter(response.headers.get("retry-after")) || 60
        limit?.scheduler.pauseBudget(seconds)
        if (await isCapacityPressure(response)) recordFailure(limit)
      }

      const body = response.body
      if (!body) {
        releaseEntry(entry, "response-without-body")
        return
      }

      const reader = body.getReader()
      let finished = false
      const finish = (reason: string) => {
        if (finished) return
        finished = true
        // Only a served request counts as recovery evidence; a 429 or 5xx
        // response that ends its body is still a failure.
        if (reason === "response-end" && response.status >= 200 && response.status < 300) {
          recordSuccess(limit)
          limit?.scheduler.recordSuccess()
        }
        releaseEntry(entry, reason)
      }

      const stream = new ReadableStream<Uint8Array>({
        async pull(controller) {
          try {
            const result = await reader.read()
            if (result.done) {
              finish("response-end")
              controller.close()
              return
            }
            controller.enqueue(result.value)
          } catch (error) {
            finish("response-error")
            controller.error(error)
          }
        },
        async cancel(reason) {
          finish("response-cancel")
          await reader.cancel(reason)
        },
      })

      event.response = new Response(stream, {
        status: response.status,
        statusText: response.statusText,
        headers: response.headers,
      })
    })

    await ctx.session.hook("retry", async (event) => {
      const dispatched = releaseRetried(event.sessionID, event.model.providerID, "retry")
      // Only a capacity signal narrows the width. A 429 is classified by the
      // response hook, which also carries Retry-After; an invalid request, a
      // context-size rejection, or a plan/quota error is not concurrency
      // pressure and must not cost a step.
      const error = event.error ?? {}
      // A rejection produced by this plugin is not a provider stall. Counting
      // it would reopen the breaker on its own output and keep it open forever.
      const message = typeof error.message === "string" ? error.message : ""
      if (/^(request-concurrency-queue:|request cancelled:|subagent launch cancelled:)/.test(message)) {
        return
      }
      if (error.status === 429) return
      // A request that never got a slot was killed by the client's own timeout
      // while queued. That is this plugin's queue, not a provider stall.
      if (!dispatched) return
      const capacity = error.type === "provider.transport" || (error.status ?? 0) >= 500
      if (!capacity) return
      const limit = limits.get(event.model.providerID)
      recordFailure(limit)
      // An attempt that produced no response is a provider stall: it counts
      // toward the circuit breaker and shrinks the in-flight context cap.
      limit?.scheduler.recordStall()
    })

    // The subagent tool returns as soon as a child is launched, so a permit is
    // bound to the returned session ID and released when that child goes idle.
    // Registered unconditionally: the gate can be enabled or disabled from the
    // Config tab, so the wrapper must read it per call rather than capture it.
    await ctx.tool.transform((editor) => {
      const tool = editor.get("subagent")
      if (!tool) {
        log("subagent tool not found; fan-out gate inactive")
        return
      }
      const original = tool.execute
      editor.update("subagent", (draft) => {
        draft.execute = async (input: unknown, context: any) => {
          const gate = store.subagents
          if (!gate) return original(input, context)
          const permit = await gate.acquire(context?.sessionID ?? "unknown", context?.signal)
          try {
            const result = await original(input, context)
            const child = extractSessionID(result)
            if (child) permit.bind(child)
            else permit.release()
            return result
          } catch (error) {
            permit.release()
            throw error
          }
        }
      })
    })

    await ctx.session.hook("experimental.idle", async (event) => {
      releaseSession(event.sessionID, "idle")
    })

    const controller = new AbortController()
    const types = [
      "session.idle",
      "session.deleted",
      "session.execution.failed",
      "session.execution.interrupted",
    ] as const
    const subscription = ctx.event.subscribe({ types, signal: controller.signal })

    const eventLoop = (async () => {
      try {
        for await (const event of subscription) {
          releaseSession(event.data.sessionID, event.type)
        }
      } catch (error) {
        if (!controller.signal.aborted) log("event subscription failed", error)
      }
    })()

    return async () => {
      controller.abort()
      // Running entries release their slots, but admission stops first so a
      // freed slot cannot be handed to a waiter this instance can no longer
      // gate. Queued waiters are left for `releaseStore`'s grace period: a
      // reload adopts this store a moment later and serves them, so a deploy
      // no longer cancels a live sweep.
      // Only the last instance drains: while another location still holds the
      // store, its freed slots must keep being handed out.
      if (store.refcount <= 1) {
        for (const limit of limits.values()) limit.scheduler.beginDrain()
        store.subagents?.beginDrain()
      }
      for (const sessionID of [...bySession.keys()]) releaseSession(sessionID, "dispose")
      await eventLoop.catch(() => {})
      unsubscribeStore()
      await registration.dispose()
      releaseStore(store, options.reloadGraceMs ?? fileConfig?.reloadGraceMs ?? 5_000)
    }
  },
})

/** The effective settings, with defaults filled in for anything unset. */
export function configSnapshot(
  store: Store,
  fileConfig?: RequestConcurrencyQueueFileConfig,
): ConfigSnapshot {
  const scheduler = fileConfig?.scheduler
  const providers: Record<string, number> = {}
  for (const [providerID, limit] of store.providers) providers[providerID] = limit.maxConcurrency

  const tokens: Record<string, { capacity: number; refillPerMinute: number; safetyFactor: number }> = {}
  for (const [providerID, budget] of Object.entries(fileConfig?.tokens ?? {})) {
    tokens[providerID] = {
      capacity: budget.capacity,
      refillPerMinute: budget.refillPerMinute,
      safetyFactor: budget.safetyFactor ?? 1,
    }
  }

  return {
    providers,
    tokens,
    scheduler: {
      contextCapacity: scheduler?.contextCapacity ?? 0,
      contextCeiling: scheduler?.contextCeiling ?? scheduler?.contextCapacity ?? 0,
      reserveShare: scheduler?.reserveShare ?? 0.25,
      smallShare: scheduler?.smallShare ?? 0.1,
      agingMs: scheduler?.agingMs ?? 30_000,
      queueDeadlineMs: scheduler?.queueDeadlineMs ?? 0,
      breaker: {
        threshold: scheduler?.breaker?.threshold ?? 2,
        cooldownMs: scheduler?.breaker?.cooldownMs ?? 60_000,
        mode: scheduler?.breaker?.mode ?? "fail",
      },
    },
    subagents: {
      max: store.subagents?.status().max ?? 0,
      hostAware: fileConfig?.subagents?.hostAware ?? false,
    },
    adaptive: fileConfig?.adaptive ?? false,
  }
}

/**
 * Validates an edited configuration, writes it to the config file, and applies
 * it to the running store. Nothing is written unless every check passes.
 */
export function saveConfig(
  store: Store,
  input: ConfigSnapshot,
  filePath = configFilePath(),
): SaveResult {
  const errors: string[] = []

  for (const [providerID, max] of Object.entries(input.providers)) {
    if (!Number.isInteger(max) || max < 1) {
      errors.push(`providers.${providerID} must be a positive integer`)
    }
  }
  for (const [providerID, budget] of Object.entries(input.tokens)) {
    if (!Number.isInteger(budget.capacity) || budget.capacity < 1) {
      errors.push(`tokens.${providerID}.capacity must be a positive integer`)
    }
    if (!Number.isInteger(budget.refillPerMinute) || budget.refillPerMinute < 1) {
      errors.push(`tokens.${providerID}.refillPerMinute must be a positive integer`)
    }
    if (!Number.isFinite(budget.safetyFactor) || budget.safetyFactor <= 0) {
      errors.push(`tokens.${providerID}.safetyFactor must be positive`)
    }
  }
  const scheduler = input.scheduler
  if (!Number.isInteger(scheduler.contextCapacity) || scheduler.contextCapacity < 0) {
    errors.push("scheduler.contextCapacity must be a non-negative integer")
  }
  if (!Number.isInteger(scheduler.contextCeiling) || scheduler.contextCeiling < 0) {
    errors.push("scheduler.contextCeiling must be a non-negative integer")
  }
  if (
    scheduler.contextCeiling > 0 &&
    scheduler.contextCapacity > 0 &&
    scheduler.contextCeiling < scheduler.contextCapacity
  ) {
    errors.push("scheduler.contextCeiling must be at least contextCapacity, or 0 for no growth")
  }
  for (const key of ["reserveShare", "smallShare"] as const) {
    const value = scheduler[key]
    if (!Number.isFinite(value) || value < 0 || value > 1) {
      errors.push(`scheduler.${key} must be between 0 and 1`)
    }
  }
  for (const key of ["agingMs", "queueDeadlineMs"] as const) {
    if (!Number.isInteger(scheduler[key]) || scheduler[key] < 0) {
      errors.push(`scheduler.${key} must be a non-negative integer`)
    }
  }
  if (!Number.isInteger(scheduler.breaker.threshold) || scheduler.breaker.threshold < 1) {
    errors.push("scheduler.breaker.threshold must be a positive integer")
  }
  if (!Number.isInteger(scheduler.breaker.cooldownMs) || scheduler.breaker.cooldownMs < 0) {
    errors.push("scheduler.breaker.cooldownMs must be a non-negative integer")
  }
  if (scheduler.breaker.mode !== "fail" && scheduler.breaker.mode !== "wait") {
    errors.push('scheduler.breaker.mode must be "fail" or "wait"')
  }
  if (!Number.isInteger(input.subagents.max) || input.subagents.max < 0) {
    errors.push("subagents.max must be a non-negative integer")
  }
  if (errors.length > 0) return { ok: false, errors, restartRequired: false }

  const tokens: Record<string, TokenBudgetConfig> = {}
  for (const [providerID, budget] of Object.entries(input.tokens)) {
    tokens[providerID] = {
      capacity: budget.capacity,
      refillPerMinute: budget.refillPerMinute,
      safetyFactor: budget.safetyFactor,
    }
  }

  const next: Record<string, unknown> = {
    ...(loadConfigFile(filePath) as Record<string, unknown> | undefined),
    providers: input.providers,
    tokens,
    scheduler: {
      contextCapacity: scheduler.contextCapacity,
      contextCeiling: scheduler.contextCeiling,
      reserveShare: scheduler.reserveShare,
      smallShare: scheduler.smallShare,
      agingMs: scheduler.agingMs,
      queueDeadlineMs: scheduler.queueDeadlineMs,
      breaker: scheduler.breaker,
    },
    adaptive: input.adaptive,
  }
  if (input.subagents.max > 0) next.subagents = input.subagents
  else delete next.subagents

  // Apply first: a failure must not leave the file describing a state the
  // running server never reached.
  let applied: { restartRequired: boolean }
  try {
    applied = applyConfig(store, {
      providers: new Map(Object.entries(input.providers)),
      tokens: new Map(Object.entries(tokens)),
      scheduler: {
        contextCapacity: scheduler.contextCapacity,
        contextCeiling: scheduler.contextCeiling,
        reserveShare: scheduler.reserveShare,
        smallShare: scheduler.smallShare,
        agingMs: scheduler.agingMs,
        queueDeadlineMs: scheduler.queueDeadlineMs,
        breaker: scheduler.breaker,
      },
      subagents:
        input.subagents.max > 0
          ? { max: input.subagents.max, hostAware: input.subagents.hostAware }
          : undefined,
      adaptive: input.adaptive,
    })
  } catch (error) {
    return {
      ok: false,
      errors: [`Could not apply the settings: ${error instanceof Error ? error.message : String(error)}`],
      restartRequired: false,
    }
  }

  const temporary = `${filePath}.tmp`
  writeFileSync(temporary, `${JSON.stringify(next, null, 2)}\n`)
  renameSync(temporary, filePath)

  return { ok: true, errors: [], restartRequired: applied.restartRequired }
}

export function configFilePath(): string {
  const explicit = process.env.OPENCODE_REQUEST_CONCURRENCY_CONFIG
  if (explicit) return explicit.startsWith("~") ? join(homedir(), explicit.slice(1)) : explicit
  return join(homedir(), ".config", "opencode", "request-concurrency-queue.json")
}

export function loadConfigFile(filePath = configFilePath()): RequestConcurrencyQueueFileConfig | undefined {
  if (!existsSync(filePath)) return undefined
  try {
    const parsed = JSON.parse(readFileSync(filePath, "utf8")) as unknown
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("config must be a JSON object")
    }
    return parsed as RequestConcurrencyQueueFileConfig
  } catch (error) {
    throw new Error(`Failed to read ${filePath}: ${error instanceof Error ? error.message : String(error)}`)
  }
}

export function resolveSubagents(
  options: RequestConcurrencyQueueOptions,
  fileConfig?: RequestConcurrencyQueueFileConfig,
): SubagentGateOptions | undefined {
  const configured = options.subagents ?? fileConfig?.subagents
  if (!configured) return undefined
  if (typeof configured !== "object" || Array.isArray(configured)) {
    throw new Error("subagents must be an object")
  }
  if (!Number.isInteger(configured.max) || configured.max < 1) {
    throw new Error(`subagents.max must be a positive integer, got ${String(configured.max)}`)
  }
  return { max: configured.max, hostAware: configured.hostAware ?? false }
}

export function resolveScheduler(
  options: RequestConcurrencyQueueOptions,
  fileConfig?: RequestConcurrencyQueueFileConfig,
): SchedulerConfig | undefined {
  const configured = options.scheduler ?? fileConfig?.scheduler
  if (!configured) return undefined
  if (!Number.isInteger(configured.contextCapacity) || configured.contextCapacity < 0) {
    throw new Error(
      `scheduler.contextCapacity must be a non-negative integer, got ${String(configured.contextCapacity)}`,
    )
  }
  const deadline = configured.queueDeadlineMs
  if (deadline !== undefined && (!Number.isInteger(deadline) || deadline < 0)) {
    throw new Error(
      `scheduler.queueDeadlineMs must be a non-negative integer, got ${String(deadline)}`,
    )
  }
  const breaker = configured.breaker
  if (breaker) {
    if (breaker.threshold !== undefined && (!Number.isInteger(breaker.threshold) || breaker.threshold < 1)) {
      throw new Error(`scheduler.breaker.threshold must be a positive integer, got ${String(breaker.threshold)}`)
    }
    if (breaker.cooldownMs !== undefined && (!Number.isInteger(breaker.cooldownMs) || breaker.cooldownMs < 0)) {
      throw new Error(`scheduler.breaker.cooldownMs must be a non-negative integer, got ${String(breaker.cooldownMs)}`)
    }
    if (breaker.mode !== undefined && breaker.mode !== "fail" && breaker.mode !== "wait") {
      throw new Error(`scheduler.breaker.mode must be "fail" or "wait", got ${String(breaker.mode)}`)
    }
  }
  return {
    contextCapacity: configured.contextCapacity,
    contextCeiling: configured.contextCeiling,
    reserveShare: configured.reserveShare,
    smallShare: configured.smallShare,
    agingMs: configured.agingMs,
    queueDeadlineMs: deadline,
    breaker,
  }
}

export function resolveTokenBudgets(
  options: RequestConcurrencyQueueOptions,
  fileConfig?: RequestConcurrencyQueueFileConfig,
): Map<string, TokenBudgetOptions> {
  const configured = options.tokens ?? fileConfig?.tokens
  const budgets = new Map<string, TokenBudgetOptions>()
  if (!configured) return budgets

  for (const [providerID, budget] of Object.entries(configured)) {
    if (!providerID) continue
    if (!budget || typeof budget !== "object") {
      throw new Error(`tokens for provider "${providerID}" must be an object`)
    }
    budgets.set(providerID, {
      capacity: budget.capacity,
      refillPerMinute: budget.refillPerMinute,
      safetyFactor: budget.safetyFactor,
    })
  }
  return budgets
}

export function resolveProviderLimits(
  options: RequestConcurrencyQueueOptions,
  fileConfig?: RequestConcurrencyQueueFileConfig,
): Map<string, number> {
  const defaultMax = options.maxConcurrency ?? fileConfig?.maxConcurrency ?? envMaxConcurrency() ?? DEFAULT_MAX_CONCURRENCY
  const configured = options.providers ?? fileConfig?.providers ?? envProviders()
  const limits = new Map<string, number>()

  if (!configured) return limits

  if (Array.isArray(configured)) {
    for (const providerID of configured) {
      if (typeof providerID === "string" && providerID.length > 0) limits.set(providerID, defaultMax)
    }
  } else if (typeof configured === "object") {
    for (const [providerID, max] of Object.entries(configured)) {
      if (!providerID) continue
      if (typeof max !== "number") {
        throw new Error(`maxConcurrency for provider "${providerID}" must be a number`)
      }
      limits.set(providerID, max)
    }
  }

  for (const [providerID, max] of limits) {
    if (!Number.isInteger(max) || max < 1) {
      throw new Error(`maxConcurrency for provider "${providerID}" must be a positive integer, got ${String(max)}`)
    }
  }

  return limits
}

export function envProviders(): string[] | Record<string, number> | undefined {
  const raw = process.env.OPENCODE_REQUEST_CONCURRENCY_PROVIDERS
  if (!raw) return undefined

  const value = raw.trim()
  if (value.startsWith("{")) {
    const parsed = JSON.parse(value) as unknown
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      const result: Record<string, number> = {}
      for (const [providerID, entry] of Object.entries(parsed as Record<string, unknown>)) {
        const max = typeof entry === "number" ? entry : Number(entry)
        if (!providerID || !Number.isInteger(max) || max < 1) {
          throw new Error(`maxConcurrency for provider "${providerID}" must be a positive integer`)
        }
        result[providerID] = max
      }
      return result
    }
  }

  const defaultMax = envMaxConcurrency() ?? DEFAULT_MAX_CONCURRENCY
  const result: Record<string, number> = {}
  for (const entry of value.split(",").map((item) => item.trim()).filter(Boolean)) {
    const [providerID, rawMax] = entry.split("=")
    if (!providerID) continue
    if (rawMax === undefined) {
      result[providerID] = defaultMax
      continue
    }
    const max = Number(rawMax)
    if (!Number.isInteger(max) || max < 1) {
      throw new Error(`maxConcurrency for provider "${providerID}" must be a positive integer`)
    }
    result[providerID] = max
  }
  return result
}

function firstEntry(entries: Set<Entry> | undefined): Entry | undefined {
  if (!entries) return undefined
  for (const entry of entries) {
    if (!entry.released) return entry
  }
  return undefined
}

function envMaxConcurrency(): number | undefined {
  const raw = process.env.OPENCODE_REQUEST_CONCURRENCY_MAX
  if (!raw) return undefined
  const value = Number(raw)
  return Number.isInteger(value) && value > 0 ? value : undefined
}

function envLog(): boolean {
  return process.env.OPENCODE_REQUEST_CONCURRENCY_LOG === "1"
}
