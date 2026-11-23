import { Plugin } from "@opencode/plugin"
import { existsSync, readFileSync, renameSync, unlinkSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"
import { estimateTokens, parseRetryAfter, type TokenBudgetOptions } from "./budget.js"
import { statusRpc, type ConfigSnapshot, type SaveResult } from "./rpc.js"
import type { RequestCost, SchedulerSlot } from "./scheduler.js"
import { createSessionDescriber } from "./sessions.js"
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

/**
 * A request body above this size is scanned for image payloads before it is
 * charged. Below it, the declared byte length is a close enough estimate and
 * the scan cost would be wasted.
 */
const IMAGE_SCAN_BYTES = 256_000

/**
 * What one image costs on the token dimensions. The provider bills an image by
 * its rendered size, not by the base64 bytes on the wire, so a fixed charge
 * replaces a byte count that would overstate it by orders of magnitude.
 */
const IMAGE_TOKENS = 1_200

/** The bytes and images one request body carries. */
interface BodyMeasure {
  readonly textBytes: number
  readonly images: number
}

/** A measured request and the cursor update that belongs with its admission. */
interface CostEstimate {
  readonly cost: RequestCost
  /** Records this body as the session's new baseline. Call once admitted. */
  commit(): void
}

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
  readonly slot: SchedulerSlot
  released: boolean
}

/**
 * One recorded attempt a retry may replace. The retry event carries no request
 * kind, so the plugin records every attempt per session and provider in the
 * order it was admitted and consumes the newest one here.
 *
 * An auxiliary attempt is recorded beside the primary rather than over it. The
 * primary's record therefore survives until a retry finds it newest or the
 * session ends, and a background compaction retry cannot release the slot of
 * the primary request that is still streaming.
 */
interface Attempt {
  readonly kind: RequestKind
  /** The primary entry, when this attempt held a slot. */
  readonly entry?: Entry
  /** Monotonic record order, so a retry consumes the newest attempt. */
  readonly seq: number
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

    // The settings form must see the file as it is now, not as it was when the
    // plugin loaded: a save rewrites it, and a stale snapshot would show the
    // old values and write them back on the next save.
    const currentFileConfig = (): RequestConcurrencyQueueFileConfig | undefined => {
      try {
        return loadConfigFile()
      } catch (error) {
        log("config re-read failed; using the load-time snapshot", error)
        return fileConfig
      }
    }

    // The dialog names the sessions holding a slot, which the store cannot: a
    // title and a project directory live in the runtime, not in the limiter.
    const describeSessions = createSessionDescriber(
      async (sessionID) =>
        ctx.session.get({ sessionID: sessionID as Parameters<typeof ctx.session.get>[0]["sessionID"] }),
      { onError: (sessionID, error) => log("session detail lookup failed", { sessionID }, error) },
    )

    const registration = await ctx.rpc.register(statusRpc, {
      status: async () => describeSessions(snapshotOf(store)),
      config: async () => configSnapshot(store, currentFileConfig()),
      save: async (input) => saveConfig(store, input as ConfigSnapshot),
    })
    // A transition anywhere in the process must reach every location's event
    // stream, so each instance forwards the shared store's changes.
    const unsubscribeStore = subscribeStore(store, () => {
      void Promise.resolve(registration.events.emit("changed", {})).catch(() => {})
    })

    const bySession = new Map<string, Set<Entry>>()
    const byRequest = new WeakMap<Request, Entry>()
    // The body each session's last admitted request carried. The delta between
    // two requests is that turn's new context, which is what a provider's token
    // budget meters. Counting bytes while streaming the body avoids buffering a
    // multi-megabyte request just to size it.
    const bodyMeasure = new Map<string, BodyMeasure>()
    // Every attempt recorded per session and provider, oldest first, consumed
    // newest-first by the retry hook.
    const attempts = new Map<string, Map<string, Attempt[]>>()
    // The auxiliary attempt each request recorded, so a completed 2xx response
    // prunes its own record instead of another in-flight auxiliary's.
    const auxAttemptByRequest = new WeakMap<Request, Attempt>()
    let attemptSeq = 0

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
      slot: SchedulerSlot,
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

