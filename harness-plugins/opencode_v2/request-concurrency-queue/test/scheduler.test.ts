import { describe, expect, test } from "bun:test"
import { TokenBudget } from "../src/budget.js"
import { RequestScheduler } from "../src/scheduler.js"

/** Resolves true when `promise` settles before the next macrotask. */
function settled(promise: Promise<unknown>): Promise<boolean> {
  return Promise.race([
    promise.then(
      () => true,
      () => true,
    ),
    new Promise<boolean>((resolve) => setTimeout(() => resolve(false), 0)),
  ])
}

describe("RequestScheduler context cap", () => {
  test("a small request passes a large one that cannot fit", async () => {
    const scheduler = new RequestScheduler({ maxSlots: 3, contextCapacity: 1000 })

    const big = await scheduler.acquire("a", { newTokens: 0, contextTokens: 900 })
    const bigTwo = scheduler.acquire("b", { newTokens: 0, contextTokens: 900 })
    expect(await settled(bigTwo)).toBe(false)

    // The small request fits beside the first big one, even though the older
    // big request is still waiting.
    const small = await scheduler.acquire("c", { newTokens: 0, contextTokens: 50 })
    expect(scheduler.queuedCount).toBe(1)
    expect(scheduler.status().contextInFlight).toBe(950)

    small.release()
    big.release()
    const bigTwoSlot = await bigTwo
    expect(scheduler.queuedCount).toBe(0)
    bigTwoSlot.release()
    scheduler.cancelAll()
  })

  test("a single request larger than the cap still runs alone", async () => {
    const scheduler = new RequestScheduler({ maxSlots: 1, contextCapacity: 500 })
    const slot = await scheduler.acquire("a", { newTokens: 0, contextTokens: 900 })
    expect(scheduler.status().contextInFlight).toBe(900)
    slot.release()
    expect(scheduler.status().contextInFlight).toBe(0)
    scheduler.cancelAll()
  })

  test("the cap shrinks only when the breaker opens and grows back in quarters", () => {
    const scheduler = new RequestScheduler({
      maxSlots: 1,
      contextCapacity: 800_000,
      contextCeiling: 800_000,
      breaker: { threshold: 3, cooldownMs: 60_000, mode: "wait" },
    })

    // A single transient stall must not cut the width the whole fan-out uses.
    scheduler.recordStall()
    scheduler.recordStall()
    expect(scheduler.status().contextCapacity).toBe(800_000)

    scheduler.recordStall()
    expect(scheduler.status().contextCapacity).toBe(400_000)

    scheduler.recordSuccess()
    expect(scheduler.status().contextCapacity).toBe(500_000)
    scheduler.recordSuccess()
    // A quarter of the remaining gap each time, so recovery accelerates as it
    // approaches the ceiling.
    expect(scheduler.status().contextCapacity).toBe(575_000)
    scheduler.cancelAll()
  })

  test("contextCeiling 0 keeps a fixed cap through a stall", () => {
    const scheduler = new RequestScheduler({
      maxSlots: 8,
      contextCapacity: 800_000,
      contextCeiling: 0,
      breaker: { threshold: 1, cooldownMs: 1_000, mode: "wait" },
    })
    scheduler.recordStall()
    expect(scheduler.status().contextCapacity).toBe(800_000)
    scheduler.cancelAll()
  })

  test("the cap never drops below one", () => {
    const scheduler = new RequestScheduler({ maxSlots: 1, contextCapacity: 4, contextCeiling: 4 })
    scheduler.recordTimeout()
    scheduler.recordTimeout()
    scheduler.recordTimeout()
    expect(scheduler.status().contextCapacity).toBe(1)
    scheduler.cancelAll()
  })
})

