import { afterEach, describe, expect, test } from "bun:test"
import { mkdtempSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import plugin, { loadConfigFile, resolveProviderLimits } from "../src/index.js"
import type { StatusSnapshot } from "../src/rpc.js"
import { clearGlobalStore, globalStore } from "../src/store.js"

process.env.OPENCODE_REQUEST_CONCURRENCY_CONFIG = "/nonexistent/request-concurrency-queue.json"

type Hook = (event: any) => Promise<void> | void

/** Resolves after the microtask queue drains, so chained promises settle. */
function tick(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0))
}

/**
 * A push-driven async iterable standing in for the server's event
 * subscription. The plugin reads it with `for await`, so a test pushes one
 * event and the loop body runs as if the server had emitted it.
 */
interface EventStream {
  push(type: string, sessionID: string): void
  close(): void
  iterator: AsyncIterableIterator<unknown>
}

function makeEventStream(): EventStream {
  const queue: unknown[] = []
  const waiters: Array<(result: IteratorResult<unknown>) => void> = []
  let closed = false

  function close(): void {
    closed = true
    while (waiters.length > 0) {
      const waiter = waiters.shift()
      waiter?.({ value: undefined, done: true })
    }
  }

  function push(type: string, sessionID: string): void {
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

interface TestRpc {
  definition: () => any
  handlers: () => any
  registration: () => any
  /** How many `changed` events the registration has emitted. */
  emitCount: () => number
}

interface TestContext {
  hooks: Map<string, Hook>
  /** Emits one server event, as the real subscription would deliver it. */
  emit: (type: string, sessionID: string) => Promise<void>
  /** The type filter and abort signal the plugin passed to `subscribe`. */
  subscriptions: Array<{ types: readonly string[]; signal?: AbortSignal }>
  rpc: TestRpc
  cleanup: () => Promise<void>
}

function makeContext(options: Record<string, unknown>): any {
  const hooks = new Map<string, Hook>()
  const stream = makeEventStream()
  const subscriptions: Array<{ types: readonly string[]; signal?: AbortSignal }> = []
  const emits: Array<{ name: string; data: unknown }> = []
  let definition: unknown
  let handlers: unknown
  let registration: unknown
  const rpc = {
    register: async (nextDefinition: unknown, nextHandlers: unknown) => {
      definition = nextDefinition
      handlers = nextHandlers
      registration = {
        events: {
          emit: async (name: string, data: unknown) => {
            emits.push({ name, data })
          },
        },
        dispose: async () => {},
      }
      return registration
    },
  }
  return {
    options,
    hooks,
    subscriptions,
    rpc: {
      register: rpc.register,
      definition: () => definition,
      handlers: () => handlers,
      registration: () => registration,
      emitCount: () => emits.length,
    },
    emit: (type: string, sessionID: string) => stream.push(type, sessionID),
    session: {
      hook: async (name: string, callback: Hook) => {
        hooks.set(name, callback)
        return { dispose: async () => {} }
      },
    },
    event: {
      subscribe: ({ types, signal }: { types: readonly string[]; signal?: AbortSignal }) => {
        subscriptions.push({ types, signal })
        // End the stream when the plugin aborts, so its dispose path settles
        // exactly as it does against the real subscription.
        if (signal) {
          if (signal.aborted) stream.close()
          else signal.addEventListener("abort", () => stream.close(), { once: true })
        }
        return stream.iterator
      },
    },
  }
}

async function setup(options: Record<string, unknown>): Promise<TestContext> {
  const ctx = makeContext(options)
  const cleanup = await plugin.setup(ctx)
  return {
    hooks: ctx.hooks,
    subscriptions: ctx.subscriptions,
    rpc: ctx.rpc,
    emit: async (type: string, sessionID: string) => {
      ctx.emit(type, sessionID)
      // The plugin's loop body runs on the microtask queue after the value is
      // delivered, so a test must yield before asserting on released state.
      await tick()
    },
    cleanup: async () => {
      await cleanup?.()
    },
  }
}

function request(url: string, signal?: AbortSignal): Request {
  return new Request(url, { signal })
}

async function requestHook(
  hooks: Map<string, Hook>,
  sessionID: string,
  req: Request,
  providerID = "acme",
  kind = "primary",
): Promise<void> {
  const hook = hooks.get("http.request")
  if (!hook) throw new Error("missing http.request hook")
  await hook({ sessionID, model: { providerID, id: "test" }, kind, request: req })
}

async function responseHook(
  hooks: Map<string, Hook>,
  sessionID: string,
  req: Request,
  body: string,
  providerID = "acme",
  kind = "primary",
): Promise<Response> {
  const hook = hooks.get("http.response")
  if (!hook) throw new Error("missing http.response hook")
  const event = {
    sessionID,
    model: { providerID, id: "test" },
    kind,
    request: req,
    response: new Response(body),
  }
  await hook(event)
  return event.response
}

async function statusSnapshot(
  rpc: TestRpc,
  options?: { location?: { directory: string } },
): Promise<StatusSnapshot> {
  const handlers = rpc.handlers()
  if (!handlers?.status) throw new Error("missing status handler")
  return handlers.status({}, options)
}

// Every test must start and end with no process-wide store, so one test's
// shared state cannot decide another's result.
afterEach(() => {
  clearGlobalStore()
})

describe("request-concurrency-queue plugin", () => {
  test("limits concurrent requests and releases when the response body ends", async () => {
    const { hooks, cleanup } = await setup({ maxConcurrency: 1, providers: ["acme"] })
    const a = request("https://example.test/a")
    const b = request("https://example.test/b")
    const c = request("https://example.test/c")

    await requestHook(hooks, "a", a)

    let bAcquired = false
    const bPromise = requestHook(hooks, "b", b).then(() => {
      bAcquired = true
    })
    let cAcquired = false
    const cPromise = requestHook(hooks, "c", c).then(() => {
      cAcquired = true
    })

    await Promise.resolve()
    expect(bAcquired).toBe(false)
    expect(cAcquired).toBe(false)

    const aResponse = await responseHook(hooks, "a", a, "a-body")
    expect(await aResponse.text()).toBe("a-body")
    await bPromise
    expect(bAcquired).toBe(true)
    expect(cAcquired).toBe(false)

    const bResponse = await responseHook(hooks, "b", b, "b-body")
    expect(await bResponse.text()).toBe("b-body")
    await cPromise
    expect(cAcquired).toBe(true)

    const cResponse = await responseHook(hooks, "c", c, "c-body")
    expect(await cResponse.text()).toBe("c-body")

    await cleanup()
  })

  test("the status snapshot follows acquire, queue, and release", async () => {
    const { hooks, rpc, cleanup } = await setup({ maxConcurrency: 1, providers: ["acme"] })

    expect(await statusSnapshot(rpc)).toEqual({
      providers: [{ providerID: "acme", active: 0, queued: 0, max: 1, utilization: 0, demand: 0 }],
    })

    const a = request("https://example.test/a")
    await requestHook(hooks, "a", a)
    expect((await statusSnapshot(rpc)).providers[0]).toMatchObject({
      active: 1,
      queued: 0,
      max: 1,
      utilization: 1,
      demand: 1,
    })

    const b = request("https://example.test/b")
    let bAcquired = false
    const bPromise = requestHook(hooks, "b", b).then(() => {
      bAcquired = true
    })
    await tick()
    expect((await statusSnapshot(rpc)).providers[0]).toMatchObject({
      active: 1,
      queued: 1,
      max: 1,
      utilization: 1,
      demand: 2,
    })

    const aResponse = await responseHook(hooks, "a", a, "a-body")
    await aResponse.text()
    await bPromise
    expect(bAcquired).toBe(true)
    expect((await statusSnapshot(rpc)).providers[0]).toMatchObject({ active: 1, queued: 0 })

    const bResponse = await responseHook(hooks, "b", b, "b-body")
    await bResponse.text()
    expect((await statusSnapshot(rpc)).providers[0]).toMatchObject({ active: 0, queued: 0 })

    await cleanup()
  })

  test("the status snapshot omits providers with no configured limit", async () => {
    const { hooks, rpc, cleanup } = await setup({ maxConcurrency: 1, providers: ["acme"] })

    await requestHook(hooks, "a", request("https://example.test/a"))
    await requestHook(hooks, "other", request("https://example.test/other"), "other")

    const snapshot = await statusSnapshot(rpc)
    expect(snapshot.providers.map((provider) => provider.providerID)).toEqual(["acme"])

    await cleanup()
  })

  test("emits changed exactly once per count-changing transition", async () => {
    const { hooks, rpc, cleanup } = await setup({ maxConcurrency: 1, providers: ["acme"] })
    const assertOneEmit = (step: string, previous: number): number => {
      const current = rpc.emitCount()
      expect({ step, emits: current - previous }).toEqual({ step, emits: 1 })
      return current
    }

    let count = rpc.emitCount()

    const a = request("https://example.test/a")
    await requestHook(hooks, "a", a)
    count = assertOneEmit("free-slot acquire", count)

    const bController = new AbortController()
    const b = request("https://example.test/b", bController.signal)
    const bPromise = requestHook(hooks, "b", b)
    await tick()
    count = assertOneEmit("join wait queue", count)

    bController.abort()
    await expect(bPromise).rejects.toThrow("aborted")
    count = assertOneEmit("queued-request abort", count)

    const c = request("https://example.test/c")
    const cPromise = requestHook(hooks, "c", c)
    await tick()
    count = assertOneEmit("third request queues", count)

    const aResponse = await responseHook(hooks, "a", a, "a-body")
    await aResponse.text()
    await cPromise
    count = assertOneEmit("release hands off to the waiter", count)

    const cResponse = await responseHook(hooks, "c", c, "c-body")
    await cResponse.text()
    assertOneEmit("release frees a slot with no waiter", count)

    await cleanup()
  })

  test("does not gate providers outside the filter", async () => {
    const { hooks, cleanup } = await setup({ maxConcurrency: 1, providers: ["acme"] })
    const a = request("https://example.test/a")

    await requestHook(hooks, "a", a)
    await requestHook(hooks, "other", request("https://example.test/other"), "other")

    const aResponse = await responseHook(hooks, "a", a, "body")
    await aResponse.text()
    await cleanup()
  })

  test("retry releases the slot", async () => {
    const { hooks, cleanup } = await setup({ maxConcurrency: 1, providers: ["acme"] })
    const a = request("https://example.test/a")
    const b = request("https://example.test/b")

    await requestHook(hooks, "a", a)

    const retry = hooks.get("retry")
    if (!retry) throw new Error("missing retry hook")
    await retry({
      sessionID: "a",
      model: { providerID: "acme", id: "test" },
      error: {},
      attempt: 2,
      decision: { retry: true, delay: 1 },
    })

    await requestHook(hooks, "b", b)
    const bResponse = await responseHook(hooks, "b", b, "body")
    await bResponse.text()
    await cleanup()
  })

  test("a retry releases only the retrying session's slot", async () => {
    const { hooks, cleanup } = await setup({ maxConcurrency: 2, providers: ["acme"] })
    const a = request("https://example.test/a")
    const b = request("https://example.test/b")
    const c = request("https://example.test/c")
    const d = request("https://example.test/d")

    // Two sessions hold the provider's two slots.
    await requestHook(hooks, "a", a)
    await requestHook(hooks, "b", b)

    const retry = hooks.get("retry")
    if (!retry) throw new Error("missing retry hook")
    await retry({
      sessionID: "a",
      model: { providerID: "acme", id: "test" },
      error: {},
      attempt: 2,
      decision: { retry: true, delay: 1 },
    })

    // The retry frees session A's slot, so a new request acquires.
    let cAcquired = false
    const cPromise = requestHook(hooks, "c", c).then(() => {
      cAcquired = true
    })
    await tick()
    expect(cAcquired).toBe(true)

    // Session B's slot stays held, so a further request still waits.
    let dAcquired = false
    const dPromise = requestHook(hooks, "d", d).then(() => {
      dAcquired = true
    })
    await tick()
    expect(dAcquired).toBe(false)

    const bResponse = await responseHook(hooks, "b", b, "b-body")
    await bResponse.text()
    await dPromise
    expect(dAcquired).toBe(true)

    await cPromise
    await cleanup()
  })

  test("a retry releases the older of two primary entries for the session", async () => {
    const { hooks, cleanup } = await setup({ maxConcurrency: 2, providers: ["acme"] })
    const first = request("https://example.test/first")
    const second = request("https://example.test/second")
    const other = request("https://example.test/other")
    const further = request("https://example.test/further")

    // One session's two primary entries hold both slots.
    await requestHook(hooks, "a", first)
    await requestHook(hooks, "a", second)

    const retry = hooks.get("retry")
    if (!retry) throw new Error("missing retry hook")
    await retry({
      sessionID: "a",
      model: { providerID: "acme", id: "test" },
      error: {},
      attempt: 2,
      decision: { retry: true, delay: 1 },
    })

    // The retry frees the older entry, so another session's request acquires.
    let otherAcquired = false
    const otherPromise = requestHook(hooks, "b", other).then(() => {
      otherAcquired = true
    })
    await otherPromise
    expect(otherAcquired).toBe(true)

    // The session's newer entry stays held, so a further request waits.
    let furtherAcquired = false
    const furtherPromise = requestHook(hooks, "c", further).then(() => {
      furtherAcquired = true
    })
    await tick()
    expect(furtherAcquired).toBe(false)

    const secondResponse = await responseHook(hooks, "a", second, "second-body")
    await secondResponse.text()
    await furtherPromise
    expect(furtherAcquired).toBe(true)

    await cleanup()
  })

  test("a title request acquires no slot", async () => {
    const { hooks, rpc, cleanup } = await setup({ maxConcurrency: 1, providers: ["acme"] })

    await requestHook(hooks, "a", request("https://example.test/title"), "acme", "title")

    expect((await statusSnapshot(rpc)).providers[0]).toMatchObject({ active: 0, queued: 0 })
    await cleanup()
  })

  test("a title request that fails before its response headers does not block a primary request", async () => {
    const { hooks, rpc, cleanup } = await setup({ maxConcurrency: 1, providers: ["acme"] })

    // A title request that dies before its response headers fires neither
    // `http.response` nor `retry`, so it must not have taken a slot.
    await requestHook(hooks, "a", request("https://example.test/title"), "acme", "title")
    expect((await statusSnapshot(rpc)).providers[0]).toMatchObject({ active: 0 })

    const primary = request("https://example.test/primary")
    await requestHook(hooks, "a", primary)
    expect((await statusSnapshot(rpc)).providers[0]).toMatchObject({ active: 1 })

    const response = await responseHook(hooks, "a", primary, "primary-body")
    await response.text()
    expect((await statusSnapshot(rpc)).providers[0]).toMatchObject({ active: 0 })

    await cleanup()
  })

  test("a title response leaves the primary slot held", async () => {
    const { hooks, cleanup } = await setup({ maxConcurrency: 1, providers: ["acme"] })
    const primary = request("https://example.test/primary")
    const other = request("https://example.test/other")

    await requestHook(hooks, "a", primary)

    // The title response arrives for the same session while the primary body
    // is still streaming, and must not release the primary's slot.
    const titleResponse = await responseHook(
      hooks,
      "a",
      request("https://example.test/title"),
      "title-body",
      "acme",
      "title",
    )
    expect(await titleResponse.text()).toBe("title-body")

    let otherAcquired = false
    const otherPromise = requestHook(hooks, "b", other).then(() => {
      otherAcquired = true
    })
    await tick()
    expect(otherAcquired).toBe(false)

    const primaryResponse = await responseHook(hooks, "a", primary, "primary-body")
    await primaryResponse.text()
    await otherPromise
    expect(otherAcquired).toBe(true)

    await cleanup()
  })

  test("cancels a queued request", async () => {
    const { hooks, cleanup } = await setup({ maxConcurrency: 1, providers: ["acme"] })
    const a = request("https://example.test/a")
    await requestHook(hooks, "a", a)

    const controller = new AbortController()
    const b = request("https://example.test/b", controller.signal)
    const bPromise = requestHook(hooks, "b", b)

    controller.abort()
    await expect(bPromise).rejects.toThrow("aborted")

    const aResponse = await responseHook(hooks, "a", a, "body")
    await aResponse.text()
    await cleanup()
  })

  test("cancelling the response body releases the slot", async () => {
    const { hooks, cleanup } = await setup({ maxConcurrency: 1, providers: ["acme"] })
    const a = request("https://example.test/a")
    const b = request("https://example.test/b")

    await requestHook(hooks, "a", a)
    const bPromise = requestHook(hooks, "b", b)

    const aResponse = await responseHook(hooks, "a", a, "body")
    await aResponse.body?.cancel()
    await bPromise

    await cleanup()
  })

  test("uses a separate max for each provider", async () => {
    const { hooks, cleanup } = await setup({ providers: { acme: 1, other: 2 } })
    const a1 = request("https://example.test/a1")
    const a2 = request("https://example.test/a2")
    const b1 = request("https://example.test/b1")
    const b2 = request("https://example.test/b2")
    const b3 = request("https://example.test/b3")

    await requestHook(hooks, "a1", a1, "acme")
    let a2Acquired = false
    const a2Promise = requestHook(hooks, "a2", a2, "acme").then(() => {
      a2Acquired = true
    })

    await requestHook(hooks, "b1", b1, "other")
    await requestHook(hooks, "b2", b2, "other")
    let b3Acquired = false
    const b3Promise = requestHook(hooks, "b3", b3, "other").then(() => {
      b3Acquired = true
    })

    await Promise.resolve()
    expect(a2Acquired).toBe(false)
    expect(b3Acquired).toBe(false)

    const a1Response = await responseHook(hooks, "a1", a1, "a1", "acme")
    await a1Response.text()
    await a2Promise
    expect(a2Acquired).toBe(true)

    const b1Response = await responseHook(hooks, "b1", b1, "b1", "other")
    await b1Response.text()
    await b3Promise
    expect(b3Acquired).toBe(true)

    const b2Response = await responseHook(hooks, "b2", b2, "b2", "other")
    await b2Response.text()
    const a2Response = await responseHook(hooks, "a2", a2, "a2", "acme")
    await a2Response.text()
    const b3Response = await responseHook(hooks, "b3", b3, "b3", "other")
    await b3Response.text()

    await cleanup()
  })

  test("stays inactive when no providers are configured", async () => {
    const { hooks, cleanup } = await setup({ providers: [] })
    await requestHook(hooks, "a", request("https://example.test/a"))
    await cleanup()
  })

  test("subscribes to the release-bearing server event types", async () => {
    const { subscriptions, cleanup } = await setup({ providers: ["acme"] })
    expect(subscriptions).toHaveLength(1)
    expect([...subscriptions[0].types].sort()).toEqual([
      "session.deleted",
      "session.execution.failed",
      "session.execution.interrupted",
      "session.idle",
    ])
    await cleanup()
  })

  // Each server event that can end a session must release that session's held
  // slots, or the queue stalls behind a request that will never complete.
  for (const type of [
    "session.idle",
    "session.deleted",
    "session.execution.failed",
    "session.execution.interrupted",
  ]) {
    test(`${type} releases every held slot for the session`, async () => {
      const { hooks, emit, cleanup } = await setup({ maxConcurrency: 2, providers: ["acme"] })

      // Two in-flight requests for one session fill the provider's limit.
      await requestHook(hooks, "a", request("https://example.test/a1"))
      await requestHook(hooks, "a", request("https://example.test/a2"))

      // A third request queues behind them.
      let queuedAcquired = false
      const queued = requestHook(hooks, "b", request("https://example.test/b")).then(() => {
        queuedAcquired = true
      })
      await tick()
      expect(queuedAcquired).toBe(false)

      await emit(type, "a")

      // Both held slots released, so the queued request is served.
      await queued
      expect(queuedAcquired).toBe(true)

      await cleanup()
    })
  }

  test("a session event does not release another session's slots", async () => {
    const { hooks, emit, cleanup } = await setup({ maxConcurrency: 1, providers: ["acme"] })

    await requestHook(hooks, "a", request("https://example.test/a"))

    let bAcquired = false
    const bPromise = requestHook(hooks, "b", request("https://example.test/b")).then(() => {
      bAcquired = true
    })
    await tick()
    expect(bAcquired).toBe(false)

    // An event for an unrelated session leaves `a`'s slot held.
    await emit("session.idle", "unrelated")
    await tick()
    expect(bAcquired).toBe(false)

    // Releasing `a` by its own response body serves `b`.
    const aResponse = await responseHook(hooks, "a", request("https://example.test/a"), "a-body")
    await aResponse.text()
    await bPromise
    expect(bAcquired).toBe(true)

    await cleanup()
  })

  test("experimental.idle releases the session's slots", async () => {
    const { hooks, cleanup } = await setup({ maxConcurrency: 1, providers: ["acme"] })

    await requestHook(hooks, "a", request("https://example.test/a"))

    let bAcquired = false
    const bPromise = requestHook(hooks, "b", request("https://example.test/b")).then(() => {
      bAcquired = true
    })
    await tick()
    expect(bAcquired).toBe(false)

    const idle = hooks.get("experimental.idle")
    if (!idle) throw new Error("missing experimental.idle hook")
    await idle({ sessionID: "a" })

    await bPromise
    expect(bAcquired).toBe(true)

    await cleanup()
  })

  test("disposal releases every held slot", async () => {
    const { hooks, cleanup } = await setup({ maxConcurrency: 2, providers: ["acme"] })

    // Two slots held, with a waiter queued behind them.
    await requestHook(hooks, "a", request("https://example.test/a1"))
    await requestHook(hooks, "a", request("https://example.test/a2"))

    let queuedAcquired = false
    const queued = requestHook(hooks, "b", request("https://example.test/b")).then(() => {
      queuedAcquired = true
    })
    await tick()
    expect(queuedAcquired).toBe(false)

    // Disposal must not leave a waiter hanging, so it releases every entry.
    await cleanup()
    await queued
    expect(queuedAcquired).toBe(true)
  })

  test("disposal aborts the event subscription", async () => {
    const { subscriptions, cleanup } = await setup({ providers: ["acme"] })
    const signal = subscriptions[0].signal
    expect(signal?.aborted).toBe(false)

    await cleanup()

    expect(signal?.aborted).toBe(true)
  })
})

describe("process-wide store", () => {
  test("two setups with the same config share one limiter per provider", async () => {
    const first = await setup({ maxConcurrency: 2, providers: ["acme"] })
    const second = await setup({ maxConcurrency: 2, providers: ["acme"] })
    try {
      const a = request("https://example.test/a")
      await requestHook(first.hooks, "a", a)

      // The slot acquired through the first instance is visible in the
      // second instance's snapshot, because both read the same limiter.
      expect((await statusSnapshot(second.rpc)).providers[0]).toMatchObject({
        providerID: "acme",
        active: 1,
        queued: 0,
        max: 2,
      })

      const b = request("https://example.test/b")
      await requestHook(first.hooks, "b", b)

      // At the shared maximum, a request through the other instance queues
      // instead of taking the combined active count past the configured cap.
      let cAcquired = false
      const cPromise = requestHook(second.hooks, "c", request("https://example.test/c")).then(() => {
        cAcquired = true
      })
      await tick()
      expect(cAcquired).toBe(false)
      expect((await statusSnapshot(second.rpc)).providers[0]).toMatchObject({ active: 2, queued: 1, max: 2 })

      // A release through the first instance serves the second's waiter.
      const aResponse = await responseHook(first.hooks, "a", a, "a-body")
      await aResponse.text()
      await cPromise
      expect(cAcquired).toBe(true)
    } finally {
      await first.cleanup()
      await second.cleanup()
    }
  })

  test("a status call with no location and one with a location return the same snapshot", async () => {
    const first = await setup({ maxConcurrency: 2, providers: ["acme"] })
    const second = await setup({ maxConcurrency: 2, providers: ["acme"] })
    try {
      await requestHook(first.hooks, "a", request("https://example.test/a"))

      const noLocation = await statusSnapshot(second.rpc)
      const withLocation = await statusSnapshot(first.rpc, { location: { directory: "/work/other-project" } })

      expect(noLocation).toEqual(withLocation)
      expect(noLocation.providers[0]).toMatchObject({ active: 1 })
    } finally {
      await first.cleanup()
      await second.cleanup()
    }
  })

  test("keeps the status RPC input as the empty object", async () => {
    const { rpc, cleanup } = await setup({ maxConcurrency: 1, providers: ["acme"] })
    try {
      expect(rpc.definition().methods.status.input).toEqual({
        type: "object",
        properties: {},
        additionalProperties: false,
      })
    } finally {
      await cleanup()
    }
  })

  test("a later setup with a different config keeps the registry and logs the mismatch", async () => {
    const messages: string[] = []
    const original = console.log
    console.log = (...args: unknown[]) => {
      messages.push(args.map((arg) => (typeof arg === "string" ? arg : JSON.stringify(arg))).join(" "))
    }
    try {
      const first = await setup({ maxConcurrency: 1, providers: ["acme"], log: true })
      const second = await setup({ maxConcurrency: 2, providers: ["acme", "other"], log: true })
      try {
        // The first instance's provider set and maximum stay authoritative.
        expect((await statusSnapshot(second.rpc)).providers).toEqual([
          { providerID: "acme", active: 0, queued: 0, max: 1, utilization: 0, demand: 0 },
        ])
        expect(messages.some((message) => message.includes("config mismatch"))).toBe(true)
      } finally {
        await first.cleanup()
        await second.cleanup()
      }
    } finally {
      console.log = original
    }
  })

  test("disposing one instance leaves the shared limiters for the other, and the last clears the registry", async () => {
    const first = await setup({ maxConcurrency: 1, providers: ["acme"] })
    const second = await setup({ maxConcurrency: 1, providers: ["acme"] })

    await requestHook(first.hooks, "a", request("https://example.test/a"))
    await first.cleanup()

    // The surviving instance still gates through the shared limiter.
    expect(globalStore()).toBeDefined()
    await requestHook(second.hooks, "b", request("https://example.test/b"))
    expect((await statusSnapshot(second.rpc)).providers[0]).toMatchObject({ active: 1, max: 1 })

    await second.cleanup()
    expect(globalStore()).toBeUndefined()
  })

  test("a transition under one instance notifies the other instance's changed subscribers", async () => {
    const first = await setup({ maxConcurrency: 1, providers: ["acme"] })
    const second = await setup({ maxConcurrency: 1, providers: ["acme"] })
    try {
      const before = second.rpc.emitCount()
      await requestHook(first.hooks, "a", request("https://example.test/a"))
      expect(second.rpc.emitCount()).toBe(before + 1)
    } finally {
      await first.cleanup()
      await second.cleanup()
    }
  })
})

describe("resolveProviderLimits", () => {
  test("supports a provider list with a shared default", () => {
    expect([...resolveProviderLimits({ maxConcurrency: 2, providers: ["a", "b"] })]).toEqual([
      ["a", 2],
      ["b", 2],
    ])
  })

  test("supports a per-provider number map", () => {
    expect([...resolveProviderLimits({ providers: { a: 1, b: 3 } })]).toEqual([
      ["a", 1],
      ["b", 3],
    ])
  })

  test("returns no limits when no providers are configured", () => {
    expect(resolveProviderLimits({ providers: [] }).size).toBe(0)
  })

  test("reads per-provider limits from the environment", () => {
    const previous = process.env.OPENCODE_REQUEST_CONCURRENCY_PROVIDERS
    process.env.OPENCODE_REQUEST_CONCURRENCY_PROVIDERS = "a=1,b=3"
    try {
      expect([...resolveProviderLimits({})]).toEqual([
        ["a", 1],
        ["b", 3],
      ])
    } finally {
      if (previous === undefined) delete process.env.OPENCODE_REQUEST_CONCURRENCY_PROVIDERS
      else process.env.OPENCODE_REQUEST_CONCURRENCY_PROVIDERS = previous
    }
  })

  test("reads a JSON provider map from the environment", () => {
    const previous = process.env.OPENCODE_REQUEST_CONCURRENCY_PROVIDERS
    process.env.OPENCODE_REQUEST_CONCURRENCY_PROVIDERS = '{"a":2,"b":4}'
    try {
      expect([...resolveProviderLimits({})]).toEqual([
        ["a", 2],
        ["b", 4],
      ])
    } finally {
      if (previous === undefined) delete process.env.OPENCODE_REQUEST_CONCURRENCY_PROVIDERS
      else process.env.OPENCODE_REQUEST_CONCURRENCY_PROVIDERS = previous
    }
  })

  test("rejects an invalid max", () => {
    expect(() => resolveProviderLimits({ providers: { a: 0 } })).toThrow("positive integer")
  })
})

describe("config file", () => {
  test("loads providers from a JSON file", () => {
    const directory = mkdtempSync(join(tmpdir(), "rcq-"))
    const file = join(directory, "config.json")
    writeFileSync(file, JSON.stringify({ providers: { a: 2 }, log: true }))
    expect(loadConfigFile(file)).toEqual({ providers: { a: 2 }, log: true })
  })

  test("returns undefined for a missing file", () => {
    expect(loadConfigFile("/nonexistent/request-concurrency-queue.json")).toBeUndefined()
  })

  test("throws on invalid JSON", () => {
    const directory = mkdtempSync(join(tmpdir(), "rcq-"))
    const file = join(directory, "config.json")
    writeFileSync(file, "{")
    expect(() => loadConfigFile(file)).toThrow("Failed to read")
  })

  test("uses file config when options omit providers", () => {
    expect([...resolveProviderLimits({}, { providers: { a: 2 } })]).toEqual([["a", 2]])
  })

  test("options override file config", () => {
    expect([...resolveProviderLimits({ providers: { a: 3 } }, { providers: { a: 2 } })]).toEqual([["a", 3]])
  })
})