    /**
     * Records an attempt a retry may later replace. A primary attempt is
     * appended beside any auxiliary record already waiting, never over it.
     */
    const recordAttempt = (
      sessionID: string,
      providerID: string,
      attempt: Omit<Attempt, "seq">,
      request?: Request,
    ): Attempt => {
      let byProvider = attempts.get(sessionID)
      if (!byProvider) {
        byProvider = new Map()
        attempts.set(sessionID, byProvider)
      }
      let records = byProvider.get(providerID)
      if (!records) {
        records = []
        byProvider.set(providerID, records)
      }
      const recorded: Attempt = { ...attempt, seq: ++attemptSeq }
      records.push(recorded)
      if (request) auxAttemptByRequest.set(request, recorded)
      return recorded
    }

    /** Removes one recorded attempt, keeping the per-provider structure clean. */
    const dropAttempt = (sessionID: string, providerID: string, attempt: Attempt): void => {
      const byProvider = attempts.get(sessionID)
      const records = byProvider?.get(providerID)
      if (!byProvider || !records) return
      const index = records.indexOf(attempt)
      if (index < 0) return
      records.splice(index, 1)
      if (records.length === 0) byProvider.delete(providerID)
      if (byProvider.size === 0) attempts.delete(sessionID)
    }

    /**
     * Consumes the newest recorded attempt, so one retry consumes one attempt
     * and a shadowed primary record is left for the retry that finds it newest.
     */
    const takeAttempt = (sessionID: string, providerID: string): Attempt | undefined => {
      const byProvider = attempts.get(sessionID)
      const records = byProvider?.get(providerID)
      if (!byProvider || !records || records.length === 0) return undefined
      let newest = 0
      for (let index = 1; index < records.length; index += 1) {
        if (records[index].seq > records[newest].seq) newest = index
      }
      const [attempt] = records.splice(newest, 1)
      if (records.length === 0) byProvider.delete(providerID)
      if (byProvider.size === 0) attempts.delete(sessionID)
      return attempt
    }

    /** Drops the record that carries a released primary entry. */
    const dropEntryAttempt = (entry: Entry): void => {
      const records = attempts.get(entry.sessionID)?.get(entry.providerID)
      if (!records) return
      const attempt = records.find((record) => record.entry === entry)
      if (attempt) dropAttempt(entry.sessionID, entry.providerID, attempt)
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
      // A completed primary request cannot be retried, so its record is spent.
      dropEntryAttempt(entry)

      const limit = limits.get(entry.providerID)
      log("released", {
        sessionID: entry.sessionID,
        providerID: entry.providerID,
        reason,
        active: limit?.scheduler.activeCount,
        queued: limit?.scheduler.queuedCount,
      })
    }

