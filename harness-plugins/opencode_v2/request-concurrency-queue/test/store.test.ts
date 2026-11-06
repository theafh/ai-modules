import { describe, expect, test } from "bun:test"
import { createStore, fingerprintOf, publish, snapshotOf, subscribeStore, TransitionBuffer, TRANSITION_LIMIT } from "../src/store.js"
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

    const slot = await store.providers.get("acme")?.limiter.acquire("session-a")
    expect(snapshotOf(store).providers[0]).toMatchObject({ providerID: "acme", active: 1, max: 2 })
    slot?.release()
    expect(snapshotOf(store).providers[0]).toMatchObject({ active: 0 })
  })

  test("each factory call builds an isolated store", async () => {
    const first = createStore(new Map([["acme", 1]]))
    const second = createStore(new Map([["acme", 1]]))

    const slot = await first.providers.get("acme")?.limiter.acquire("session-a")
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

    const slot = await store.providers.get("acme")?.limiter.acquire("session-a")
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

    const slot = await store.providers.get("acme")?.limiter.acquire("session-a")
    const queued = store.providers.get("acme")?.limiter.acquire("session-b")
    slot?.release()
    await queued

    expect(snapshotOf(store).transitions).toEqual([
      { timestamp: expect.any(Number), providerID: "acme", kind: "acquired", sessionID: "session-a", active: 1, queued: 0 },
      { timestamp: expect.any(Number), providerID: "acme", kind: "queued", sessionID: "session-b", active: 1, queued: 1 },
      { timestamp: expect.any(Number), providerID: "acme", kind: "released", sessionID: "session-a", active: 1, queued: 0 },
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
