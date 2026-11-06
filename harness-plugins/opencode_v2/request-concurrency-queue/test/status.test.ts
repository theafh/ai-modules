import { describe, expect, test } from "bun:test"
import type { ProviderStatus, StatusSnapshot } from "../src/rpc.js"
import { providerRows, subscribeStatus, type StatusClient } from "../src/status.js"

function tick(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0))
}

/**
 * Drains pending microtasks without arming a timer, so a rejected publish is
 * reported by the runner instead of being held open by a pending timer.
 */
async function settle(): Promise<void> {
  for (let i = 0; i < 10; i += 1) await Promise.resolve()
}

function provider(overrides: Partial<ProviderStatus> & Pick<ProviderStatus, "providerID">): ProviderStatus {
  const active = overrides.active ?? 0
  const queued = overrides.queued ?? 0
  const max = overrides.max ?? 1
  return {
    providerID: overrides.providerID,
    active,
    queued,
    max,
    utilization: overrides.utilization ?? (max === 0 ? 0 : active / max),
    demand: overrides.demand ?? (max === 0 ? 0 : (active + queued) / max),
  }
}

function snapshot(...providers: ProviderStatus[]): StatusSnapshot {
  return { providers }
}

interface FakeClient {
  client: StatusClient
  fire(): Promise<void>
  handlerCount(): number
}

function fakeClient(next: () => StatusSnapshot): FakeClient {
  const handlers = new Set<() => void | Promise<void>>()
  return {
    client: {
      status: async () => next(),
      events: {
        on: (_name, handler) => {
          handlers.add(handler)
          return () => {
            handlers.delete(handler)
          }
        },
      },
    },
    async fire() {
      for (const handler of [...handlers]) await handler()
    },
    handlerCount: () => handlers.size,
  }
}

describe("providerRows", () => {
  test("renders absolute counts and percentage utilization and demand", () => {
    const rows = providerRows(snapshot(provider({ providerID: "acme", active: 2, queued: 1, max: 4 })))

    expect(rows).toEqual([
      {
        providerID: "acme",
        active: 2,
        queued: 1,
        max: 4,
        utilization: "50%",
        demand: "75%",
        color: "red",
      },
    ])
  })

  test("colors green while there is headroom and no queue", () => {
    const [row] = providerRows(snapshot(provider({ providerID: "acme", active: 1, queued: 0, max: 2 })))
    expect(row.color).toBe("green")
  })

  test("colors amber at capacity with no queue", () => {
    const [row] = providerRows(snapshot(provider({ providerID: "acme", active: 2, queued: 0, max: 2 })))
    expect(row.color).toBe("amber")
  })

  test("colors red whenever a queue exists", () => {
    const [row] = providerRows(snapshot(provider({ providerID: "acme", active: 2, queued: 1, max: 2 })))
    expect(row.color).toBe("red")
  })
})

describe("subscribeStatus", () => {
  test("publishes a fresh snapshot on every changed event until unsubscribed", async () => {
    let calls = 0
    const fake = fakeClient(() => snapshot(provider({ providerID: "acme", active: ++calls, queued: 0, max: 4 })))
    const seen: number[] = []

    const unsubscribe = subscribeStatus(() => fake.client, (next) => {
      seen.push(next.providers[0].active)
    })

    await tick()
    expect(seen).toEqual([1])
    expect(fake.handlerCount()).toBe(1)

    await fake.fire()
    await tick()
    expect(seen).toEqual([1, 2])

    unsubscribe()
    await fake.fire()
    await tick()
    expect(seen).toEqual([1, 2])
  })

  test("moves the subscription to the new session's server on a switch", async () => {
    const first = fakeClient(() => snapshot(provider({ providerID: "first", active: 1, queued: 0, max: 4 })))
    const second = fakeClient(() => snapshot(provider({ providerID: "second", active: 2, queued: 0, max: 4 })))
    let current = first.client
    const seen: string[] = []

    const firstUnsubscribe = subscribeStatus(() => current, (next) => {
      seen.push(`${next.providers[0].providerID}:${next.providers[0].active}`)
    })
    await tick()
    expect(seen).toEqual(["first:1"])

    firstUnsubscribe()
    current = second.client
    const secondUnsubscribe = subscribeStatus(() => current, (next) => {
      seen.push(`${next.providers[0].providerID}:${next.providers[0].active}`)
    })
    await tick()
    expect(seen).toEqual(["first:1", "second:2"])

    await first.fire()
    await tick()
    expect(seen).toEqual(["first:1", "second:2"])

    await second.fire()
    await tick()
    expect(seen).toEqual(["first:1", "second:2", "second:2"])

    secondUnsubscribe()
  })

  test("a rejecting status writes no snapshot and raises no unhandled rejection", async () => {
    const client: StatusClient = {
      status: async () => {
        throw new Error("status unavailable")
      },
      events: {
        on: () => () => {},
      },
    }
    const seen: StatusSnapshot[] = []

    const unsubscribe = subscribeStatus(() => client, (next) => {
      seen.push(next)
    })
    await settle()
    unsubscribe()

    expect(seen).toEqual([])
  })

  test("drops a snapshot that resolves after unsubscribe", async () => {
    let resolveStatus!: (value: StatusSnapshot) => void
    const pending = new Promise<StatusSnapshot>((resolve) => {
      resolveStatus = resolve
    })
    const client: StatusClient = {
      status: () => pending,
      events: {
        on: () => () => {},
      },
    }
    const seen: StatusSnapshot[] = []

    const unsubscribe = subscribeStatus(() => client, (next) => {
      seen.push(next)
    })
    unsubscribe()
    resolveStatus(snapshot(provider({ providerID: "acme", active: 1, queued: 0, max: 4 })))
    await settle()

    expect(seen).toEqual([])
  })
})