    const releaseSession = (
      sessionID: string,
      reason: string,
      options: { permits?: boolean } = {},
    ): void => {
      // A child session going idle frees the fan-out permit it held. A disposing
      // instance skips this: the children keep running, and the instance that
      // adopts the store releases each permit when its own idle event arrives.
      if (options.permits !== false) store.subagents?.releaseSession(sessionID)
      // An attempt belongs to a live session's in-flight retry, so it never
      // outlives the session that recorded it.
      attempts.delete(sessionID)
      // The body cursor must survive a turn boundary. Deleting it on idle made
      // the next request charge its whole body as new tokens instead of the
      // delta, draining the budget every turn.
      if (reason === "session.deleted" || reason === "dispose") bodyMeasure.delete(sessionID)
      // A waiting request is not in `bySession` until it holds a slot, so it
      // must be cancelled here or it is dispatched later for a session that
      // has already ended.
      for (const limit of limits.values()) limit.scheduler.cancelSession(sessionID)
      const entries = bySession.get(sessionID)
      if (!entries) return
      for (const entry of [...entries]) releaseEntry(entry, reason)
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
     * Sizes one request on both admission dimensions without buffering a small
     * body. The difference from the same session's previous admitted request is
     * this turn's new context, and the total is what the request occupies in
     * flight.
     *
     * A large body is scanned for embedded image payloads first. Base64 image
     * bytes are not text tokens: charging them at the text rate made one
     * screenshot look like hundreds of thousands of new tokens and could
     * exhaust the whole budget or context cap on its own. Images are charged a
     * fixed amount instead, and only the text bytes feed the text estimate.
     *
     * An auxiliary request is charged its whole prompt (`fresh`): compaction
     * rewrites the transcript into a new prompt that no longer shares the
     * primary request's cached prefix, so its size is genuinely new context.
     * The cursor is not moved for it, so the next primary request's delta still
     * measures against the conversation it continues.
     *
     * The cursor moves only when the request is admitted, so a request that
     * dies in the queue cannot make the next turn look smaller than it is.
     */
    const estimateRequestCost = async (
      request: Request,
      sessionID: string,
      safetyFactor: number,
      fresh = false,
    ): Promise<CostEstimate> => {
      const measured = await measureBody(request, log)
      const previous = fresh ? { textBytes: 0, images: 0 } : (bodyMeasure.get(sessionID) ?? { textBytes: 0, images: 0 })
      const newText = Math.max(0, measured.textBytes - previous.textBytes)
      const newImages = Math.max(0, measured.images - previous.images)
      return {
        cost: {
          newTokens:
            estimateTokens(newText, safetyFactor) + newImages * IMAGE_TOKENS,
          contextTokens:
            estimateTokens(measured.textBytes, safetyFactor) + measured.images * IMAGE_TOKENS,
        },
        commit: () => {
          if (!fresh) bodyMeasure.set(sessionID, measured)
        },
      }
    }

    await ctx.session.hook("http.request", async (event) => {
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
      const estimate: CostEstimate | undefined = needsEstimate
        ? await estimateRequestCost(
            event.request,
            event.sessionID,
            limit.scheduler.budgetSafetyFactor,
            event.kind !== "primary",
          )
        : undefined
      const cost = estimate?.cost ?? { newTokens: 0, contextTokens: 0 }

      if (event.kind !== "primary") {
        // Auxiliary requests (title, compaction, generate) take no slot: the
        // runtime gives no per-request failure signal for one that dies before
        // its response headers, so a held slot would have no release path. They
        // are still charged to the provider's new-token budget, because a
        // compaction resends the whole transcript and is the largest burst the
        // provider meters.
        await limit.scheduler.acquireBudget(event.sessionID, cost, event.request.signal)
        estimate?.commit()
        recordAttempt(event.sessionID, event.model.providerID, { kind: event.kind }, event.request)
        return
      }

      const slot = await limit.scheduler.acquire(event.sessionID, cost, event.request.signal)
      estimate?.commit()
      const entry = addEntry(event.sessionID, event.model.providerID, event.kind, slot, event.request)
      recordAttempt(event.sessionID, event.model.providerID, { kind: "primary", entry })
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
      const limit = limits.get(event.model.providerID)
      const response = event.response

      // A 429 is answered for every kind of request: an auxiliary compaction
      // can exhaust the provider's burst allowance just as a primary request
      // can, and ignoring it left the whole provider unpaused.
      if (response.status === 429) {
        if (await isCapacityPressure(response)) {
          // The provider has no free concurrent slot. A narrower width is the
          // right answer; the token bucket is not what ran out.
          recordFailure(limit)
        } else {
          // `burst_protection`: the new-token allowance is spent. Wait as long
          // as the provider asks, and only that long. A missing header is a
          // one-second wait, never a minute: the provider itself asks for about
          // a second, and a minute-long pause would freeze every request while
          // a full bucket sits unused.
          const seconds = parseRetryAfter(response.headers.get("retry-after"))
          limit?.scheduler.pauseBudget(seconds > 0 ? seconds : 1)
        }
      }

      // A 5xx is a provider stall whether or not its body is drained by the
      // caller, so it is counted here instead of on the retry path, which only
      // sees it when the body was left unread.
      if (response.status >= 500) {
        recordFailure(limit)
        limit?.scheduler.recordStall()
      }

      // An auxiliary response must not fall through to the session's primary
      // entry while that primary body is still streaming. A 2xx completion
      // spends the auxiliary's own record once its body has actually finished,
      // mirroring the primary `finish` path, because a retry follows a 2xx
      // whose body fails mid-stream. An error status, a failed body, or a
      // cancelled body keeps the record: the retry that follows the failed
      // auxiliary request must consume its own record, not the primary's.
      if (event.kind !== "primary") {
        if (response.status >= 200 && response.status < 300) {
          const recorded = auxAttemptByRequest.get(event.request)
          if (recorded) {
            const auxBody = response.body
            if (!auxBody) {
              dropAttempt(event.sessionID, event.model.providerID, recorded)
            } else {
              const auxReader = auxBody.getReader()
              let auxFinished = false
              const finishAux = (reason: string) => {
                if (auxFinished) return
                auxFinished = true
                if (reason === "response-end") {
                  dropAttempt(event.sessionID, event.model.providerID, recorded)
                }
              }
              const auxStream = new ReadableStream<Uint8Array>({
                async pull(controller) {
                  try {
                    const result = await auxReader.read()
                    if (result.done) {
                      finishAux("response-end")
                      controller.close()
                      return
                    }
                    controller.enqueue(result.value)
                  } catch (error) {
                    finishAux("response-error")
                    controller.error(error)
                  }
                },
                async cancel(reason) {
                  finishAux("response-cancel")
                  await auxReader.cancel(reason)
                },
              })
              event.response = new Response(auxStream, {
                status: response.status,
                statusText: response.statusText,
                headers: response.headers,
              })
            }
          }
        }
        return
      }
      const entry = byRequest.get(event.request) ?? soleEntry(bySession.get(event.sessionID))
      if (!entry) return

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
      // The retry event names only the session and provider. The newest
      // recorded attempt says whether it was a primary request (whose slot
      // must be released) or an auxiliary one (which holds no slot), so a
      // background compaction retry can never free a primary request that is
      // still streaming. A primary shadowed by a newer auxiliary record stays
      // recorded for the retry that later finds it newest, or for idle.
      const attempt = takeAttempt(event.sessionID, event.model.providerID)
      const entry = attempt?.kind === "primary" ? attempt.entry : undefined
      if (entry && !entry.released) releaseEntry(entry, "retry")
      const dispatched = attempt !== undefined

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
      // A 5xx already produced a response and was counted by the response hook,
      // so only a transport failure that produced no response counts here.
      if (error.type !== "provider.transport") return
      const limit = limits.get(event.model.providerID)
      recordFailure(limit)
      // An attempt that produced no response is a provider stall: it counts
      // toward the circuit breaker and may shrink the in-flight context cap.
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
      // gate. A queued waiter is cancelled with its session: its promise lives
      // in this instance's hook frame, so handing it to the next instance would
      // dispatch a request whose response nobody here can observe.
      // Only the last instance drains: while another location still holds the
      // store, its freed slots must keep being handed out.
      if (store.refcount <= 1) {
        for (const limit of limits.values()) limit.scheduler.beginDrain()
        store.subagents?.beginDrain()
      }
      // Live child sessions keep their permits: they are still running, and the
      // instance that adopts the store releases each one when its own idle
      // event arrives. Releasing them here would let a reload admit a full new
      // fan-out on top of the children it just forgot.
      for (const sessionID of [...bySession.keys()]) {
        releaseSession(sessionID, "dispose", { permits: false })
      }
      await eventLoop.catch(() => {})
      unsubscribeStore()
      await registration.dispose()
      releaseStore(store, options.reloadGraceMs ?? fileConfig?.reloadGraceMs ?? 5_000)
    }
  },
})

