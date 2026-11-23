import { describe, expect, test } from "bun:test"
import type { ProviderStatus, StatusSnapshot } from "../src/rpc.js"
import {
  blockedLabel,
  loadColor,
  providerRows,
  subagentRow,
  subscribeStatus,
  type StatusClient,
} from "../src/status.js"

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
    ceiling: overrides.ceiling ?? max,
    sessions: overrides.sessions ?? 0,
    utilization: overrides.utilization ?? (max === 0 ? 0 : active / max),
    demand: overrides.demand ?? (max === 0 ? 0 : (active + queued) / max),
    tokensAvailable: overrides.tokensAvailable ?? 0,
    tokensCapacity: overrides.tokensCapacity ?? 0,
    tokensPausedUntil: overrides.tokensPausedUntil ?? 0,
    blocked: overrides.blocked ?? { slots: 0, context: 0, budget: 0, breaker: 0, draining: 0 },
    breaker: overrides.breaker ?? "closed",
    breakerRetryAfterMs: overrides.breakerRetryAfterMs ?? 0,
    stalls: overrides.stalls ?? 0,
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
    const rows = providerRows(snapshot(provider({ providerID: "acme", active: 2, queued: 1, max: 4, sessions: 2 })))

    expect(rows).toEqual([
      {
        providerID: "acme",
        active: 2,
        queued: 1,
        max: 4,
        ceiling: 4,
        sessions: 2,
        total: 3,
        slotLabel: "2/4",
        queueLabel: "+1",
        title: "2 of 4 slots in use by 2 sessions · 1 waiting",
        utilization: "50%",
        demand: "75%",
        utilizationColor: loadColor(50),
        demandColor: loadColor(75),
        tokensAvailable: 0,
        tokensCapacity: 0,
        tokensPausedUntil: 0,
        blocked: { slots: 0, context: 0, budget: 0, breaker: 0, draining: 0 },
        blockedLabel: "",
        tokensLabel: "",
        tokensColor: "",
      },
    ])
  })

  test("formats a token budget compactly and colours it by the remaining share", () => {
    const [row] = providerRows(
      snapshot(provider({ providerID: "acme", tokensAvailable: 300_000, tokensCapacity: 400_000 })),
    )

    expect(row.tokensLabel).toBe("300k / 400k")
    expect(row.tokensColor).toBe(loadColor(75))
  })

  test("renders no token label when the provider has no budget", () => {
    const [row] = providerRows(snapshot(provider({ providerID: "acme" })))
    expect(row.tokensLabel).toBe("")
    expect(row.tokensColor).toBe("")
  })

  test("colors the active count by utilization and the combined count by demand", () => {
    const [row] = providerRows(snapshot(provider({ providerID: "acme", active: 2, queued: 1, max: 4 })))

    expect(row.total).toBe(3)
    expect(row.utilizationColor).toBe(loadColor(50))
    expect(row.demandColor).toBe(loadColor(75))
  })

  test("names the session count, the waiting gate, and the token allowance in the bar tooltip", () => {
    const [row] = providerRows(
      snapshot(
        provider({
          providerID: "acme",
          active: 1,
          queued: 2,
          max: 8,
          sessions: 1,
          blocked: { slots: 2, context: 0, budget: 0, breaker: 0, draining: 0 },
          tokensAvailable: 500_000,
          tokensCapacity: 500_000,
        }),
      ),
    )

    expect(row.title).toBe(
      "1 of 8 slots in use by 1 session · 2 waiting on slots 2 · 500k new-context tokens",
    )
    expect(row.slotLabel).toBe("1/8")
    expect(row.queueLabel).toBe("+2")
  })

  test("drops the queue badge when nothing waits", () => {
    const [row] = providerRows(
      snapshot(provider({ providerID: "acme", active: 2, max: 4, sessions: 2 })),
    )

    expect(row.queueLabel).toBe("")
    expect(row.title).toBe("2 of 4 slots in use by 2 sessions")
  })

  test("treats a snapshot from an older server as zero sessions", () => {
    const { sessions: _omitted, ...legacy } = provider({ providerID: "acme", active: 1, max: 2 })

    const [row] = providerRows(snapshot(legacy))

    expect(row.sessions).toBe(0)
    expect(row.title).toBe("1 of 2 slots in use by 0 sessions")
  })
})

describe("loadColor", () => {
  test("anchors the eight scale points from dark green to magenta", () => {
    expect(loadColor(0)).toBe("hsl(145 60% 28%)")
    expect(loadColor(100)).toBe("hsl(120 60% 60%)")
    expect(loadColor(150)).toBe("hsl(60 85% 70%)")
    expect(loadColor(200)).toBe("hsl(32 95% 55%)")
    expect(loadColor(250)).toBe("hsl(12 90% 68%)")
    expect(loadColor(300)).toBe("hsl(0 70% 35%)")
    expect(loadColor(350)).toBe("hsl(-24 75% 42%)")
    expect(loadColor(400)).toBe("hsl(-40 70% 30%)")
  })

  test("warms continuously as the load climbs between anchors", () => {
    const hue = (percent: number): number => Number(loadColor(percent).match(/^hsl\((-?\d+)/)?.[1])

    expect(hue(0)).toBeGreaterThan(hue(50))
    expect(hue(50)).toBeGreaterThan(hue(100))
    expect(hue(100)).toBeGreaterThan(hue(125))
    expect(hue(125)).toBeGreaterThan(hue(150))
    expect(hue(150)).toBeGreaterThan(hue(175))
    expect(hue(175)).toBeGreaterThan(hue(200))
    expect(hue(200)).toBeGreaterThan(hue(225))
    expect(hue(225)).toBeGreaterThan(hue(250))
    expect(hue(250)).toBeGreaterThan(hue(275))
    expect(hue(275)).toBeGreaterThan(hue(300))
    expect(hue(300)).toBeGreaterThan(hue(325))
    expect(hue(325)).toBeGreaterThan(hue(350))
    expect(hue(350)).toBeGreaterThan(hue(375))
    expect(hue(375)).toBeGreaterThan(hue(400))
  })

  test("holds magenta past 400 and treats a negative or missing load as zero", () => {
    expect(loadColor(450)).toBe(loadColor(400))
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

describe("blockedLabel", () => {
  test("names only the gates holding a request back", () => {
    expect(blockedLabel({ slots: 2, context: 0, budget: 1, breaker: 0, draining: 0 })).toBe(
      "slots 2 · budget 1",
    )
    expect(blockedLabel({ slots: 0, context: 0, budget: 0, breaker: 0, draining: 0 })).toBe("")
  })
})

describe("subagentRow", () => {
  test("renders the live and waiting counts", () => {
    expect(subagentRow({ live: 6, calling: 4, queued: 2, max: 8, capacity: 8 })).toEqual({
      live: 6,
      calling: 4,
      queued: 2,
      max: 8,
      capacity: 8,
      label: "6/8 live · 4 calling · 2 waiting",
    })
  })

  test("shows the host-limited capacity when it is below the ceiling", () => {
    expect(subagentRow({ live: 2, calling: 1, queued: 1, max: 8, capacity: 3 })?.label).toBe(
      "2/3 of 8 live · 1 calling · 1 waiting",
    )
  })

  test("omits the waiting part when nothing waits", () => {
    expect(subagentRow({ live: 8, calling: 7, queued: 0, max: 64, capacity: 64 })?.label).toBe(
      "8/64 live · 7 calling",
    )
  })

  test("is absent when fan-out gating is off", () => {
    expect(subagentRow(undefined)).toBeUndefined()
  })
})
