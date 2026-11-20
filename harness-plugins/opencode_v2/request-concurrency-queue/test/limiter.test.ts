import { describe, expect, test } from "bun:test"
import { FifoLimiter, type LimiterTransition } from "../src/limiter.js"

/** Collects every notification call and the flattened transitions it carried. */
function recordingLimiter(max: number): {
  limiter: FifoLimiter
  calls: LimiterTransition[][]
  changes: LimiterTransition[]
} {
  const calls: LimiterTransition[][] = []
  const changes: LimiterTransition[] = []
  const limiter = new FifoLimiter(max, (transitions) => {
    calls.push([...transitions])
    changes.push(...transitions)
  })
  return { limiter, calls, changes }
}

describe("FifoLimiter", () => {
  test("serializes at max 1 in FIFO order", async () => {
    const limiter = new FifoLimiter(1)
    const order: number[] = []

    const first = await limiter.acquire("a")
    const secondPromise = limiter.acquire("b").then((slot) => {
      order.push(2)
      return slot
    })
    const thirdPromise = limiter.acquire("c").then((slot) => {
      order.push(3)
      return slot
    })

    await Promise.resolve()
    expect(limiter.activeCount).toBe(1)
    expect(limiter.queuedCount).toBe(2)

    first.release()
    const second = await secondPromise
    expect(order).toEqual([2])
    expect(limiter.activeCount).toBe(1)

    second.release()
    const third = await thirdPromise
    expect(order).toEqual([2, 3])

    third.release()
    expect(limiter.activeCount).toBe(0)
    expect(limiter.queuedCount).toBe(0)
  })

  test("allows max 2 and serves the oldest waiter first", async () => {
    const limiter = new FifoLimiter(2)
    const order: string[] = []

    const first = await limiter.acquire("first")
    const second = await limiter.acquire("second")
    const thirdPromise = limiter.acquire("third").then((slot) => {
      order.push("third")
      return slot
    })
    const fourthPromise = limiter.acquire("fourth").then((slot) => {
      order.push("fourth")
      return slot
    })

    await Promise.resolve()
    expect(limiter.activeCount).toBe(2)
    expect(limiter.queuedCount).toBe(2)

    first.release()
    const third = await thirdPromise
    expect(order).toEqual(["third"])

    second.release()
    const fourth = await fourthPromise
    expect(order).toEqual(["third", "fourth"])

    third.release()
    fourth.release()
    expect(limiter.activeCount).toBe(0)
  })

  test("cancels a queued waiter and preserves the order of the rest", async () => {
    const limiter = new FifoLimiter(1)
    const order: string[] = []

    const first = await limiter.acquire("first")
    const controller = new AbortController()
    const cancelled = limiter.acquire("cancelled", controller.signal)
    const nextPromise = limiter.acquire("next").then((slot) => {
      order.push("next")
      return slot
    })

    controller.abort()
    await expect(cancelled).rejects.toThrow("aborted")
    expect(limiter.queuedCount).toBe(1)

    first.release()
    const next = await nextPromise
    expect(order).toEqual(["next"])

    next.release()
    expect(limiter.activeCount).toBe(0)
  })

  test("rejects an already aborted signal", async () => {
    const limiter = new FifoLimiter(1)
    const controller = new AbortController()
    controller.abort()

    await expect(limiter.acquire("a", controller.signal)).rejects.toThrow("aborted")
    expect(limiter.activeCount).toBe(0)
  })

  test("double release is idempotent", async () => {
    const limiter = new FifoLimiter(1)
    const slot = await limiter.acquire("a")

    slot.release()
    slot.release()

    expect(limiter.activeCount).toBe(0)
  })

  test("rejects an invalid maximum", () => {
    expect(() => new FifoLimiter(0)).toThrow("positive integer")
    expect(() => new FifoLimiter(1.5)).toThrow("positive integer")
  })
})