/**
 * The effective settings, with defaults filled in for anything unset.
 *
 * Every live limit is read from the store, whichever source configured it:
 * plugin options, the environment, or the config file. `fileConfig` stays in the
 * signature for the provider-set work that reads it; the token, scheduler, and
 * `hostAware` reads come from the store.
 */
export function configSnapshot(
  store: Store,
  fileConfig?: RequestConcurrencyQueueFileConfig,
): ConfigSnapshot {
  const providers: Record<string, number> = {}
  for (const [providerID, limit] of store.providers) providers[providerID] = limit.maxConcurrency

  // A provider the store gates without a budget reports no entry, so the form
  // shows no fabricated default and an unchanged save leaves the file alone.
  const tokens: Record<string, { capacity: number; refillPerMinute: number; safetyFactor: number }> = {}
  for (const [providerID, limit] of store.providers) {
    const budget = limit.scheduler.budgetConfig
    if (!budget) continue
    tokens[providerID] = {
      capacity: budget.capacity,
      refillPerMinute: budget.refillPerMinute,
      safetyFactor: budget.safetyFactor,
    }
  }

  // Every provider starts from the one configured scheduler, and `applyConfig`
  // writes one scheduler configuration back to all of them, so the first
  // provider's live values speak for the process. A cap that adaptive control
  // lowered is reported as it stands.
  const [firstProvider] = store.providers.values()
  const liveScheduler = firstProvider?.scheduler
  const scheduler = liveScheduler
    ? {
        contextCapacity: liveScheduler.status().contextCapacity,
        contextCeiling: liveScheduler.contextCeiling,
        reserveShare: liveScheduler.reserveShare,
        smallShare: liveScheduler.smallShare,
        agingMs: liveScheduler.agingMs,
        queueDeadlineMs: liveScheduler.queueDeadlineMs,
        breaker: liveScheduler.breakerConfig,
      }
    : {
        contextCapacity: 0,
        contextCeiling: 0,
        reserveShare: 0.25,
        smallShare: 0.1,
        agingMs: 30_000,
        queueDeadlineMs: 0,
        breaker: { threshold: 3, cooldownMs: 60_000, mode: "fail" as const },
      }

  return {
    providers,
    tokens,
    scheduler,
    subagents: {
      max: store.subagents?.status().max ?? 0,
      // The gate's live value, not the file's: an options-configured gate has no
      // file entry, and a saved change must read back as what the gate uses.
      hostAware: store.subagents?.hostAware ?? false,
    },
    // The running store is the source of truth for adaptive control: a save
    // applies it there, and the file is only the persistence of that value.
    adaptive: store.adaptive,
  }
}

