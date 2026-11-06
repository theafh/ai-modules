import { describe, expect, test } from "bun:test"
import type { ProviderStatus, StatusSnapshot } from "../src/rpc.js"
import { loadColor, providerRows, subscribeStatus, type StatusClient } from "../src/status.js"

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
  return { providers, transitions: [] }
}

/** Narrows a delivered value to the successful snapshot these tests expect. */
function present(next: StatusSnapshot | null): StatusSnapshot {
  if (next === null) throw new Error("expected a status snapshot")
  return next
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
        utilizationColor: loadColor(50),
        demandColor: loadColor(75),
      },
    ])
  })

  test("colors the active count by utilization and the queue by demand", () => {
    const [row] = providerRows(snapshot(provider({ providerID: "acme", active: 2, queued: 1, max: 4 })))

    expect(row.utilizationColor).toBe(loadColor(50))
    expect(row.demandColor).toBe(loadColor(75))
  })
})

describe("loadColor", () => {
  test("anchors green at zero, yellow at 100, orange at 200, and red at 300", () => {
    expect(loadColor(0)).toBe("hsl(145 65% 50%)")
    expect(loadColor(100)).toBe("hsl(48 95% 55%)")
    expect(loadColor(200)).toBe("hsl(28 95% 58%)")
    expect(loadColor(300)).toBe("hsl(0 80% 62%)")
  })

  test("warms continuously as the load climbs between anchors", () => {
    const hue = (percent: number): number => Number(loadColor(percent).match(/^hsl\((\d+)/)?.[1])

    expect(hue(0)).toBeGreaterThan(hue(50))
    expect(hue(50)).toBeGreaterThan(hue(100))
    expect(hue(100)).toBeGreaterThan(hue(150))
    expect(hue(150)).toBeGreaterThan(hue(200))
    expect(hue(200)).toBeGreaterThan(hue(250))
    expect(hue(250)).toBeGreaterThan(hue(300))
  })

  test("stays red past 300 and treats a negative or missing load as zero", () => {
    expect(loadColor(450)).toBe(loadColor(300))
    expect(loadColor(-10)).toBe(loadColor(0))
    expect(loadColor(Number.NaN)).toBe(loadColor(0))
  })
})

describe("subscribeStatus", () => {
  test("publishes a fresh snapshot on every changed event until unsubscribed", async () => {
    let calls = 0
    const fake = fakeClient(() => snapshot(provider({ providerID: "acme", active: ++calls, queued: 0, max: 4 })))
    const seen: number[] = []

    const unsubscribe = subscribeStatus(() => fake.client, (next) => {
      seen.push(present(next).providers[0].active)
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
      const value = present(next)
      seen.push(`${value.providers[0].providerID}:${value.providers[0].active}`)
    })
    await tick()
    expect(seen).toEqual(["first:1"])

    firstUnsubscribe()
    current = second.client
    const secondUnsubscribe = subscribeStatus(() => current, (next) => {
      const value = present(next)
      seen.push(`${value.providers[0].providerID}:${value.providers[0].active}`)
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

  test("a rejected fetch delivers null and raises no unhandled rejection", async () => {
    const client: StatusClient = {
      status: async () => {
        throw new Error("status unavailable")
      },
      events: {
        on: () => () => {},
      },
    }
    const seen: Array<StatusSnapshot | null> = []

    const unsubscribe = subscribeStatus(() => client, (next) => {
      seen.push(next)
    })
    await settle()
    unsubscribe()

    expect(seen).toEqual([null])
  })

  test("sends the empty body and the session directory as the call location", async () => {
    const calls: Array<{ input: unknown; options: unknown }> = []
    const client: StatusClient = {
      status: async (input, options) => {
        calls.push({ input, options })
        return snapshot(provider({ providerID: "acme" }))
      },
      events: {
        on: () => () => {},
      },
    }

    const unsubscribe = subscribeStatus(() => client, () => {}, { directory: "/work/project-a" })
    await tick()
    unsubscribe()

    expect(calls).toEqual([{ input: {}, options: { location: { directory: "/work/project-a" } } }])
  })

  test("re-subscribes with the new session's directory on a switch", async () => {
    const directories: string[] = []
    const makeClient = (directory: string): StatusClient => ({
      status: async (_input, options) => {
        directories.push(options?.location?.directory ?? "")
        return snapshot(provider({ providerID: directory }))
      },
      events: {
        on: () => () => {},
      },
    })
    const first = makeClient("/work/first")
    const second = makeClient("/work/second")

    const firstUnsubscribe = subscribeStatus(() => first, () => {}, { directory: "/work/first" })
    await tick()
    firstUnsubscribe()

    const secondUnsubscribe = subscribeStatus(() => second, () => {}, { directory: "/work/second" })
    await tick()
    secondUnsubscribe()

    expect(directories).toEqual(["/work/first", "/work/second"])
  })

  test("refetches on its interval even without a changed event", async () => {
    let calls = 0
    const client: StatusClient = {
      status: async () => snapshot(provider({ providerID: "acme", active: ++calls })),
      events: {
        on: () => () => {},
      },
    }
    const seen: number[] = []

    const unsubscribe = subscribeStatus(
      () => client,
      (next) => {
        if (next) seen.push(next.providers[0].active)
      },
      { refetchIntervalMs: 10 },
    )
    await new Promise((resolve) => setTimeout(resolve, 60))
    unsubscribe()

    expect(seen.length).toBeGreaterThan(1)
  })

  test("recovers from a failed fetch on the next successful refetch", async () => {
    let fail = true
    const client: StatusClient = {
      status: async () => {
        if (fail) throw new Error("status unavailable")
        return snapshot(provider({ providerID: "acme", active: 3, max: 4 }))
      },
      events: {
        on: () => () => {},
      },
    }
    const seen: Array<StatusSnapshot | null> = []

    const unsubscribe = subscribeStatus(
      () => client,
      (next) => {
        seen.push(next)
      },
      { refetchIntervalMs: 10 },
    )
    await new Promise((resolve) => setTimeout(resolve, 25))
    fail = false
    await new Promise((resolve) => setTimeout(resolve, 40))
    unsubscribe()

    expect(seen[0]).toBeNull()
    expect(seen.some((next) => next !== null)).toBe(true)
  })

  test("a throwing onChange escapes the fetch guard instead of being swallowed", async () => {
    const statusModule = new URL("../src/status.ts", import.meta.url).href
    const script = `
      let escaped = null
      process.on("unhandledRejection", (reason) => {
        escaped = reason
      })
      const { subscribeStatus } = await import(${JSON.stringify(statusModule)})
      const client = {
        status: async () => ({ providers: [] }),
        events: { on: () => () => {} },
      }
      const unsubscribe = subscribeStatus(() => client, () => {
        throw new Error("render blew up")
      })
      await new Promise((resolve) => setTimeout(resolve, 0))
      unsubscribe()
      if (escaped instanceof Error && escaped.message === "render blew up") {
        console.log("escaped")
        process.exit(0)
      }
      console.error("swallowed")
      process.exit(1)
    `
    const child = Bun.spawn([process.execPath, "-e", script], { stdout: "pipe", stderr: "pipe" })
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(child.stdout).text(),
      new Response(child.stderr).text(),
      child.exited,
    ])

    expect(exitCode).toBe(0)
    expect(stdout.trim()).toBe("escaped")
    expect(stderr).not.toContain("swallowed")
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
      if (next) seen.push(next)
    })
    unsubscribe()
    resolveStatus(snapshot(provider({ providerID: "acme", active: 1, queued: 0, max: 4 })))
    await settle()

    expect(seen).toEqual([])
  })

  test("drops an older snapshot that resolves after a newer one", async () => {
    const pending: Array<(value: StatusSnapshot) => void> = []
    let fire: () => void | Promise<void> = () => {}
    const client: StatusClient = {
      status: () =>
        new Promise<StatusSnapshot>((resolve) => {
          pending.push(resolve)
        }),
      events: {
        on: (_name, handler) => {
          fire = handler
          return () => {}
        },
      },
    }
    const seen: number[] = []

    const unsubscribe = subscribeStatus(() => client, (next) => {
      seen.push(present(next).providers[0].active)
    })

    expect(pending.length).toBe(1)
    await fire()
    expect(pending.length).toBe(2)

    pending[1](snapshot(provider({ providerID: "acme", active: 2, queued: 0, max: 4 })))
    await settle()
    pending[0](snapshot(provider({ providerID: "acme", active: 1, queued: 0, max: 4 })))
    await settle()

    expect(seen).toEqual([2])
    unsubscribe()
  })
})
