import { describe, expect, test } from "bun:test"
import type { StatusSnapshot } from "../src/rpc.js"
import { createSessionDescriber, type SessionInfoLike } from "../src/sessions.js"

function snapshot(activeSessionIDs: string[]): StatusSnapshot {
  return {
    providers: [
      {
        providerID: "acme",
        active: activeSessionIDs.length,
        queued: 0,
        max: 8,
        ceiling: 8,
        sessions: activeSessionIDs.length,
        activeSessionIDs,
        utilization: 0,
        demand: 0,
        tokensAvailable: 0,
        tokensCapacity: 0,
        tokensPausedUntil: 0,
        blocked: { slots: 0, context: 0, budget: 0, breaker: 0, draining: 0 },
        breaker: "closed",
        breakerRetryAfterMs: 0,
        stalls: 0,
      },
    ],
    transitions: [],
  }
}

function info(overrides: Partial<SessionInfoLike> = {}): SessionInfoLike {
  return {
    title: "Implement http response contract",
    agent: "general",
    location: { directory: "/work/no-cms" },
    ...overrides,
  }
}

describe("createSessionDescriber", () => {
  test("attaches a title, agent, and project to each in-flight session", async () => {
    const lookups: string[] = []
    const describe = createSessionDescriber(async (sessionID) => {
      lookups.push(sessionID)
      return info()
    })

    const described = await describe(snapshot(["ses_a", "ses_b"]))

    expect(lookups.sort()).toEqual(["ses_a", "ses_b"])
    expect(described.sessionDetails).toEqual([
      { sessionID: "ses_a", title: "Implement http response contract", agent: "general", directory: "/work/no-cms" },
      { sessionID: "ses_b", title: "Implement http response contract", agent: "general", directory: "/work/no-cms" },
    ])
  })

  test("lists a session by its ID when the lookup fails", async () => {
    const errors: string[] = []
    const describe = createSessionDescriber(
      async () => {
        throw new Error("no such session")
      },
      { onError: (sessionID) => errors.push(sessionID) },
    )

    const described = await describe(snapshot(["ses_gone"]))

    expect(described.sessionDetails).toEqual([{ sessionID: "ses_gone" }])
    expect(errors).toEqual(["ses_gone"])
  })

  test("reuses a detail within the refresh window and refetches after it", async () => {
    let clock = 0
    let calls = 0
    const describe = createSessionDescriber(
      async () => {
        calls += 1
        return info({ title: `title ${calls}` })
      },
      { ttlMs: 1_000, now: () => clock },
    )

    await describe(snapshot(["ses_a"]))
    clock = 500
    await describe(snapshot(["ses_a"]))
    expect(calls).toBe(1)

    clock = 1_500
    const refreshed = await describe(snapshot(["ses_a"]))
    expect(calls).toBe(2)
    expect(refreshed.sessionDetails?.[0].title).toBe("title 2")
  })

  test("omits fields the runtime leaves empty", async () => {
    const describe = createSessionDescriber(async () => ({}))

    const described = await describe(snapshot(["ses_a"]))

    expect(described.sessionDetails).toEqual([{ sessionID: "ses_a" }])
  })

  test("describes a session that only appears in the activity feed", async () => {
    const describe = createSessionDescriber(async () => info())
    const withFeed: StatusSnapshot = {
      ...snapshot([]),
      transitions: [
        {
          timestamp: 1,
          providerID: "acme",
          kind: "released",
          sessionID: "ses_old",
          active: 0,
          queued: 0,
        },
      ],
    }

    const described = await describe(withFeed)

    expect(described.sessionDetails).toEqual([
      { sessionID: "ses_old", title: "Implement http response contract", agent: "general", directory: "/work/no-cms" },
    ])
  })

  test("leaves a snapshot with nothing in flight untouched", async () => {
    let calls = 0
    const describe = createSessionDescriber(async () => {
      calls += 1
      return info()
    })

    const empty = snapshot([])
    const described = await describe(empty)

    expect(described).toBe(empty)
    expect(described.sessionDetails).toBeUndefined()
    expect(calls).toBe(0)
  })
})
