import { describe, expect, test } from "bun:test"
import os from "node:os"
import {
  SubagentGate,
  extractSessionID,
  freeMemoryGBFromVmStat,
  hostCapacity,
  readFreeMemoryGB,
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

const APPLE_SILICON_VM_STAT = [
  "Mach Virtual Memory Statistics: (page size of 16384 bytes)",
  "Pages free:                                    100.",
  "Pages active:                                  500.",
  "Pages inactive:                                200.",
  "Pages wired down:                              300.",
  "",
].join("\n")

const FOUR_KIB_VM_STAT = [
  "Mach Virtual Memory Statistics: (page size of 4096 bytes)",
  "Pages free:                                    100.",
  "Pages inactive:                                200.",
  "",
].join("\n")

const HEADERLESS_VM_STAT = [
  "Pages free:                                    100.",
  "Pages inactive:                                200.",
  "",
].join("\n")

describe("freeMemoryGBFromVmStat", () => {
  test("uses the 16384-byte page size the capture header reports", () => {
    expect(freeMemoryGBFromVmStat(APPLE_SILICON_VM_STAT, 4096)).toBe((300 * 16384) / 1024 ** 3)
  })

  test("uses the 4096-byte page size the capture header reports", () => {
    expect(freeMemoryGBFromVmStat(FOUR_KIB_VM_STAT, 16384)).toBe((300 * 4096) / 1024 ** 3)
  })

  test("uses the injected fallback rather than assuming 4096 when the header is absent", () => {
    expect(freeMemoryGBFromVmStat(HEADERLESS_VM_STAT, 65536)).toBe((300 * 65536) / 1024 ** 3)
  })
})

describe("readFreeMemoryGB", () => {
  test("reads the page size from the vm_stat header", () => {
    const calls: string[] = []
    const value = readFreeMemoryGB({
      platform: "darwin",
      run: (file) => {
        calls.push(file)
        return APPLE_SILICON_VM_STAT
      },
    })

    expect(value).toBe((300 * 16384) / 1024 ** 3)
    // The header answered, so sysctl was never needed.
    expect(calls).toEqual(["vm_stat"])
  })

  test("asks sysctl for the page size when the capture has no header", () => {
    const value = readFreeMemoryGB({
      platform: "darwin",
      run: (file, args) => {
        if (file === "vm_stat") return HEADERLESS_VM_STAT
        expect(file).toBe("sysctl")
        expect(args).toEqual(["-n", "hw.pagesize"])
        return "16384\n"
      },
    })

    expect(value).toBe((300 * 16384) / 1024 ** 3)
  })

  test("falls back to os.freemem() when vm_stat throws", () => {
    const expected = os.freemem() / 1024 ** 3
    const value = readFreeMemoryGB({
      platform: "darwin",
      run: () => {
        throw new Error("vm_stat is unavailable")
      },
    })

    expect(value).toBeCloseTo(expected, 1)
  })

  test("falls back to os.freemem() when the capture carries no page lines", () => {
    const headerOnly = "Mach Virtual Memory Statistics: (page size of 16384 bytes)\n"
    // The helper alone measures nothing here, and a 0 GiB reading would pin
    // `hostCapacity` to a single child session on a healthy host.
    expect(freeMemoryGBFromVmStat(headerOnly, 16384)).toBe(0)

    const expected = os.freemem() / 1024 ** 3
    const value = readFreeMemoryGB({ platform: "darwin", run: () => headerOnly })

    expect(value).toBeGreaterThan(0)
    expect(Math.abs(value - expected)).toBeLessThan(1)
  })

  test("falls back to os.freemem() when a page line carries no parseable count", () => {
    // The page line is present but its count is missing, so the guard's value
    // is 0 and a line-presence test alone would return it.
    const unparseable = [
      "Mach Virtual Memory Statistics: (page size of 16384 bytes)",
      "Pages free: .",
      "",
    ].join("\n")
    expect(freeMemoryGBFromVmStat(unparseable, 16384)).toBe(0)

    const expected = os.freemem() / 1024 ** 3
    const value = readFreeMemoryGB({ platform: "darwin", run: () => unparseable })

    expect(value).toBeGreaterThan(0)
    expect(Math.abs(value - expected)).toBeLessThan(1)
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

describe("SubagentGate fairness and recheck", () => {
  const RECHECK_WAIT_MS = 2_500

  function wait(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms))
  }

  test("a launch behind a waiter joins the queue while the older waiter is served", async () => {
    let metrics: HostMetrics = { cores: 4, load1: 3, freeMemoryGB: 10 }
    const gate = new SubagentGate({ max: 2, hostAware: true, probe: () => metrics })

    const held = await gate.acquire("parent")
    held.bind("ses_a")
    expect(gate.capacity()).toBe(1)

    let olderAdmitted = false
    const older = gate.acquire("parent").then((permit) => {
      olderAdmitted = true
      return permit
    })
    await tick()
    expect(olderAdmitted).toBe(false)
    expect(gate.status()).toEqual({ live: 1, queued: 1, max: 2, capacity: 1 })

    // One slot frees on the host while a new launch arrives. The new launch
    // must queue behind the older waiter rather than overtake it.
    metrics = { cores: 4, load1: 2, freeMemoryGB: 10 }
    let newerAdmitted = false
    const newer = gate.acquire("parent").then((permit) => {
      newerAdmitted = true
      return permit
    })
    await tick()

    expect(olderAdmitted).toBe(true)
    expect(newerAdmitted).toBe(false)
    expect(gate.liveCount).toBe(2)

    const olderPermit = await older
    expect(olderPermit).toBeDefined()
    gate.cancelAll()
    await newer.catch(() => undefined)
    olderPermit.release()
    held.release()
  })

  test("the recheck admits a queued launch when host capacity rises", async () => {
    let metrics: HostMetrics = { cores: 4, load1: 3, freeMemoryGB: 10 }
    const gate = new SubagentGate({ max: 4, hostAware: true, probe: () => metrics })

    const held = await gate.acquire("parent")
    held.bind("ses_a")

    const queued = gate.acquire("parent")
    await tick()
    expect(gate.queuedCount).toBe(1)
    expect(gate.recheckArmed).toBe(true)

    // No permit is released; only the host frees capacity.
    metrics = { cores: 4, load1: 0, freeMemoryGB: 10 }
    const permit = await Promise.race([
      queued,
      wait(RECHECK_WAIT_MS).then(() => {
        throw new Error("the recheck did not admit the queued launch")
      }),
    ])

    expect(gate.liveCount).toBe(2)
    expect(gate.queuedCount).toBe(0)
    expect(gate.recheckArmed).toBe(false)

    permit.release()
    held.release()
    expect(gate.liveCount).toBe(0)
  })

  test("a drain queues a launch that capacity would otherwise admit", async () => {
    const gate = new SubagentGate({ max: 2 })
    gate.beginDrain()

    let admitted = false
    const queued = gate.acquire("parent").then((permit) => {
      admitted = true
      return permit
    })
    await tick()
    expect(admitted).toBe(false)
    expect(gate.queuedCount).toBe(1)
    expect(gate.liveCount).toBe(0)

    gate.endDrain()
    const permit = await queued
    expect(admitted).toBe(true)
    expect(gate.liveCount).toBe(1)
    permit.release()
  })

  test("a post-cancel launch settles instead of queueing on the torn-down drain", async () => {
    const gate = new SubagentGate({ max: 2, hostAware: true, probe: () => idleHost })
    gate.beginDrain()

    const queued = gate.acquire("parent")
    await tick()
    expect(gate.queuedCount).toBe(1)

    gate.cancelAll()
    await queued.catch(() => undefined)
    expect(gate.recheckArmed).toBe(false)

    const permit = await Promise.race([
      gate.acquire("parent"),
      wait(RECHECK_WAIT_MS).then(() => {
        throw new Error("the post-cancel launch hung")
      }),
    ])
    expect(gate.liveCount).toBe(1)
    expect(gate.recheckArmed).toBe(false)
    permit.release()
  })

  test("the last waiter's abort clears the recheck timer", async () => {
    const gate = new SubagentGate({
      max: 1,
      hostAware: true,
      probe: () => ({ cores: 4, load1: 3, freeMemoryGB: 10 }),
    })
    const held = await gate.acquire("parent")
    held.bind("ses_a")

    const controller = new AbortController()
    const queued = gate.acquire("parent", controller.signal).catch((error: unknown) => error)
    await tick()
    expect(gate.queuedCount).toBe(1)
    expect(gate.recheckArmed).toBe(true)

    controller.abort()
    const error = await queued
    expect(error).toBeInstanceOf(Error)
    expect((error as Error).name).toBe("AbortError")
    expect(gate.queuedCount).toBe(0)
    expect(gate.recheckArmed).toBe(false)
    held.release()
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