describe("FifoLimiter transitions", () => {
  test("a free-slot acquire reports one acquired transition for its session", async () => {
    const { limiter, changes } = recordingLimiter(2)

    const slot = await limiter.acquire("a")
    expect(changes).toEqual([{ kind: "acquired", sessionID: "a" }])

    slot.release()
  })

  test("joining the wait queue reports one queued transition for its session", async () => {
    const { limiter, changes } = recordingLimiter(1)
    const held = await limiter.acquire("a")
    changes.length = 0

    const waiting = limiter.acquire("b")
    expect(changes).toEqual([{ kind: "queued", sessionID: "b" }])

    held.release()
    await waiting
  })

  test("a queued-request abort reports one dequeued transition, never released or acquired", async () => {
    const { limiter, changes } = recordingLimiter(1)
    const held = await limiter.acquire("a")
    const controller = new AbortController()
    const waiting = limiter.acquire("b", controller.signal)
    changes.length = 0

    controller.abort()
    await expect(waiting).rejects.toThrow("aborted")
    expect(changes).toEqual([{ kind: "dequeued", sessionID: "b" }])

    held.release()
  })

  test("a release with no waiter reports one released transition", async () => {
    const { limiter, changes } = recordingLimiter(1)
    const slot = await limiter.acquire("a")
    changes.length = 0

    slot.release()
    expect(changes).toEqual([{ kind: "released", sessionID: "a" }])
  })

  test("a release handoff reports one call with released then acquired, one entry each", async () => {
    const { limiter, calls } = recordingLimiter(1)
    const held = await limiter.acquire("a")
    const waiting = limiter.acquire("b")
    calls.length = 0

    held.release()
    await waiting

    expect(calls).toEqual([
      [
        { kind: "released", sessionID: "a" },
        { kind: "acquired", sessionID: "b" },
      ],
    ])
  })
})

describe("FifoLimiter cancellation", () => {
  test("cancelSession removes that session's waiters and leaves the rest", async () => {
    const limiter = new FifoLimiter(1)
    const held = await limiter.acquire("a")

    let bRejected = false
    const b = limiter.acquire("b").catch(() => {
      bRejected = true
    })
    const cPromise = limiter.acquire("c")
    await Promise.resolve()
    expect(limiter.queuedCount).toBe(2)

    expect(limiter.cancelSession("b")).toBe(1)
    await b
    expect(bRejected).toBe(true)
    expect(limiter.queuedCount).toBe(1)

    held.release()
    const c = await cPromise
    expect(c).toBeDefined()
  })

  test("cancelSession ignores a session that holds a slot", async () => {
    const limiter = new FifoLimiter(1)
    const held = await limiter.acquire("a")
    expect(limiter.cancelSession("a")).toBe(0)
    expect(limiter.activeCount).toBe(1)
    held.release()
  })

  test("cancelAll rejects every waiter", async () => {
    const limiter = new FifoLimiter(1)
    const held = await limiter.acquire("a")
    let rejected = 0
    const waiters = ["b", "c", "d"].map((sessionID) =>
      limiter.acquire(sessionID).catch(() => {
        rejected += 1
      }),
    )
    await Promise.resolve()
    expect(limiter.cancelAll()).toBe(3)
    await Promise.all(waiters)
    expect(rejected).toBe(3)
    expect(limiter.queuedCount).toBe(0)
    held.release()
  })

  test("a cancelled waiter is never dispatched", async () => {
    const limiter = new FifoLimiter(1)
    const held = await limiter.acquire("a")
    let dispatched = false
    const queued = limiter.acquire("b").then(
      () => {
        dispatched = true
      },
      () => {},
    )
    await Promise.resolve()
    limiter.cancelSession("b")
    held.release()
    await queued
    expect(dispatched).toBe(false)
  })
})

describe("FifoLimiter adaptive maximum", () => {
  test("raising the maximum serves a waiting request at once", async () => {
    const limiter = new FifoLimiter(1)
    const held = await limiter.acquire("a")

    let bAcquired = false
    const bPromise = limiter.acquire("b").then(() => {
      bAcquired = true
    })
    await Promise.resolve()
    expect(bAcquired).toBe(false)

    limiter.setMax(2)
    await bPromise
    expect(bAcquired).toBe(true)
    expect(limiter.activeCount).toBe(2)
    held.release()
  })

  test("lowering the maximum admits nothing until active drops below it", async () => {
    const limiter = new FifoLimiter(4)
    const slots = await Promise.all(["a", "b", "c", "d"].map((sessionID) => limiter.acquire(sessionID)))

    limiter.setMax(2)
    let nextAcquired = false
    const next = limiter.acquire("next").then(() => {
      nextAcquired = true
    })
    await Promise.resolve()

    slots[0].release()
    await Promise.resolve()
    expect(nextAcquired).toBe(false)

    slots[1].release()
    await Promise.resolve()
    expect(nextAcquired).toBe(false)

    slots[2].release()
    await next
    expect(nextAcquired).toBe(true)
    expect(limiter.activeCount).toBe(2)
  })

  test("rejects a maximum below one", () => {
    const limiter = new FifoLimiter(1)
    expect(() => limiter.setMax(0)).toThrow("positive integer")
  })
})