/** The file operations a save uses, injected so a test can force each failure. */
export interface SaveIo {
  /** Reads the current config file as text; throws when it is absent or unreadable. */
  readFile: (path: string) => string
  /** Moves the temporary file over the config file. */
  rename: (from: string, to: string) => void
}

const defaultSaveIo: SaveIo = {
  readFile: (path) => readFileSync(path, "utf8"),
  rename: renameSync,
}

/**
 * Validates an edited configuration, writes it to the config file, and applies
 * it to the running store. Nothing is written unless every check passes.
 *
 * A failed read or rename leaves the file and the store untouched. An apply
 * that throws after the rename is undone by restoring the bytes read here — or
 * by removing the file when there was none — so the two sides never describe
 * different edits, apart from a provider-set change, which the store defers to
 * a restart.
 */
export function saveConfig(
  store: Store,
  input: ConfigSnapshot,
  filePath = configFilePath(),
  io: SaveIo = defaultSaveIo,
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

  // Read the current file before touching it: a malformed file is reported as a
  // save error, and its exact bytes are what a failed apply is restored to.
  const existing = readExistingConfig(io, filePath)
  if ("error" in existing) return { ok: false, errors: [existing.error], restartRequired: false }

  // The snapshot covers only providers the store gates with a live budget, so a
  // provider outside that set has no entry. Keep the file's own budget for it
  // instead of deleting it on an unchanged save. This map is what the file
  // keeps; `tokens` above is what the store applies, so a provider the store
  // gates without a bucket is never handed its dormant file entry on a save.
  const fileTokens: Record<string, TokenBudgetConfig> = { ...tokens }
  const existingTokens = existing.value?.tokens
  if (existingTokens && typeof existingTokens === "object" && !Array.isArray(existingTokens)) {
    for (const [providerID, entry] of Object.entries(existingTokens as Record<string, unknown>)) {
      if (providerID in fileTokens) continue
      fileTokens[providerID] = entry as TokenBudgetConfig
    }
  }

  const next: Record<string, unknown> = {
    ...existing.value,
    providers: input.providers,
    tokens: fileTokens,
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

  // Write the new file first and rename it into place, then apply it. A failed
  // write or rename leaves both sides on the old configuration. An apply that
  // throws is restored to the bytes read above, or removed when there was no
  // previous file, so the store and the file never describe different edits.
  const temporary = `${filePath}.tmp`
  try {
    writeFileSync(temporary, `${JSON.stringify(next, null, 2)}\n`)
  } catch (error) {
    return {
      ok: false,
      errors: [`Could not write the settings file: ${errorMessage(error)}`],
      restartRequired: false,
    }
  }

  try {
    io.rename(temporary, filePath)
  } catch (error) {
    try {
      unlinkSync(temporary)
    } catch {
      // The rename failed, so a leftover temporary file is harmless.
    }
    return {
      ok: false,
      errors: [`Could not rename the settings file into place: ${errorMessage(error)}`],
      restartRequired: false,
    }
  }

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
    // The up-front validation makes this unreachable in practice; restoring the
    // file keeps it bounded if a store method ever throws.
    try {
      if (existing.bytes === undefined) unlinkSync(filePath)
      else writeFileSync(filePath, existing.bytes)
    } catch {
      // Nothing more can be done here; the save still reports the failure.
    }
    return {
      ok: false,
      errors: [`Could not apply the settings: ${errorMessage(error)}`],
      restartRequired: false,
    }
  }

  return { ok: true, errors: [], restartRequired: applied.restartRequired }
}