describe("RequestScheduler budget lanes", () => {
  test("the reserve holds a small request only while a large one waits", async () => {
    const now = { value: 0 }
    const budget = new TokenBudget({ capacity: 1000, refillPerMinute: 60_000, now: () => now.value })
    const scheduler = new RequestScheduler({
      maxSlots: 2,
      budget,
      smallShare: 0.1,
      reserveShare: 0.25,
      agingMs: 1_000,
      now: () => now.value,
    })
    budget.spend(800) // 200 available

    // A large request is above the small threshold, so it waits for the bucket
    // rather than for the reserve.
    const large = scheduler.acquire("large", { newTokens: 400, contextTokens: 0 })
    expect(await settled(large)).toBe(false)

    // The small request behind it must leave the reserve intact.
    const small = scheduler.acquire("small", { newTokens: 50, contextTokens: 0 })
    expect(await settled(small)).toBe(false)
    expect(scheduler.queuedCount).toBe(2)

    // Once the bucket refills, the large request is served first and the small
    // one follows it, because no large request waits any more.
    now.value += 1_000
    scheduler.reconfigure({})
    const largeSlot = await large
    const smallSlot = await small
    expect(scheduler.queuedCount).toBe(0)
    largeSlot.release()
    smallSlot.release()
    scheduler.cancelAll()
  })

  test("the oldest fitting waiter is served first", async () => {
    const scheduler = new RequestScheduler({ maxSlots: 1 })
    const held = await scheduler.acquire("held", { newTokens: 0, contextTokens: 0 })

    const order: string[] = []
    const first = scheduler.acquire("first", { newTokens: 0, contextTokens: 0 }).then((slot) => {
      order.push("first")
      return slot
    })
    const second = scheduler.acquire("second", { newTokens: 0, contextTokens: 0 }).then((slot) => {
      order.push("second")
      return slot
    })
    await Promise.resolve()
    expect(order).toEqual([])

    held.release()
    const firstSlot = await first
    expect(order).toEqual(["first"])
    firstSlot.release()
    const secondSlot = await second
    expect(order).toEqual(["first", "second"])
    secondSlot.release()
    scheduler.cancelAll()
  })

  test("a cancelled session leaves the queue and never dispatches", async () => {
    const scheduler = new RequestScheduler({ maxSlots: 1 })
    const held = await scheduler.acquire("a", { newTokens: 0, contextTokens: 0 })

    let rejected = false
    const waiting = scheduler.acquire("b", { newTokens: 0, contextTokens: 0 }).catch(() => {
      rejected = true
    })
    await Promise.resolve()
    expect(scheduler.cancelSession("b")).toBe(1)
    await waiting
    expect(rejected).toBe(true)
    expect(scheduler.queuedCount).toBe(0)

    held.release()
    scheduler.cancelAll()
  })
})

describe("RequestScheduler queue deadline", () => {
  test("rejects a waiter that never gets a slot", async () => {
    const scheduler = new RequestScheduler({ maxSlots: 1, queueDeadlineMs: 20 })
    const held = await scheduler.acquire("a", { newTokens: 0, contextTokens: 0 })

    let error: Error | undefined
    await scheduler.acquire("b", { newTokens: 0, contextTokens: 0 }).catch((err) => {
      error = err
    })

    expect(error?.name).toBe("QueueTimeoutError")
    expect(error?.message).toContain("no slot within")
    expect(scheduler.queuedCount).toBe(0)
    held.release()
    scheduler.cancelAll()
  })

  test("an admitted waiter is not rejected later", async () => {
    const scheduler = new RequestScheduler({ maxSlots: 1, queueDeadlineMs: 20 })
    const held = await scheduler.acquire("a", { newTokens: 0, contextTokens: 0 })
    const waiting = scheduler.acquire("b", { newTokens: 0, contextTokens: 0 })

    held.release()
    const slot = await waiting
    await new Promise((resolve) => setTimeout(resolve, 40))

    expect(scheduler.queuedCount).toBe(0)
    expect(scheduler.activeCount).toBe(1)
    slot.release()
    scheduler.cancelAll()
  })
})

