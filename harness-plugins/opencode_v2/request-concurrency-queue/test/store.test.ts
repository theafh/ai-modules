import { describe, expect, test } from "bun:test"
import { mkdtempSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { saveConfig } from "../src/index.js"
import {
  adoptStore,
  applyConfig,
  clearGlobalStore,
  createStore,
  fingerprintOf,
  globalStore,
  publish,
  releaseStore,
  snapshotOf,
  subscribeStore,
  TransitionBuffer,
  TRANSITION_LIMIT,
} from "../src/store.js"
import type { TransitionRecord } from "../src/rpc.js"

function transition(index: number): TransitionRecord {
  return {
    timestamp: 1_700_000_000_000 + index,
    providerID: "acme",
    kind: "acquired",
    sessionID: `session-${index}`,
    active: 1,
    queued: 0,
  }
}

describe("createStore", () => {
  test("builds one limiter per configured provider", async () => {
    const store = createStore(
      new Map([
        ["acme", 2],
        ["other", 1],
      ]),
    )

    expect([...store.providers.keys()]).toEqual(["acme", "other"])
    expect(snapshotOf(store).providers.map((provider) => provider.max)).toEqual([2, 1])

    const slot = await store.providers.get("acme")?.scheduler.acquire("session-a")
    expect(snapshotOf(store).providers[0]).toMatchObject({ providerID: "acme", active: 1, max: 2 })
    slot?.release()
    expect(snapshotOf(store).providers[0]).toMatchObject({ active: 0 })
  })

  test("each factory call builds an isolated store", async () => {
    const first = createStore(new Map([["acme", 1]]))
    const second = createStore(new Map([["acme", 1]]))

    const slot = await first.providers.get("acme")?.scheduler.acquire("session-a")
    expect(snapshotOf(first).providers[0]).toMatchObject({ active: 1 })
    expect(snapshotOf(second).providers[0]).toMatchObject({ active: 0 })
    slot?.release()
  })

  test("a limiter transition publishes to every subscriber", async () => {
    const store = createStore(new Map([["acme", 1]]))
    let first = 0
    let second = 0
    const unsubscribeFirst = subscribeStore(store, () => {
      first += 1
    })
    subscribeStore(store, () => {
      second += 1
    })

    const slot = await store.providers.get("acme")?.scheduler.acquire("session-a")
    expect({ first, second }).toEqual({ first: 1, second: 1 })

    unsubscribeFirst()
    slot?.release()
    expect({ first, second }).toEqual({ first: 1, second: 2 })
  })

  test("a throwing subscriber does not stop the others", () => {
    const store = createStore(new Map([["acme", 1]]))
    let reached = 0
    subscribeStore(store, () => {
      throw new Error("emitter failed")
    })
    subscribeStore(store, () => {
      reached += 1
    })

    expect(() => publish(store)).not.toThrow()
    expect(reached).toBe(1)
  })

  test("fingerprints a provider set order-independently", () => {
    expect(fingerprintOf(new Map([
      ["other", 2],
      ["acme", 1],
    ]))).toBe("acme=1,other=2")
    expect(fingerprintOf(new Map())).toBe("")
  })

  test("the status snapshot carries the transitions the limiter recorded", async () => {
    const store = createStore(new Map([["acme", 1]]))

    const slot = await store.providers.get("acme")?.scheduler.acquire("session-a")
    const queued = store.providers.get("acme")?.scheduler.acquire("session-b")
    slot?.release()
    await queued

    expect(snapshotOf(store).transitions).toEqual([
      { timestamp: expect.any(Number), providerID: "acme", kind: "acquired", sessionID: "session-a", active: 1, queued: 0 },
      { timestamp: expect.any(Number), providerID: "acme", kind: "queued", sessionID: "session-b", active: 1, queued: 1 },
      { timestamp: expect.any(Number), providerID: "acme", kind: "released", sessionID: "session-a", active: 0, queued: 1 },
      { timestamp: expect.any(Number), providerID: "acme", kind: "acquired", sessionID: "session-b", active: 1, queued: 0 },
    ])
  })
})

describe("TransitionBuffer", () => {
  test("keeps at most 50 entries and drops the oldest when a 51st is appended", () => {
    const buffer = new TransitionBuffer()
    for (let index = 0; index < TRANSITION_LIMIT; index += 1) buffer.append(transition(index))

    expect(buffer.recent()).toHaveLength(50)
    expect(buffer.recent()[0].sessionID).toBe("session-0")

    buffer.append(transition(50))

    const retained = buffer.recent()
    expect(retained).toHaveLength(50)
    expect(retained[0].sessionID).toBe("session-1")
    expect(retained[retained.length - 1].sessionID).toBe("session-50")
    expect(retained.map((entry) => entry.sessionID)).not.toContain("session-0")
  })

  test("returns a copy, so a caller cannot mutate the retained history", () => {
    const buffer = new TransitionBuffer()
    buffer.append(transition(0))

    const first = buffer.recent()
    first.pop()

    expect(buffer.recent()).toHaveLength(1)
  })
})


describe("reload grace", () => {
  test("a reload within the grace adopts the store and serves its waiters", async () => {
    const limits = new Map([["acme", 1]])
    const store = adoptStore(limits)
    const scheduler = store.providers.get("acme")!.scheduler

    const held = await scheduler.acquire("a")
    let admitted = false
    const waiting = scheduler.acquire("b").then((slot) => {
      admitted = true
      return slot
    })
    await Promise.resolve()
    expect(admitted).toBe(false)

    // The old instance disposes; a reload arrives before the grace expires.
    releaseStore(store, 100)
    const reloaded = adoptStore(limits)
    expect(reloaded).toBe(store)
    expect(globalStore()).toBe(store)

    held.release()
    const slot = await waiting
    expect(admitted).toBe(true)
    slot.release()

    releaseStore(reloaded, 0)
    expect(globalStore()).toBeUndefined()
  })

  test("without a reload the grace expires and cancels the waiters", async () => {
    const store = adoptStore(new Map([["acme", 1]]))
    const scheduler = store.providers.get("acme")!.scheduler

    const held = await scheduler.acquire("a")
    let error: Error | undefined
    const waiting = scheduler.acquire("b").catch((err) => {
      error = err
    })
    await Promise.resolve()

    releaseStore(store, 10)
    await new Promise((resolve) => setTimeout(resolve, 40))

    expect(error?.message).toContain("the queue plugin was unloaded")
    expect(globalStore()).toBeUndefined()
    held.release()
    await waiting
  })

  test("a disposing instance stops admitting until the reload adopts it", async () => {
    const limits = new Map([["acme", 1]])
    const store = adoptStore(limits)
    const scheduler = store.providers.get("acme")!.scheduler

    const held = await scheduler.acquire("a")
    let admitted = false
    const waiting = scheduler.acquire("b").then((slot) => {
      admitted = true
      return slot
    })
    await Promise.resolve()

    scheduler.beginDrain()
    held.release()
    await Promise.resolve()
    expect(admitted).toBe(false)

    const reloaded = adoptStore(limits)
    const slot = await waiting
    expect(admitted).toBe(true)
    slot.release()
    releaseStore(reloaded, 0)
    clearGlobalStore()
  })
})

describe("adopting an older store", () => {
  test("a store whose scheduler lacks a newer method still adopts", () => {
    const limits = new Map([["acme", 1]])
    const store = adoptStore(limits)
    // Simulate a store created by a build that predates `endDrain`.
    const scheduler = store.providers.get("acme")!.scheduler as unknown as Record<string, unknown>
    scheduler.endDrain = undefined

    expect(() => adoptStore(limits)).not.toThrow()
    expect(globalStore()).toBe(store)

    clearGlobalStore()
  })
})

describe("live subagent config", () => {
  test("clearing the subagent setting turns the gate off", () => {
    const store = createStore(new Map([["acme", 1]]), new Map(), undefined, { max: 2 })
    expect(store.subagents).toBeDefined()

    applyConfig(store, {
      providers: new Map([["acme", 1]]),
      tokens: new Map(),
      subagents: undefined,
      adaptive: false,
    })

    expect(store.subagents).toBeUndefined()
  })
})

describe("budget fill across a config edit", () => {
  test("changing the budget keeps what is left in it", async () => {
    const store = createStore(
      new Map([["acme", 1]]),
      new Map([["acme", { capacity: 1_000, refillPerMinute: 1 }]]),
    )
    const scheduler = store.providers.get("acme")!.scheduler
    const slot = await scheduler.acquire("a", { newTokens: 400, contextTokens: 0 })
    expect(scheduler.budgetSnapshot?.available).toBe(600)

    applyConfig(store, {
      providers: new Map([["acme", 1]]),
      tokens: new Map([["acme", { capacity: 2_000, refillPerMinute: 1 }]]),
      adaptive: false,
    })

    // The capacity grew, but the 400 already spent is not handed back.
    expect(scheduler.budgetSnapshot?.capacity).toBe(2_000)
    expect(scheduler.budgetSnapshot?.available).toBe(600)
    slot.release()
  })

  test("adding a budget starts it full", () => {
    const store = createStore(new Map([["acme", 1]]))

    applyConfig(store, {
      providers: new Map([["acme", 1]]),
      tokens: new Map([["acme", { capacity: 1_000, refillPerMinute: 1 }]]),
      adaptive: false,
    })

    expect(store.providers.get("acme")!.scheduler.budgetSnapshot?.available).toBe(1_000)
  })
})

describe("a provider-set change with in-place edits", () => {
  test("applies every in-place edit, writes the new set, and reports the restart", () => {
    const dir = mkdtempSync(join(tmpdir(), "rcq-store-"))
    const filePath = join(dir, "request-concurrency-queue.json")
    try {
      const store = createStore(
        new Map([
          ["acme", 8],
          ["other", 2],
        ]),
        new Map(),
        { contextCapacity: 1_000, contextCeiling: 2_000 },
        { max: 2 },
        false,
      )

      const result = saveConfig(
        store,
        {
          providers: { acme: 4, other: 3, third: 1 },
          tokens: { acme: { capacity: 400_000, refillPerMinute: 200_000, safetyFactor: 1.2 } },
          scheduler: {
            contextCapacity: 5_000,
            contextCeiling: 5_000,
            reserveShare: 0.25,
            smallShare: 0.1,
            agingMs: 30_000,
            queueDeadlineMs: 0,
            breaker: { threshold: 2, cooldownMs: 60_000, mode: "fail" },
          },
          subagents: { max: 5, hostAware: true },
          adaptive: true,
        },
        filePath,
      )

      expect(result.ok).toBe(true)
      expect(result.restartRequired).toBe(true)

      const acme = store.providers.get("acme")!.scheduler
      expect(acme.maxConcurrency).toBe(4)
      expect(acme.status().contextCapacity).toBe(5_000)
      expect(acme.budgetSnapshot?.capacity).toBe(400_000)
      expect(store.subagents?.status().max).toBe(5)
      expect(store.adaptive).toBe(true)
      // The added provider is deferred to the restart, not half-applied.
      expect(store.providers.has("third")).toBe(false)

      const written = JSON.parse(readFileSync(filePath, "utf8"))
      expect(written.providers).toEqual({ acme: 4, other: 3, third: 1 })
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })
})
