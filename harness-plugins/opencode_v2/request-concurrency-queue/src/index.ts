import { Plugin } from "@opencode/plugin"
import { existsSync, readFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"
import { FifoLimiter, type Slot } from "./limiter.js"
import { statusRpc, type ProviderStatus, type StatusSnapshot } from "./rpc.js"

export interface RequestConcurrencyQueueOptions {
  maxConcurrency?: number
  providers?: string[] | Record<string, number>
  log?: boolean
}

export interface RequestConcurrencyQueueFileConfig {
  maxConcurrency?: number
  providers?: string[] | Record<string, number>
  log?: boolean
}

interface ProviderLimit {
  readonly maxConcurrency: number
  readonly limiter: FifoLimiter
}

interface Entry {
  readonly sessionID: string
  readonly providerID: string
  readonly slot: Slot
  released: boolean
}

const DEFAULT_MAX_CONCURRENCY = 1

export default Plugin.define({
  id: "request-concurrency-queue",
  async setup(ctx) {
    const options = (ctx.options ?? {}) as RequestConcurrencyQueueOptions
    const fileConfig = loadConfigFile()
    const limits = new Map<string, ProviderLimit>()
    const registration = await ctx.rpc.register(statusRpc, {
      status: async () => snapshot(limits),
    })
    for (const [providerID, maxConcurrency] of resolveProviderLimits(options, fileConfig)) {
      limits.set(providerID, {
        maxConcurrency,
        limiter: new FifoLimiter(maxConcurrency, () => void registration.events.emit("changed", {})),
      })
    }

    const bySession = new Map<string, Set<Entry>>()
    const byRequest = new WeakMap<Request, Entry>()
    const logEnabled = options.log ?? fileConfig?.log ?? envLog()
    const log = logEnabled
      ? (...args: unknown[]) => console.log("[request-concurrency-queue]", ...args)
      : () => {}

    log("initialized", {
      providers: Object.fromEntries([...limits].map(([providerID, limit]) => [providerID, limit.maxConcurrency])),
    })

    const addEntry = (sessionID: string, providerID: string, slot: Slot, request: Request): Entry => {
      const entry: Entry = { sessionID, providerID, slot, released: false }
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
        active: limit?.limiter.activeCount,
        queued: limit?.limiter.queuedCount,
      })
      return entry
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

      const limit = limits.get(entry.providerID)
      log("released", {
        sessionID: entry.sessionID,
        providerID: entry.providerID,
        reason,
        active: limit?.limiter.activeCount,
        queued: limit?.limiter.queuedCount,
      })
    }

    const releaseSession = (sessionID: string, reason: string): void => {
      const entries = bySession.get(sessionID)
      if (!entries) return
      for (const entry of [...entries]) releaseEntry(entry, reason)
    }

    await ctx.session.hook("http.request", async (event) => {
      const limit = limits.get(event.model.providerID)
      if (!limit) return
      const slot = await limit.limiter.acquire(event.request.signal)
      addEntry(event.sessionID, event.model.providerID, slot, event.request)
    })

    await ctx.session.hook("http.response", async (event) => {
      const entry = byRequest.get(event.request) ?? firstEntry(bySession.get(event.sessionID))
      if (!entry) return

      const response = event.response
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
      releaseSession(event.sessionID, "retry")
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
      for (const sessionID of [...bySession.keys()]) releaseSession(sessionID, "dispose")
      await eventLoop.catch(() => {})
      await registration.dispose()
    }
  },
})

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

function snapshot(limits: Map<string, ProviderLimit>): StatusSnapshot {
  const providers = [...limits].map(([providerID, limit]): ProviderStatus => {
    const active = limit.limiter.activeCount
    const queued = limit.limiter.queuedCount
    const max = limit.maxConcurrency
    return {
      providerID,
      active,
      queued,
      max,
      utilization: max === 0 ? 0 : active / max,
      demand: max === 0 ? 0 : (active + queued) / max,
    }
  })
  return { providers }
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
