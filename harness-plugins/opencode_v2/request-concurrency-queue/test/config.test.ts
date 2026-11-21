import { describe, expect, test } from "bun:test"
import { mkdtempSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { configSnapshot, saveConfig } from "../src/index.js"
import type { ConfigSnapshot } from "../src/rpc.js"
import { createStore } from "../src/store.js"

function tempFile(): { path: string; cleanup: () => void } {
  const dir = mkdtempSync(join(tmpdir(), "rcq-config-"))
  return {
    path: join(dir, "request-concurrency-queue.json"),
    cleanup: () => rmSync(dir, { recursive: true, force: true }),
  }
}

function storeWith(max = 8) {
  return createStore(
    new Map([["acme", max]]),
    new Map(),
    { contextCapacity: 1000, contextCeiling: 2000 },
    { max: 8 },
    false,
  )
}

function validSnapshot(overrides: Partial<ConfigSnapshot> = {}): ConfigSnapshot {
  return {
    providers: { acme: 4 },
    tokens: { acme: { capacity: 400_000, refillPerMinute: 400_000, safetyFactor: 1.1 } },
    scheduler: {
      contextCapacity: 1_200_000,
      contextCeiling: 1_200_000,
      reserveShare: 0.25,
      smallShare: 0.1,
      agingMs: 30_000,
      queueDeadlineMs: 0,
      breaker: { threshold: 2, cooldownMs: 60_000, mode: "fail" },
    },
    subagents: { max: 8, hostAware: false },
    adaptive: false,
    ...overrides,
  }
}

describe("configSnapshot", () => {
  test("reports live provider maximums and fills unset settings with defaults", () => {
    const store = storeWith(6)
    const snapshot = configSnapshot(store, undefined)

    expect(snapshot.providers).toEqual({ acme: 6 })
    expect(snapshot.tokens).toEqual({})
    expect(snapshot.scheduler.breaker).toEqual({ threshold: 3, cooldownMs: 60_000, mode: "fail" })
    expect(snapshot.scheduler.queueDeadlineMs).toBe(0)
    expect(snapshot.subagents).toEqual({ max: 8, hostAware: false })
    expect(snapshot.adaptive).toBe(false)
  })

  test("reads the token budget from the file config", () => {
    const store = storeWith()
    const snapshot = configSnapshot(store, {
      tokens: { acme: { capacity: 1000, refillPerMinute: 500 } },
    })
    expect(snapshot.tokens.acme).toEqual({ capacity: 1000, refillPerMinute: 500, safetyFactor: 1 })
  })
})

describe("saveConfig", () => {
  test("rejects invalid values and writes nothing", () => {
    const file = tempFile()
    const store = storeWith()
    try {
      const result = saveConfig(
        store,
        validSnapshot({ providers: { acme: 0 }, adaptive: false }),
        file.path,
      )
      expect(result.ok).toBe(false)
      expect(result.errors).toContain("providers.acme must be a positive integer")
      expect(() => readFileSync(file.path, "utf8")).toThrow()
    } finally {
      file.cleanup()
    }
  })

  test("rejects a ceiling below the capacity", () => {
    const file = tempFile()
    const store = storeWith()
    try {
      const snapshot = validSnapshot()
      snapshot.scheduler.contextCeiling = 100
      const result = saveConfig(store, snapshot, file.path)
      expect(result.ok).toBe(false)
      expect(result.errors.join(" ")).toContain("contextCeiling must be at least")
    } finally {
      file.cleanup()
    }
  })

  test("writes the file and applies the settings to the running store", () => {
    const file = tempFile()
    const store = storeWith(8)
    try {
      const result = saveConfig(store, validSnapshot(), file.path)

      expect(result).toEqual({ ok: true, errors: [], restartRequired: false })

      const written = JSON.parse(readFileSync(file.path, "utf8"))
      expect(written.providers).toEqual({ acme: 4 })
      expect(written.scheduler.breaker.threshold).toBe(2)

      const limit = store.providers.get("acme")
      expect(limit?.scheduler.maxConcurrency).toBe(4)
      expect(limit?.scheduler.status().contextCapacity).toBe(1_200_000)
      expect(limit?.scheduler.budgetSnapshot?.capacity).toBe(400_000)
    } finally {
      file.cleanup()
    }
  })

  test("keeps a provider set change as a restart notice instead of half-applying", () => {
    const file = tempFile()
    const store = storeWith()
    try {
      const result = saveConfig(store, validSnapshot({ providers: { other: 2 } }), file.path)
      expect(result.ok).toBe(true)
      expect(result.restartRequired).toBe(true)
      expect(store.providers.has("acme")).toBe(true)
      expect(store.providers.has("other")).toBe(false)
    } finally {
      file.cleanup()
    }
  })

  test("preserves unrelated keys already in the file", () => {
    const file = tempFile()
    const store = storeWith()
    try {
      saveConfig(store, validSnapshot(), file.path)
      const first = JSON.parse(readFileSync(file.path, "utf8"))
      first.log = true
      require("node:fs").writeFileSync(file.path, JSON.stringify(first))

      saveConfig(store, validSnapshot({ adaptive: true }), file.path)
      const second = JSON.parse(readFileSync(file.path, "utf8"))
      expect(second.log).toBe(true)
      expect(second.adaptive).toBe(true)
    } finally {
      file.cleanup()
    }
  })
})

describe("saveConfig failure handling", () => {
  test("a failed apply does not write the file", () => {
    const file = tempFile()
    const store = storeWith()
    try {
      // Simulate a store whose scheduler cannot be reconfigured.
      const scheduler = store.providers.get("acme")!.scheduler as unknown as Record<string, unknown>
      scheduler.reconfigure = undefined

      const result = saveConfig(store, validSnapshot(), file.path)

      expect(result.ok).toBe(false)
      expect(result.errors.join(" ")).toContain("Could not apply the settings")
      expect(() => readFileSync(file.path, "utf8")).toThrow()
    } finally {
      file.cleanup()
    }
  })
})