/**
 * Reads the current config file through the save seam. A missing file is not an
 * error: it means a fresh install with nothing to preserve or restore.
 */
function readExistingConfig(
  io: SaveIo,
  filePath: string,
): { value?: Record<string, unknown>; bytes?: string } | { error: string } {
  let bytes: string
  try {
    bytes = io.readFile(filePath)
  } catch (error) {
    if (isMissingFile(error)) return { value: undefined }
    return { error: `Failed to read ${filePath}: ${errorMessage(error)}` }
  }
  try {
    const parsed = JSON.parse(bytes) as unknown
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("config must be a JSON object")
    }
    return { value: parsed as Record<string, unknown>, bytes }
  } catch (error) {
    return { error: `Failed to read ${filePath}: ${errorMessage(error)}` }
  }
}

function isMissingFile(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    (error as { code?: unknown }).code === "ENOENT"
  )
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
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
  const capacity = configured.contextCapacity ?? 0
  if (!Number.isInteger(capacity) || capacity < 0) {
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
  const ceiling = configured.contextCeiling
  if (ceiling !== undefined && (!Number.isInteger(ceiling) || ceiling < 0)) {
    throw new Error(
      `scheduler.contextCeiling must be a non-negative integer, got ${String(ceiling)}`,
    )
  }
  for (const key of ["reserveShare", "smallShare"] as const) {
    const value = configured[key]
    if (value !== undefined && (!Number.isFinite(value) || value < 0 || value > 1)) {
      throw new Error(`scheduler.${key} must be between 0 and 1, got ${String(value)}`)
    }
  }
  const aging = configured.agingMs
  if (aging !== undefined && (!Number.isInteger(aging) || aging < 0)) {
    throw new Error(`scheduler.agingMs must be a non-negative integer, got ${String(aging)}`)
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
    contextCapacity: capacity,
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
    const safetyFactor = budget.safetyFactor
    if (safetyFactor !== undefined && (!Number.isFinite(safetyFactor) || safetyFactor <= 0)) {
      throw new Error(
        `tokens for provider "${providerID}" safetyFactor must be a finite number greater than zero, got ${String(safetyFactor)}`,
      )
    }
    budgets.set(providerID, {
      capacity: budget.capacity,
      refillPerMinute: budget.refillPerMinute,
      safetyFactor,
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

/**
 * The session's entry when exactly one primary request is unreleased.
 *
 * The response hook prefers the entry keyed by the request object; this is only
 * the fallback for a runtime that hands back a different object. Releasing the
 * wrong entry would free another request's slot, so an ambiguous session
 * releases nothing and lets the idle/delete path clean up.
 */
function soleEntry(entries: Set<Entry> | undefined): Entry | undefined {
  if (!entries) return undefined
  let found: Entry | undefined
  for (const entry of entries) {
    if (entry.released || entry.kind !== "primary") continue
    if (found) return undefined
    found = entry
  }
  return found
}

/**
 * Measures one request body as text bytes plus an image count.
 *
 * A body under the scan threshold is charged by its declared length, which is
 * accurate for text and cheap. A larger one is read once and scanned, because a
 * base64 image in it is billed by the provider as an image, not as the hundreds
 * of thousands of text tokens its bytes would otherwise imply.
 */
async function measureBody(
  request: Request,
  log: (...args: unknown[]) => void,
): Promise<BodyMeasure> {
  const declared = Number(request.headers.get("content-length"))
  if (Number.isFinite(declared) && declared > 0 && declared <= IMAGE_SCAN_BYTES) {
    return { textBytes: declared, images: 0 }
  }
  try {
    const body = request.clone().body
    if (!body) return { textBytes: 0, images: 0 }
    const reader = body.getReader()
    const decoder = new TextDecoder()
    let text = ""
    try {
      for (;;) {
        const { done, value } = await reader.read()
        if (done) break
        text += decoder.decode(value, { stream: true })
      }
      text += decoder.decode()
    } finally {
      reader.releaseLock()
    }
    return measureText(text)
  } catch (error) {
    log("token estimate skipped", error)
    return { textBytes: 0, images: 0 }
  }
}

/** Counts the text of a parsed body, charging each embedded blob as an image. */
function measureText(text: string): BodyMeasure {
  const measured = { textBytes: 0, images: 0 }
  try {
    walkBody(JSON.parse(text), measured)
    return measured
  } catch {
    // Not JSON, or too malformed to walk: fall back to the raw length.
    return { textBytes: text.length, images: 0 }
  }
}

function walkBody(value: unknown, measured: { textBytes: number; images: number }): void {
  if (typeof value === "string") {
    if (isImagePayload(value)) measured.images += 1
    else measured.textBytes += value.length
    return
  }
  if (Array.isArray(value)) {
    for (const item of value) walkBody(item, measured)
    return
  }
  if (value !== null && typeof value === "object") {
    for (const item of Object.values(value as Record<string, unknown>)) walkBody(item, measured)
  }
}

/** A data URI or a bare base64 blob, as an image or document part carries it. */
function isImagePayload(value: string): boolean {
  if (value.length < 2_048) return false
  if (/^data:[a-z]+\/[a-z0-9.+-]+;base64,/i.test(value)) return true
  return /^[A-Za-z0-9+/\r\n]{2048,}={0,2}$/.test(value) && /[+/=]/.test(value)
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
