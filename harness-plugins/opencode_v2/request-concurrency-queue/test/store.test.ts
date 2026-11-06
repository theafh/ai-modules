import { describe, expect, test } from "bun:test"
import { createStore, fingerprintOf, publish, snapshotOf, subscribeStore } from "../src/store.js"

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

    const slot = await store.providers.get("acme")?.limiter.acquire()
    expect(snapshotOf(store).providers[0]).toMatchObject({ providerID: "acme", active: 1, max: 2 })
    slot?.release()
    expect(snapshotOf(store).providers[0]).toMatchObject({ active: 0 })
  })

  test("each factory call builds an isolated store", async () => {
    const first = createStore(new Map([["acme", 1]]))
    const second = createStore(new Map([["acme", 1]]))

    const slot = await first.providers.get("acme")?.limiter.acquire()
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

    const slot = await store.providers.get("acme")?.limiter.acquire()
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
})