describe("RequestScheduler circuit breaker", () => {
  test("opens after the configured number of stalls and rejects new requests", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 2,
      breaker: { threshold: 2, cooldownMs: 60_000, mode: "fail" },
      now: () => now.value,
    })

    scheduler.recordStall()
    expect(scheduler.status().breaker).toBe("closed")
    scheduler.recordStall()
    expect(scheduler.status().breaker).toBe("open")
    expect(scheduler.status().breakerRetryAfterMs).toBe(60_000)

    await expect(scheduler.acquire("a", { newTokens: 0, contextTokens: 0 })).rejects.toThrow(
      "provider circuit open",
    )
    scheduler.cancelAll()
  })

  test("opening rejects the requests already queued", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 1,
      breaker: { threshold: 1, cooldownMs: 60_000, mode: "fail" },
      now: () => now.value,
    })
    const held = await scheduler.acquire("a", { newTokens: 0, contextTokens: 0 })

    let rejected = false
    const queued = scheduler.acquire("b", { newTokens: 0, contextTokens: 0 }).catch(() => {
      rejected = true
    })
    await Promise.resolve()
    expect(scheduler.queuedCount).toBe(1)

    scheduler.recordStall()
    await queued
    expect(rejected).toBe(true)
    expect(scheduler.queuedCount).toBe(0)

    held.release()
    scheduler.cancelAll()
  })

  test("half-open admits one probe, and a success closes the circuit", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 2,
      breaker: { threshold: 1, cooldownMs: 1_000, mode: "fail" },
      now: () => now.value,
    })
    scheduler.recordStall()
    expect(scheduler.status().breaker).toBe("open")

    now.value = 1_000
    expect(scheduler.status().breaker).toBe("half-open")

    const probe = await scheduler.acquire("probe", { newTokens: 0, contextTokens: 0 })
    // A second request queues behind the probe instead of failing, so a
    // recovery never turns the rest of a fan-out into errors.
    let otherAdmitted = false
    const other = scheduler.acquire("other", { newTokens: 0, contextTokens: 0 }).then((slot) => {
      otherAdmitted = true
      return slot
    })
    expect(await settled(other)).toBe(false)
    expect(scheduler.queuedCount).toBe(1)

    scheduler.recordSuccess()
    expect(scheduler.status().breaker).toBe("closed")
    probe.release()

    const otherSlot = await other
    expect(otherAdmitted).toBe(true)
    otherSlot.release()
    scheduler.cancelAll()
  })

  test("a stalled probe reopens the circuit", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 2,
      breaker: { threshold: 2, cooldownMs: 1_000, mode: "fail" },
      now: () => now.value,
    })
    scheduler.recordStall()
    scheduler.recordStall()
    now.value = 1_000

    const probe = await scheduler.acquire("probe", { newTokens: 0, contextTokens: 0 })
    scheduler.recordStall()

    expect(scheduler.status().breaker).toBe("open")
    expect(scheduler.status().breakerRetryAfterMs).toBe(1_000)
    probe.release()
    scheduler.cancelAll()
  })

  test("wait mode holds the request until the cooldown ends", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 2,
      breaker: { threshold: 1, cooldownMs: 1_000, mode: "wait" },
      now: () => now.value,
    })
    scheduler.recordStall()

    let admitted = false
    const waiting = scheduler.acquire("a", { newTokens: 0, contextTokens: 0 }).then((slot) => {
      admitted = true
      return slot
    })
    await new Promise((resolve) => setTimeout(resolve, 5))
    expect(admitted).toBe(false)

    now.value = 1_000
    scheduler.cancelAll()
    await waiting.catch(() => {})
  })

  test("a success resets the stall count", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 1,
      breaker: { threshold: 2, cooldownMs: 60_000, mode: "fail" },
      now: () => now.value,
    })
    scheduler.recordStall()
    scheduler.recordSuccess()
    scheduler.recordStall()

    expect(scheduler.status().breaker).toBe("closed")
    expect(scheduler.status().stalls).toBe(1)
    scheduler.cancelAll()
  })
})

