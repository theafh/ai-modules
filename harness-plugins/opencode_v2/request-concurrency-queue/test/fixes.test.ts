import { afterEach, describe, expect, test } from "bun:test"
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import plugin, { type RequestConcurrencyQueueFileConfig } from "../src/index.js"
import type { StatusSnapshot } from "../src/rpc.js"
import { clearGlobalStore } from "../src/store.js"

// Each test points the plugin at its own config file, so a re-read cannot pick
// up another test's settings.
const configDir = mkdtempSync(join(tmpdir(), "rcq-fixes-"))
let configFile = join(configDir, "config.json")
process.env.OPENCODE_REQUEST_CONCURRENCY_CONFIG = configFile

const tick = () => new Promise((resolve) => setTimeout(resolve, 0))

function settledWithin(promise: Promise<unknown>, ms: number): Promise<boolean> {
  return Promise.race([
    promise.then(
      () => true,
      () => true,
    ),
    new Promise<boolean>((resolve) => setTimeout(() => resolve(false), ms)),
  ])
}

function makeEventStream() {
  const queue: unknown[] = []
  const waiters: Array<(result: IteratorResult<unknown>) => void> = []
  let closed = false
  const close = () => {
    closed = true
    while (waiters.length) waiters.shift()!({ value: undefined, done: true })
  }
  const push = (type: string, sessionID: string) => {
    if (closed) return
    const event = { type, data: { sessionID } }
    const waiter = waiters.shift()
    if (waiter) waiter({ value: event, done: false })
    else queue.push(event)
  }
  const iterator: AsyncIterableIterator<unknown> = {
    next() {
      const queued = queue.shift()
      if (queued !== undefined) return Promise.resolve({ value: queued, done: false })
      if (closed) return Promise.resolve({ value: undefined, done: true })
      return new Promise((resolve) => waiters.push(resolve))
    },
    return() {
      close()
      return Promise.resolve({ value: undefined, done: true })
    },
    [Symbol.asyncIterator]() {
      return iterator
    },
  }
  return { push, close, iterator }
}

function makeContext(options: Record<string, unknown>) {
  const hooks = new Map<string, any>()
  const tools = new Map<string, any>()
  const stream = makeEventStream()
  let handlers: any
  const ctx: any = {
    options,
    hooks,
    tools,
    rpc: {
      register: async (_definition: unknown, nextHandlers: unknown) => {
        handlers = nextHandlers
        return { events: { emit: async () => {} }, dispose: async () => {} }
      },
    },
    session: {
      hook: async (name: string, callback: any) => {
        hooks.set(name, callback)
        return { dispose: async () => {} }
      },
    },
    tool: {
      transform: async (callback: (editor: any) => void) => {
        const editor = {
          get: (id: string) => tools.get(id),
          update: (id: string, update: (tool: any) => void) => {
            const tool = tools.get(id)
            if (tool) update(tool)
          },
          add: (tool: any) => tools.set(tool.name, tool),
        }
        callback(editor)
        return { dispose: async () => {} }
      },
    },
    event: {
      subscribe: ({ signal }: { signal?: AbortSignal } = {}) => {
        signal?.addEventListener("abort", () => stream.close(), { once: true })
        return stream.iterator
      },
    },
  }
  return {
    ctx,
    hooks,
    tools,
    status: () => handlers.status({}) as Promise<StatusSnapshot>,
    config: () => handlers.config({}),
    save: (input: unknown) => handlers.save(input),
  }
}

async function setup(options: Record<string, unknown>, seedTools?: (tools: Map<string, any>) => void) {
  const context = makeContext({ reloadGraceMs: 0, ...options })
  seedTools?.(context.tools)
  const cleanup = await plugin.setup(context.ctx)
  return { ...context, cleanup }
}

const request = (url: string, body?: string) =>
  body === undefined
    ? new Request(url)
    : new Request(url, { method: "POST", body, headers: { "content-type": "application/json" } })

const requestHook = (hooks: Map<string, any>, sessionID: string, req: Request, kind = "primary") =>
  hooks.get("http.request")!({ sessionID, model: { providerID: "acme", id: "test" }, kind, request: req })

