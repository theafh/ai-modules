import { describe, expect, test } from "bun:test"
import {
  BYTES_PER_TOKEN,
  TokenBudget,
  estimateTokens,
  parseRetryAfter,
} from "../src/budget.js"

/** A budget driven by a clock the test advances by hand. */
function budgetAt(now: { value: number }, capacity = 1000, refillPerMinute = 60_000) {
  return new TokenBudget({ capacity, refillPerMinute, now: () => now.value })
}

describe("TokenBudget", () => {
  test("starts full", () => {
    const now = { value: 0 }
    const budget = budgetAt(now)
    expect(budget.snapshot().available).toBe(1000)
  })

  test("spends immediately while the budget lasts", () => {
    const now = { value: 0 }
    const budget = budgetAt(now)
    expect(budget.waitFor(400)).toBe(0)
    budget.spend(400)
    expect(budget.snapshot().available).toBe(600)
  })

  test("waits for the refill to cover a spend it cannot afford", () => {
    const now = { value: 0 }
    // 60,000 tokens per minute is 1,000 tokens per second, so 1 ms per token.
    const budget = budgetAt(now)
    budget.spend(1000)

    // 500 tokens short at 1 token/ms is a 500 ms wait.
    expect(budget.waitFor(500)).toBe(500)

    now.value = 500
    expect(budget.waitFor(500)).toBe(0)
    budget.spend(500)
    expect(budget.snapshot().available).toBe(0)
  })

  test("never refills past capacity", () => {
    const now = { value: 0 }
    const budget = budgetAt(now)
    now.value = 60_000_000
    expect(budget.snapshot().available).toBe(1000)
  })

  test("a pause holds every request until it expires", () => {
    const now = { value: 0 }
    const budget = budgetAt(now)
    budget.pause(30)
    expect(budget.waitFor(1)).toBe(30_000)
    now.value = 30_000
    expect(budget.waitFor(1)).toBe(0)
  })

  test("the longest pause wins", () => {
    const now = { value: 0 }
    const budget = budgetAt(now)
    budget.pause(30)
    budget.pause(5)
    expect(budget.snapshot().pausedUntil).toBe(30_000)
  })

  test("a spend larger than capacity is admitted rather than stuck forever", () => {
    const now = { value: 0 }
    const budget = budgetAt(now, 1000, 60_000)
    // The bucket can never hold more than its capacity, so waiting cannot help.
    expect(budget.waitFor(1500)).toBe(0)
    budget.spend(1500)
    expect(budget.snapshot().available).toBe(0)
  })
})

describe("estimateTokens", () => {
  test("over-estimates at the configured bytes per token", () => {
    expect(estimateTokens(350)).toBe(Math.ceil(350 / BYTES_PER_TOKEN))
    expect(BYTES_PER_TOKEN).toBeLessThan(4)
  })

  test("applies the safety factor", () => {
    expect(estimateTokens(350, 1.5)).toBe(Math.ceil((350 / BYTES_PER_TOKEN) * 1.5))
  })

  test("treats a non-positive or invalid size as no tokens", () => {
    expect(estimateTokens(0)).toBe(0)
    expect(estimateTokens(-5)).toBe(0)
    expect(estimateTokens(Number.NaN)).toBe(0)
  })
})

describe("parseRetryAfter", () => {
  test("reads a number of seconds", () => {
    expect(parseRetryAfter("12")).toBe(12)
    expect(parseRetryAfter("0")).toBe(0)
  })

  test("reads an HTTP date", () => {
    const now = Date.parse("2026-11-20T12:00:00Z")
    expect(parseRetryAfter("Fri, 20 Nov 2026 12:00:30 GMT", now)).toBe(30)
  })

  test("returns zero for a missing or unreadable header", () => {
    expect(parseRetryAfter(null)).toBe(0)
    expect(parseRetryAfter("soon")).toBe(0)
  })
})