describe("half-open probe recovery", () => {
  test("a probe that ends without a verdict does not wedge the circuit", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 2,
      breaker: { threshold: 1, cooldownMs: 1_000, mode: "fail" },
      now: () => now.value,
    })

    scheduler.recordStall()
    now.value = 1_000

    // The probe is admitted, then the session goes idle before any response is
    // recorded: no recordSuccess and no recordStall.
    const probe = await scheduler.acquire("probe", { newTokens: 0, contextTokens: 0 })
    probe.release()

    now.value = 60_000
    const next = await scheduler.acquire("next", { newTokens: 0, contextTokens: 0 })
    expect(next).toBeDefined()
    next.release()
    scheduler.cancelAll()
  })

  test("a second request queues behind the probe instead of failing", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 4,
      breaker: { threshold: 1, cooldownMs: 1_000, mode: "fail" },
      now: () => now.value,
    })
    scheduler.recordStall()
    now.value = 1_000

    const probe = await scheduler.acquire("probe", { newTokens: 0, contextTokens: 0 })
    const other = scheduler.acquire("other", { newTokens: 0, contextTokens: 0 })
    expect(await settled(other)).toBe(false)

    probe.release()
    const otherSlot = await other
    expect(otherSlot).toBeDefined()
    otherSlot.release()
    scheduler.cancelAll()
  })

  test("a probe that never reports back stops blocking after its lease", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 4,
      breaker: { threshold: 1, cooldownMs: 1_000, mode: "fail" },
      now: () => now.value,
    })
    scheduler.recordStall()
    now.value = 1_000

    const probe = await scheduler.acquire("probe", { newTokens: 0, contextTokens: 0 })
    // The probe hangs and is never released.
    now.value = 1_000 + 400_000

    const next = await scheduler.acquire("next", { newTokens: 0, contextTokens: 0 })
    expect(next).toBeDefined()
    next.release()
    probe.release()
    scheduler.cancelAll()
  })
})

describe("half-open probe assignment", () => {
  test("a budget-only waiter is admitted and the slot waiter takes the probe", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 2,
      breaker: { threshold: 1, cooldownMs: 1_000, mode: "wait" },
      now: () => now.value,
    })
    scheduler.recordStall()

    // The auxiliary request waits out the cooldown without taking a slot.
    const auxiliary = scheduler.acquireBudget("aux", { newTokens: 0, contextTokens: 0 })
    expect(await settled(auxiliary)).toBe(false)
    expect(scheduler.queuedCount).toBe(1)

    // The cooldown ends and the budget-only waiter is admitted; it takes no
    // slot and, with no probe in flight, must not become the probe.
    now.value = 1_000
    scheduler.reconfigure({})
    const auxiliarySlot = await auxiliary
    expect(scheduler.activeCount).toBe(0)
    expect(scheduler.queuedCount).toBe(0)

    // The first slot-holding request therefore becomes the probe and is
    // admitted. A second one queues behind it, which only happens when the
    // slot waiter, not the auxiliary request, holds the probe.
    const probe = await scheduler.acquire("probe", { newTokens: 0, contextTokens: 0 })
    expect(scheduler.activeCount).toBe(1)
    const other = scheduler.acquire("other", { newTokens: 0, contextTokens: 0 })
    expect(await settled(other)).toBe(false)
    expect(scheduler.queuedCount).toBe(1)

    probe.release()
    const otherSlot = await other
    otherSlot.release()
    auxiliarySlot.release()
    scheduler.cancelAll()
  })

  test("a budget-only waiter queues behind a slot probe in flight", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 2,
      breaker: { threshold: 1, cooldownMs: 1_000, mode: "wait" },
      now: () => now.value,
    })
    scheduler.recordStall()
    now.value = 1_000

    const probe = await scheduler.acquire("probe", { newTokens: 0, contextTokens: 0 })
    const auxiliary = scheduler.acquireBudget("aux", { newTokens: 0, contextTokens: 0 })
    expect(await settled(auxiliary)).toBe(false)
    expect(scheduler.queuedCount).toBe(1)

    probe.release()
    const auxiliarySlot = await auxiliary
    expect(auxiliarySlot).toBeDefined()
    auxiliarySlot.release()
    scheduler.cancelAll()
  })
})

