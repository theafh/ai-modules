import { describe, expect, test } from "bun:test"
import { FifoLimiter } from "../src/limiter.js"

describe("FifoLimiter", () => {
  test("serializes at max 1 in FIFO order", async () => {
    const limiter = new FifoLimiter(1)
    const order: number[] = []

    const first = await limiter.acquire()
    const secondPromise = limiter.acquire().then((slot) => {
      order.push(2)
      return slot
    })
    const thirdPromise = limiter.acquire().then((slot) => {
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

    const first = await limiter.acquire()
    const second = await limiter.acquire()
    const thirdPromise = limiter.acquire().then((slot) => {
      order.push("third")
      return slot
    })
    const fourthPromise = limiter.acquire().then((slot) => {
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

    const first = await limiter.acquire()
    const controller = new AbortController()
    const cancelled = limiter.acquire(controller.signal)
    const nextPromise = limiter.acquire().then((slot) => {
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

    await expect(limiter.acquire(controller.signal)).rejects.toThrow("aborted")
    expect(limiter.activeCount).toBe(0)
  })

  test("double release is idempotent", async () => {
    const limiter = new FifoLimiter(1)
    const slot = await limiter.acquire()

    slot.release()
    slot.release()

    expect(limiter.activeCount).toBe(0)
  })

  test("rejects an invalid maximum", () => {
    expect(() => new FifoLimiter(0)).toThrow("positive integer")
    expect(() => new FifoLimiter(1.5)).toThrow("positive integer")
  })
})