async function responseHook(
  hooks: Map<string, any>,
  sessionID: string,
  req: Request,
  init: ResponseInit,
  body = "body",
  kind = "primary",
) {
  const event = {
    sessionID,
    model: { providerID: "acme", id: "test" },
    kind,
    request: req,
    response: new Response(body, init),
  }
  await hooks.get("http.response")!(event)
  return event.response
}

afterEach(() => clearGlobalStore())

describe("a 5xx is a provider stall even when its body is drained", () => {
  test("a drained 500 opens the breaker and shrinks the cap", async () => {
    const { hooks, status, cleanup } = await setup({
      maxConcurrency: 1,
      providers: ["acme"],
      scheduler: {
        contextCapacity: 800_000,
        contextCeiling: 800_000,
        breaker: { threshold: 1, cooldownMs: 60_000, mode: "wait" },
      },
    })
    const req = request("https://example.test/a")
    await requestHook(hooks, "a", req)
    const response = await responseHook(hooks, "a", req, { status: 500 }, "server error")
    await response.text()

    const provider = (await status()).providers[0]
    expect(provider.stalls).toBe(1)
    expect(provider.breaker).toBe("open")
    expect(provider.contextCapacity).toBe(400_000)
    await cleanup?.()
  })
})

describe("an embedded image is charged as an image, not as text", () => {
  test("a 300 KB base64 image fits a budget that its bytes would exhaust", async () => {
    const { hooks, status, cleanup } = await setup({
      maxConcurrency: 2,
      providers: ["acme"],
      tokens: { acme: { capacity: 20_000, refillPerMinute: 1 } },
    })
    const image = "A".repeat(300_000)
    const body = JSON.stringify({
      model: "test",
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: "what is in this screenshot?" },
            { type: "image_url", image_url: { url: `data:image/png;base64,${image}` } },
          ],
        },
      ],
    })
    const req = request("https://example.test/image", body)
    expect(await settledWithin(requestHook(hooks, "a", req), 500)).toBe(true)
    expect((await status()).providers[0].active).toBe(1)
    await cleanup?.()
  })
})

describe("an auxiliary request is charged to the token budget", () => {
  test("a compaction waits when the bucket is spent", async () => {
    const { hooks, status, cleanup } = await setup({
      maxConcurrency: 2,
      providers: ["acme"],
      tokens: { acme: { capacity: 1_000, refillPerMinute: 60 } },
    })
    // Spend the whole bucket with a primary request.
    const primary = request("https://example.test/primary", "x".repeat(3_500))
    await requestHook(hooks, "a", primary)
    const response = await responseHook(hooks, "a", primary, { status: 200 }, "ok")
    await response.text()

    // The compaction is a fresh large prompt and must wait for the bucket.
    const compaction = request("https://example.test/compact", "y".repeat(700))
    const pending = requestHook(hooks, "a", compaction, "compaction")
    expect(await settledWithin(pending, 100)).toBe(false)
    expect((await status()).providers[0].active).toBe(0)

    await hooks.get("experimental.idle")!({ sessionID: "a", background: [] })
    await expect(pending).rejects.toThrow("cancelled")
    await cleanup?.()
  })
})

describe("an auxiliary response is classified like a primary one", () => {
  test("a burst-protection 429 on a compaction pauses the bucket", async () => {
    const { hooks, status, cleanup } = await setup({
      maxConcurrency: 2,
      providers: ["acme"],
      tokens: { acme: { capacity: 1_000, refillPerMinute: 60_000 } },
    })
    const compaction = request("https://example.test/compact", "{}")
    await requestHook(hooks, "a", compaction, "compaction")
    await responseHook(
      hooks,
      "a",
      compaction,
      { status: 429, headers: { "retry-after": "30" } },
      JSON.stringify({ error: { code: "burst_protection" } }),
      "compaction",
    )

    const provider = (await status()).providers[0]
    const pauseMs = provider.tokensPausedUntil - Date.now()
    expect(pauseMs).toBeGreaterThan(25_000)
    expect(provider.max).toBe(2)
    await cleanup?.()
  })

  test("a 5xx on a compaction counts as a stall", async () => {
    const { hooks, status, cleanup } = await setup({
      maxConcurrency: 2,
      providers: ["acme"],
      scheduler: {
        contextCapacity: 800_000,
        contextCeiling: 800_000,
        breaker: { threshold: 1, cooldownMs: 60_000, mode: "wait" },
      },
    })
    const compaction = request("https://example.test/compact", "{}")
    await requestHook(hooks, "a", compaction, "compaction")
    await responseHook(hooks, "a", compaction, { status: 500 }, "boom", "compaction")

    const provider = (await status()).providers[0]
    expect(provider.stalls).toBe(1)
    expect(provider.breaker).toBe("open")
    expect(provider.contextCapacity).toBe(400_000)
    await cleanup?.()
  })
})