describe("cooldown authority", () => {
  test("a straggler success during the cooldown leaves the circuit open and the queue waiting", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 2,
      breaker: { threshold: 1, cooldownMs: 10_000, mode: "wait" },
      now: () => now.value,
    })
    scheduler.recordStall()

    const waiting = scheduler.acquire("waiting", { newTokens: 0, contextTokens: 0 })
    expect(await settled(waiting)).toBe(false)

    // A request admitted before the circuit opened finishes mid-cooldown: its
    // success is not the probe's, so the circuit stays open and the queue stays
    // held.
    now.value = 5_000
    scheduler.recordSuccess()
    expect(scheduler.status().breaker).toBe("open")
    expect(await settled(waiting)).toBe(false)
    expect(scheduler.queuedCount).toBe(1)

    scheduler.cancelAll()
    await waiting.catch(() => {})
  })

  test("a straggler stall during the cooldown neither extends it nor shrinks the cap", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 2,
      contextCapacity: 800_000,
      contextCeiling: 800_000,
      breaker: { threshold: 1, cooldownMs: 10_000, mode: "wait" },
      now: () => now.value,
    })
    scheduler.recordStall()
    expect(scheduler.status().contextCapacity).toBe(400_000)

    now.value = 5_000
    scheduler.recordStall()

    const status = scheduler.status()
    expect(status.breaker).toBe("open")
    // No larger than the remaining cooldown: the stall did not restart it.
    expect(status.breakerRetryAfterMs).toBe(5_000)
    // The cap is unchanged, so the suppression is real and not masked by the
    // zero-cap early return.
    expect(status.contextCapacity).toBe(400_000)
    scheduler.cancelAll()
  })

  test("a stalled probe at the cooldown reopens the circuit and shrinks the cap", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 2,
      contextCapacity: 800_000,
      contextCeiling: 800_000,
      breaker: { threshold: 2, cooldownMs: 1_000, mode: "wait" },
      now: () => now.value,
    })
    scheduler.recordStall()
    scheduler.recordStall()
    expect(scheduler.status().contextCapacity).toBe(400_000)
    now.value = 1_000

    const probe = await scheduler.acquire("probe", { newTokens: 0, contextTokens: 0 })
    expect(scheduler.status().breaker).toBe("half-open")
    scheduler.recordStall()

    const status = scheduler.status()
    expect(status.breaker).toBe("open")
    expect(status.breakerRetryAfterMs).toBe(1_000)
    expect(status.contextCapacity).toBe(200_000)
    probe.release()
    scheduler.cancelAll()
  })

  test("a success serves a queued wait-mode waiter with no context cap configured", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 2,
      breaker: { threshold: 1, cooldownMs: 1_000, mode: "wait" },
      now: () => now.value,
    })
    scheduler.recordStall()

    const waiting = scheduler.acquire("waiting", { newTokens: 0, contextTokens: 0 })
    expect(await settled(waiting)).toBe(false)

    now.value = 1_000
    scheduler.recordSuccess()
    // Served by the success itself, not by the two-second recheck timer.
    expect(await settled(waiting)).toBe(true)
    const slot = await waiting
    slot.release()
    scheduler.cancelAll()
  })
})

/** Resolves true when `promise` settles within `ms` of real time. */
function settlesWithin(promise: Promise<unknown>, ms: number): Promise<boolean> {
  return Promise.race([
    promise.then(
      () => true,
      () => true,
    ),
    new Promise<boolean>((resolve) => setTimeout(() => resolve(false), ms)),
  ])
}

