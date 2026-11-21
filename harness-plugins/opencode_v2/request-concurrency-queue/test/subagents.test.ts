import { describe, expect, test } from "bun:test"
import {
  SubagentGate,
  extractSessionID,
  hostCapacity,
  type HostMetrics,
} from "../src/subagents.js"

function tick(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0))
}

const idleHost: HostMetrics = { cores: 14, load1: 2, freeMemoryGB: 10 }

describe("hostCapacity", () => {
  test("allows the full ceiling on an idle host", () => {
    expect(hostCapacity(8, idleHost)).toBe(8)
  })

  test("drops to one when the load meets the core count", () => {
    expect(hostCapacity(8, { cores: 14, load1: 21.8, freeMemoryGB: 3.8 })).toBe(1)
  })

  test("subtracts load from cores", () => {
    expect(hostCapacity(8, { cores: 14, load1: 7, freeMemoryGB: 10 })).toBe(7)
    expect(hostCapacity(8, { cores: 14, load1: 6, freeMemoryGB: 10 })).toBe(8)
  })

  test("keeps a floor of one even when the host is short of memory", () => {
    expect(hostCapacity(8, { cores: 14, load1: 0, freeMemoryGB: 0.4 })).toBe(1)
  })

  test("never exceeds the configured ceiling", () => {
    expect(hostCapacity(4, { cores: 64, load1: 0, freeMemoryGB: 100 })).toBe(4)
  })
})

describe("SubagentGate", () => {
  test("admits up to the ceiling and queues the rest in FIFO order", async () => {
    const gate = new SubagentGate({ max: 1 })

    const first = await gate.acquire("parent")
    first.bind("ses_a")

    let secondAdmitted = false
    const second = gate.acquire("parent").then((permit) => {
      secondAdmitted = true
      return permit
    })
    await tick()
    expect(secondAdmitted).toBe(false)
    expect(gate.status()).toEqual({ live: 1, queued: 1, max: 1, capacity: 1 })

    gate.releaseSession("ses_a")
    const secondPermit = await second
    expect(secondAdmitted).toBe(true)
    secondPermit.release()
  })

  test("releasing an unbound permit serves the queue", async () => {
    const gate = new SubagentGate({ max: 1 })
    const pending = await gate.acquire("parent")

    let nextAdmitted = false
    const next = gate.acquire("parent").then((permit) => {
      nextAdmitted = true
      return permit
    })
    await tick()
    expect(nextAdmitted).toBe(false)

    pending.release()
    const permit = await next
    expect(nextAdmitted).toBe(true)
    permit.release()
  })

  test("a bound permit is freed only by its child session", async () => {
    const gate = new SubagentGate({ max: 1 })
    const permit = await gate.acquire("parent")
    permit.bind("ses_a")

    gate.releaseSession("ses_other")
    expect(gate.liveCount).toBe(1)

    gate.releaseSession("ses_a")
    expect(gate.liveCount).toBe(0)
  })

  test("release is idempotent", async () => {
    const gate = new SubagentGate({ max: 2 })
    const permit = await gate.acquire("parent")
    permit.bind("ses_a")
    permit.release()
    permit.release()
    expect(gate.liveCount).toBe(0)
  })

  test("cancelAll rejects waiters and frees permits", async () => {
    const gate = new SubagentGate({ max: 1 })
    const held = await gate.acquire("parent")
    held.bind("ses_a")

    let rejected = false
    const waiting = gate.acquire("parent").catch(() => {
      rejected = true
    })
    await tick()

    gate.cancelAll()
    await waiting
    expect(rejected).toBe(true)
    expect(gate.liveCount).toBe(0)
    expect(gate.queuedCount).toBe(0)
  })

  test("hostAware lowers the effective ceiling", async () => {
    const gate = new SubagentGate({
      max: 8,
      hostAware: true,
      probe: () => ({ cores: 14, load1: 12, freeMemoryGB: 8 }),
    })
    expect(gate.capacity()).toBe(2)
  })

  test("hostAware off always uses the ceiling", () => {
    const gate = new SubagentGate({
      max: 8,
      hostAware: false,
      probe: () => ({ cores: 14, load1: 100, freeMemoryGB: 0.1 }),
    })
    expect(gate.capacity()).toBe(8)
  })

  test("rejects a ceiling below one", () => {
    expect(() => new SubagentGate({ max: 0 })).toThrow("positive integer")
  })
})

describe("extractSessionID", () => {
  test("reads a top-level session ID", () => {
    expect(extractSessionID({ sessionID: "ses_a" })).toBe("ses_a")
  })

  test("reads a metadata session ID", () => {
    expect(extractSessionID({ content: [], metadata: { sessionID: "ses_b" } })).toBe("ses_b")
  })

  test("finds a session ID that is a whole nested value", () => {
    expect(extractSessionID({ content: [{ type: "text", text: "ses_c" }] })).toBe("ses_c")
  })

  test("ignores a session ID merely mentioned in prose", () => {
    // Binding to a mentioned ID would hold a slot for the wrong child.
    expect(extractSessionID({ content: [{ type: "text", text: "started ses_c" }] })).toBeUndefined()
  })

  test("prefers an explicit sessionID key over a parent ID found by the walk", () => {
    // A result may carry the parent session alongside the child's own ID, and
    // the walk follows insertion order, so the explicit key must decide.
    expect(extractSessionID({ parentID: "ses_parent", sessionID: "ses_child" })).toBe("ses_child")
    expect(extractSessionID({ parentID: "ses_parent", metadata: { sessionID: "ses_child" } })).toBe(
      "ses_child",
    )
  })

  test("returns undefined when no session ID is present", () => {
    expect(extractSessionID({ ok: true })).toBeUndefined()
    expect(extractSessionID("plain")).toBeUndefined()
    expect(extractSessionID(null)).toBeUndefined()
  })
})

describe("SubagentGate.setMax", () => {
  test("raising the ceiling serves a waiting launch", async () => {
    const gate = new SubagentGate({ max: 1 })
    const held = await gate.acquire("parent")
    held.bind("ses_a")

    let admitted = false
    const waiting = gate.acquire("parent").then((permit) => {
      admitted = true
      return permit
    })
    await tick()
    expect(admitted).toBe(false)

    gate.setMax(2)
    const permit = await waiting
    expect(admitted).toBe(true)
    expect(gate.capacity()).toBe(2)
    permit.release()
  })

  test("rejects a ceiling below one", () => {
    const gate = new SubagentGate({ max: 1 })
    expect(() => gate.setMax(0)).toThrow("positive integer")
  })
})

describe("permit lifecycle", () => {
  test("a child that ends before its permit binds does not leak the slot", async () => {
    const gate = new SubagentGate({ max: 1 })
    const permit = await gate.acquire("parent")

    // The child goes idle before the launch returns and binds.
    gate.releaseSession("ses_fast")
    permit.bind("ses_fast")

    expect(gate.liveCount).toBe(0)
  })

  test("permits handed out before cancelAll cannot corrupt the count", async () => {
    const gate = new SubagentGate({ max: 2 })
    const permit = await gate.acquire("parent")

    gate.cancelAll()
    permit.release()
    permit.bind("ses_late")

    expect(gate.liveCount).toBe(0)
  })
})