describe("the status snapshot names the gate that holds a request", () => {
  test("a request waiting for a slot is counted under slots", async () => {
    const { hooks, status, cleanup } = await setup({ maxConcurrency: 1, providers: ["acme"] })
    await requestHook(hooks, "a", request("https://example.test/a"))
    const queued = requestHook(hooks, "b", request("https://example.test/b"))
    await tick()
    expect((await status()).providers[0].blocked).toEqual({
      slots: 1,
      context: 0,
      budget: 0,
      breaker: 0,
      draining: 0,
    })
    await hooks.get("experimental.idle")!({ sessionID: "b", background: [] })
    await expect(queued).rejects.toThrow("cancelled")
    await cleanup?.()
  })
})

describe("the fan-out line distinguishes live children from model calls", () => {
  test("a live child running a tool is live but not calling", async () => {
    const { hooks, tools, status, cleanup } = await setup(
      { maxConcurrency: 2, providers: ["acme"], subagents: { max: 2 } },
      (seeded) => {
        seeded.set("subagent", {
          name: "subagent",
          execute: async () => ({ sessionID: "ses_child1" }),
        })
      },
    )

    // A launch binds its permit to the child session.
    await tools.get("subagent").execute({}, { sessionID: "parent" })
    let subagents = (await status()).subagents
    expect(subagents).toMatchObject({ live: 1, calling: 0, queued: 0 })

    // The child calls the model: live stays 1, calling becomes 1.
    const req = request("https://example.test/child")
    await requestHook(hooks, "ses_child1", req)
    subagents = (await status()).subagents
    expect(subagents).toMatchObject({ live: 1, calling: 1 })
    expect((await status()).providers[0].active).toBe(1)

    // The response ends and the child is back in a tool: calling returns to 0.
    const response = await responseHook(hooks, "ses_child1", req, { status: 200 }, "ok")
    await response.text()
    subagents = (await status()).subagents
    expect(subagents).toMatchObject({ live: 1, calling: 0 })
    expect((await status()).providers[0].active).toBe(0)

    await cleanup?.()
  })
})

describe("the settings form reads the file as it is now", () => {
  test("a saved change is visible on the next config read", async () => {
    configFile = join(mkdtempSync(join(tmpdir(), "rcq-config-")), "config.json")
    process.env.OPENCODE_REQUEST_CONCURRENCY_CONFIG = configFile
    const base: RequestConcurrencyQueueFileConfig = {
      providers: { acme: 8 },
      scheduler: {
        contextCapacity: 1_200_000,
        contextCeiling: 1_200_000,
        reserveShare: 0.25,
        smallShare: 0.1,
        agingMs: 30_000,
        queueDeadlineMs: 0,
        breaker: { threshold: 3, cooldownMs: 60_000, mode: "fail" },
      },
      adaptive: false,
    }
    writeFileSync(configFile, JSON.stringify(base))

    const { config, save, cleanup } = await setup({ providers: { acme: 8 } })
    const before = await config()
    expect(before.scheduler.contextCapacity).toBe(1_200_000)

    const saved = await save({
      ...before,
      scheduler: { ...before.scheduler, contextCapacity: 400_000, contextCeiling: 400_000 },
    })
    expect(saved.ok).toBe(true)

    // The file now holds the new cap, and the form must report it rather than
    // the snapshot captured at load time.
    const after = await config()
    expect(after.scheduler.contextCapacity).toBe(400_000)
    expect(JSON.parse(readFileSync(configFile, "utf8")).scheduler.contextCapacity).toBe(400_000)
    await cleanup?.()
  })
})