// These run on the real clock: the bug they pin is a timer that was never
// armed, which a frozen clock cannot show. Every request the tests queue is
// admitted without any slot being released and without a new request arriving,
// which is the state a fan-out reaches when every session waits on its own
// queued request.
describe("RequestScheduler wakes queued requests without a release", () => {
  test("requests held by the reserve are admitted once the bucket refills", async () => {
    // 10 tokens per millisecond; the reserve is 250 and a small request is at most 100.
    const budget = new TokenBudget({ capacity: 1000, refillPerMinute: 600_000 })
    const scheduler = new RequestScheduler({
      maxSlots: 8,
      budget,
      reserveShare: 0.25,
      smallShare: 0.1,
      agingMs: 60_000,
    })

    const big = await scheduler.acquire("big", { newTokens: 900, contextTokens: 0 })
    // A large request is waiting, so the reserve now protects it from the small
    // requests behind it.
    const large = scheduler.acquire("large", { newTokens: 200, contextTokens: 0 })
    const small = Array.from({ length: 6 }, (_, index) =>
      scheduler.acquire(`small-${index}`, { newTokens: 50, contextTokens: 0 }),
    )
    expect(scheduler.queuedCount).toBe(7)

    expect(await settlesWithin(Promise.all([large, ...small]), 1_000)).toBe(true)
    expect(scheduler.queuedCount).toBe(0)
    expect(scheduler.activeCount).toBe(8)

    for (const slot of await Promise.all(small)) slot.release()
    ;(await large).release()
    big.release()
    scheduler.cancelAll()
  })

  test("a small request the bucket cannot refill for is admitted once it ages", async () => {
    // One token per second: the reserve would take minutes to refill.
    const budget = new TokenBudget({ capacity: 1000, refillPerMinute: 60 })
    const scheduler = new RequestScheduler({
      maxSlots: 2,
      budget,
      reserveShare: 0.25,
      smallShare: 0.1,
      agingMs: 30,
    })
    budget.spend(900)

    // A large waiter makes the reserve apply to the small request behind it.
    const large = scheduler.acquire("large", { newTokens: 200, contextTokens: 0 })
    const small = scheduler.acquire("small", { newTokens: 50, contextTokens: 0 })
    expect(scheduler.queuedCount).toBe(2)

    // The small request ages out of the reserve while the bucket is still short.
    expect(await settlesWithin(small, 1_000)).toBe(true)
    ;(await small).release()

    scheduler.cancelSession("large")
    await expect(large).rejects.toThrow("session ended")
    scheduler.cancelAll()
  })

  test("a held small request does not cancel a large request's refill wake-up", async () => {
    // One token per millisecond; the large request needs about 50 ms of refill.
    const budget = new TokenBudget({ capacity: 1000, refillPerMinute: 60_000 })
    const scheduler = new RequestScheduler({
      maxSlots: 8,
      budget,
      reserveShare: 0.25,
      smallShare: 0.1,
      agingMs: 60_000,
    })
    budget.spend(900)

    const large = scheduler.acquire("large", { newTokens: 150, contextTokens: 0 })
    const small = scheduler.acquire("small", { newTokens: 20, contextTokens: 0 })
    expect(scheduler.queuedCount).toBe(2)

    expect(await settlesWithin(large, 1_000)).toBe(true)

    ;(await large).release()
    scheduler.cancelAll()
    await small.catch(() => {})
  })
})

describe("oversized token cost", () => {
  test("a request larger than the bucket is admitted instead of waiting forever", async () => {
    const now = { value: 0 }
    const budget = new TokenBudget({ capacity: 1000, refillPerMinute: 60_000, now: () => now.value })
    const scheduler = new RequestScheduler({ maxSlots: 2, budget, now: () => now.value })

    const slot = await scheduler.acquire("big", { newTokens: 5000, contextTokens: 0 })
    expect(scheduler.queuedCount).toBe(0)
    expect(scheduler.activeCount).toBe(1)
    slot.release()
    scheduler.cancelAll()
  })
})

describe("RequestScheduler blocked gate counts", () => {
  test("a waiter held by the context cap is counted under context", async () => {
    const now = { value: 0 }
    const scheduler = new RequestScheduler({
      maxSlots: 8,
      contextCapacity: 1_000,
      agingMs: 60_000,
      now: () => now.value,
    })
    const held = await scheduler.acquire("a", { newTokens: 0, contextTokens: 600 })
    const waiting = scheduler.acquire("b", { newTokens: 0, contextTokens: 600 })
    expect(scheduler.blocked()).toEqual({
      slots: 0,
      context: 1,
      budget: 0,
      breaker: 0,
      draining: 0,
    })

    held.release()
    ;(await waiting).release()
    scheduler.cancelAll()
  })

  test("a waiter held by the token budget is counted under budget", async () => {
    const budget = new TokenBudget({ capacity: 1_000, refillPerMinute: 60, now: () => 0 })
    const scheduler = new RequestScheduler({
      maxSlots: 4,
      budget,
      smallShare: 0.1,
      reserveShare: 0.25,
      agingMs: 60_000,
      now: () => 0,
    })
    budget.spend(950)

    const waiting = scheduler.acquire("a", { newTokens: 100, contextTokens: 0 })
    expect(scheduler.blocked().budget).toBe(1)

    scheduler.cancelAll()
    await waiting.catch(() => {})
  })
})
