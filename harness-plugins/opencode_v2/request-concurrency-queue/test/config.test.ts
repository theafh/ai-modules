import { describe, expect, test } from "bun:test"
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  configSnapshot,
  loadConfigFile,
  resolveScheduler,
  resolveTokenBudgets,
  saveConfig,
} from "../src/index.js"
import { TokenBudget } from "../src/budget.js"
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
    providerSetEditable: true,
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

  test("reports the token budget and scheduler the store runs, whichever source configured them", () => {
    const store = createStore(
      new Map([
        ["acme", 4],
        ["other", 2],
      ]),
      new Map([["acme", { capacity: 500_000, refillPerMinute: 500_000, safetyFactor: 1.2 }]]),
      {
        contextCapacity: 900_000,
        contextCeiling: 1_800_000,
        reserveShare: 0.3,
        smallShare: 0.15,
        agingMs: 45_000,
        queueDeadlineMs: 240_000,
        breaker: { threshold: 4, cooldownMs: 90_000, mode: "wait" },
      },
      undefined,
      false,
    )

    const snapshot = configSnapshot(store, undefined)

    expect(snapshot.tokens).toEqual({
      acme: { capacity: 500_000, refillPerMinute: 500_000, safetyFactor: 1.2 },
    })
    expect(snapshot.tokens.other).toBeUndefined()
    expect(snapshot.scheduler).toEqual({
      contextCapacity: 900_000,
      contextCeiling: 1_800_000,
      reserveShare: 0.3,
      smallShare: 0.15,
      agingMs: 45_000,
      queueDeadlineMs: 240_000,
      breaker: { threshold: 4, cooldownMs: 90_000, mode: "wait" },
    })
  })

  test("reports hostAware from the gate rather than the file", () => {
    const store = createStore(new Map([["acme", 2]]), new Map(), undefined, {
      max: 6,
      hostAware: true,
    })

    expect(configSnapshot(store, undefined).subagents).toEqual({ max: 6, hostAware: true })
  })

  test("a file-sourced budget reaches the store, so both sources report one value", () => {
    const fileConfig = { tokens: { acme: { capacity: 1_000, refillPerMinute: 500 } } }
    const fromFile = createStore(new Map([["acme", 2]]), resolveTokenBudgets({}, fileConfig))
    const fromOptions = createStore(
      new Map([["acme", 2]]),
      resolveTokenBudgets({ tokens: fileConfig.tokens }),
    )

    // The store speaks for the value; a conflicting file argument does not win.
    expect(configSnapshot(fromFile, { tokens: { acme: { capacity: 999_999, refillPerMinute: 1 } } }).tokens).toEqual(
      { acme: { capacity: 1_000, refillPerMinute: 500, safetyFactor: 1 } },
    )
    expect(configSnapshot(fromFile, fileConfig).tokens).toEqual(configSnapshot(fromOptions).tokens)
  })

  test("a store with no providers reports the zeroed scheduler defaults", () => {
    const snapshot = configSnapshot(createStore(new Map()))

    expect(snapshot.providers).toEqual({})
    expect(snapshot.tokens).toEqual({})
    expect(snapshot.scheduler).toEqual({
      contextCapacity: 0,
      contextCeiling: 0,
      reserveShare: 0.25,
      smallShare: 0.1,
      agingMs: 30_000,
      queueDeadlineMs: 0,
      breaker: { threshold: 3, cooldownMs: 60_000, mode: "fail" },
    })
  })

  test("still accepts the file config input and the plugin still supplies the re-read one", () => {
    const store = storeWith()

    // The second argument stays in the signature; every live value comes from
    // the store even when a file config is passed.
    expect(
      configSnapshot(store, { tokens: { acme: { capacity: 5, refillPerMinute: 5 } } }).tokens,
    ).toEqual({})

    const source = readFileSync(join(import.meta.dir, "..", "src", "index.ts"), "utf8")
    expect(source).toContain("configSnapshot(store, currentFileConfig(), options)")
  })
})

describe("configSnapshot's provider set", () => {
  test("reports the saved maximum after a save and leaves it unchanged on a second save", () => {
    const file = tempFile()
    const store = storeWith(8)
    try {
      expect(saveConfig(store, validSnapshot({ providers: { acme: 4 } }), file.path).ok).toBe(true)

      const snapshot = configSnapshot(store, loadConfigFile(file.path), {})
      expect(snapshot.providers).toEqual({ acme: 4 })

      const second = saveConfig(store, snapshot, file.path)
      expect(second).toEqual({ ok: true, errors: [], restartRequired: false })

      expect(configSnapshot(store, loadConfigFile(file.path), {}).providers).toEqual({ acme: 4 })
      expect(JSON.parse(readFileSync(file.path, "utf8")).providers).toEqual({ acme: 4 })
    } finally {
      file.cleanup()
    }
  })

  test("reports the store's set when the options carry one, even when the file differs", () => {
    const store = createStore(new Map([["acme", 4]]))

    const snapshot = configSnapshot(store, { providers: { beta: 2 } }, { providers: { acme: 4 } })

    expect(snapshot.providers).toEqual({ acme: 4 })
  })

  test("resolves a file provider list at the options' shared default", () => {
    // The store runs 8; the file list and the options' default say 4, so the
    // reported numbers can only come from the file branch.
    const store = createStore(new Map([
      ["acme", 8],
      ["beta", 8],
    ]))

    const snapshot = configSnapshot(store, { providers: ["acme", "beta"] }, { maxConcurrency: 4 })

    expect(snapshot.providers).toEqual({ acme: 4, beta: 4 })
  })

  test("reports a pending provider set from the file and keeps it across a second save", () => {
    const file = tempFile()
    const store = storeWith(8)
    try {
      // The store gates `acme` only; the save adds `beta`, which the store
      // defers to a restart while the file already holds it.
      const first = saveConfig(
        store,
        validSnapshot({ providers: { acme: 8, beta: 2 }, tokens: {} }),
        file.path,
      )
      expect(first).toEqual({ ok: true, errors: [], restartRequired: true })
      expect(store.providers.has("beta")).toBe(false)

      const pending = configSnapshot(store, loadConfigFile(file.path), {})
      expect(pending.providers).toEqual({ acme: 8, beta: 2 })

      const second = saveConfig(store, pending, file.path)
      expect(second.ok).toBe(true)
      expect(second.restartRequired).toBe(true)
      expect(JSON.parse(readFileSync(file.path, "utf8")).providers).toEqual({ acme: 8, beta: 2 })
    } finally {
      file.cleanup()
    }
  })

  test("marks the set editable only when no plugin options own it", () => {
    const store = storeWith(4)

    expect(configSnapshot(store, undefined, {}).providerSetEditable).toBe(true)
    expect(
      configSnapshot(store, { providers: { acme: 4 } }, {}).providerSetEditable,
    ).toBe(true)
    expect(
      configSnapshot(store, undefined, { providers: { acme: 4 } }).providerSetEditable,
    ).toBe(false)
    expect(
      configSnapshot(store, undefined, { providers: ["acme"] }).providerSetEditable,
    ).toBe(false)
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

describe("saving the reported live settings", () => {
  function optionsStore() {
    return createStore(
      new Map([["acme", 4]]),
      new Map([["acme", { capacity: 500_000, refillPerMinute: 500_000, safetyFactor: 1.2 }]]),
      {
        contextCapacity: 900_000,
        contextCeiling: 1_800_000,
        reserveShare: 0.3,
        smallShare: 0.15,
        agingMs: 45_000,
        queueDeadlineMs: 240_000,
        breaker: { threshold: 4, cooldownMs: 90_000, mode: "wait" },
      },
      undefined,
      false,
    )
  }

  test("an unchanged save writes the same values and leaves the live limits as they were", () => {
    const file = tempFile()
    const store = optionsStore()
    try {
      const before = configSnapshot(store, undefined)
      const result = saveConfig(store, before, file.path)

      expect(result).toEqual({ ok: true, errors: [], restartRequired: false })

      const written = JSON.parse(readFileSync(file.path, "utf8"))
      expect(written.tokens).toEqual({
        acme: { capacity: 500_000, refillPerMinute: 500_000, safetyFactor: 1.2 },
      })
      expect(written.scheduler).toEqual({
        contextCapacity: 900_000,
        contextCeiling: 1_800_000,
        reserveShare: 0.3,
        smallShare: 0.15,
        agingMs: 45_000,
        queueDeadlineMs: 240_000,
        breaker: { threshold: 4, cooldownMs: 90_000, mode: "wait" },
      })

      const scheduler = store.providers.get("acme")!.scheduler
      expect(scheduler.budgetSnapshot?.capacity).toBe(500_000)
      expect(scheduler.budgetConfig?.refillPerMinute).toBe(500_000)
      expect(scheduler.status().contextCapacity).toBe(900_000)
    } finally {
      file.cleanup()
    }
  })

  test("reports a refill change applied in place and an unchanged save keeps it", () => {
    const file = tempFile()
    const store = createStore(
      new Map([["acme", 2]]),
      new Map([["acme", { capacity: 500_000, refillPerMinute: 500_000 }]]),
    )
    try {
      const scheduler = store.providers.get("acme")!.scheduler
      scheduler.reconfigureBudget({ capacity: 500_000, refillPerMinute: 250_000 })

      const snapshot = configSnapshot(store, undefined)
      expect(snapshot.tokens.acme.refillPerMinute).toBe(250_000)

      expect(saveConfig(store, snapshot, file.path).ok).toBe(true)
      expect(JSON.parse(readFileSync(file.path, "utf8")).tokens.acme.refillPerMinute).toBe(250_000)
      expect(scheduler.budgetConfig?.refillPerMinute).toBe(250_000)
    } finally {
      file.cleanup()
    }
  })

  test("keeps a file budget for a provider the store does not gate", () => {
    const file = tempFile()
    const store = createStore(
      new Map([["acme", 2]]),
      new Map([["acme", { capacity: 500_000, refillPerMinute: 500_000 }]]),
    )
    try {
      writeFileSync(
        file.path,
        JSON.stringify({
          providers: { acme: 2 },
          tokens: { other: { capacity: 1_234, refillPerMinute: 4_321 } },
        }),
      )

      const snapshot = configSnapshot(store, undefined)
      expect(snapshot.tokens.other).toBeUndefined()

      expect(saveConfig(store, snapshot, file.path).ok).toBe(true)

      const written = JSON.parse(readFileSync(file.path, "utf8"))
      expect(written.tokens.other).toEqual({ capacity: 1_234, refillPerMinute: 4_321 })
      expect(written.tokens.acme).toEqual({
        capacity: 500_000,
        refillPerMinute: 500_000,
        safetyFactor: 1,
      })
    } finally {
      file.cleanup()
    }
  })

  test("does not attach the file budget to a provider the store gates without one", () => {
    const file = tempFile()
    // The plugin options carry `acme`'s budget, so `options.tokens` wins over
    // the file at load and the store gates `other` with no bucket.
    const store = createStore(
      new Map([
        ["acme", 4],
        ["other", 2],
      ]),
      new Map([["acme", { capacity: 500_000, refillPerMinute: 500_000 }]]),
    )
    try {
      writeFileSync(
        file.path,
        JSON.stringify({
          providers: { acme: 4, other: 2 },
          tokens: {
            acme: { capacity: 500_000, refillPerMinute: 500_000 },
            other: { capacity: 1_234, refillPerMinute: 4_321 },
          },
        }),
      )

      const before = store.providers.get("other")!.scheduler.budgetConfig
      expect(before).toBeUndefined()

      const snapshot = configSnapshot(store, undefined)
      expect(saveConfig(store, snapshot, file.path).ok).toBe(true)

      // The file entry stays where it is, and live admission is unchanged.
      expect(store.providers.get("other")!.scheduler.budgetConfig).toBeUndefined()
      expect(JSON.parse(readFileSync(file.path, "utf8")).tokens.other).toEqual({
        capacity: 1_234,
        refillPerMinute: 4_321,
      })
    } finally {
      file.cleanup()
    }
  })

  test("drops a removed provider's budget while keeping a dormant entry", () => {
    const file = tempFile()
    const store = createStore(new Map([
      ["acme", 4],
      ["beta", 2],
    ]))
    try {
      // `beta` is in the file's provider set and this save removes it, so its
      // budget must go with its maximum. `other` was never in that set — a
      // dormant entry from a hand-edited file — and must survive.
      writeFileSync(
        file.path,
        JSON.stringify({
          providers: { acme: 4, beta: 2 },
          tokens: {
            acme: { capacity: 500_000, refillPerMinute: 500_000 },
            beta: { capacity: 1_000, refillPerMinute: 1_000 },
            other: { capacity: 1_234, refillPerMinute: 4_321 },
          },
        }),
      )

      const result = saveConfig(
        store,
        validSnapshot({
          providers: { acme: 2 },
          tokens: { acme: { capacity: 500_000, refillPerMinute: 500_000, safetyFactor: 1 } },
        }),
        file.path,
      )

      expect(result.ok).toBe(true)
      expect(result.restartRequired).toBe(true)

      const written = JSON.parse(readFileSync(file.path, "utf8"))
      expect(written.providers).toEqual({ acme: 2 })
      expect(written.tokens).toEqual({
        acme: { capacity: 500_000, refillPerMinute: 500_000, safetyFactor: 1 },
        other: { capacity: 1_234, refillPerMinute: 4_321 },
      })
    } finally {
      file.cleanup()
    }
  })

  test("saving hostAware off admits a launch the host probe held, and on holds it again", async () => {
    const file = tempFile()
    const store = createStore(new Map([["acme", 1]]), new Map(), undefined, {
      max: 4,
      hostAware: true,
      probe: () => ({ cores: 2, load1: 0, freeMemoryGB: 8 }),
    })
    const gate = store.subagents!
    try {
      expect(gate.capacity()).toBe(2)
      const first = await gate.acquire("child-1")
      const second = await gate.acquire("child-2")
      let admitted = false
      const queued = gate.acquire("child-3").then((permit) => {
        admitted = true
        return permit
      })
      await Promise.resolve()
      expect(admitted).toBe(false)

      const off = configSnapshot(store, undefined)
      off.subagents.hostAware = false
      expect(saveConfig(store, off, file.path).ok).toBe(true)

      const third = await queued
      expect(admitted).toBe(true)
      expect(gate.capacity()).toBe(4)

      const on = configSnapshot(store, undefined)
      on.subagents.hostAware = true
      expect(saveConfig(store, on, file.path).ok).toBe(true)
      expect(gate.capacity()).toBe(2)

      third.release()
      second.release()
      first.release()
    } finally {
      file.cleanup()
    }
  })
})

describe("saveConfig failure handling", () => {
  test("a failed apply removes the file it just wrote", () => {
    const file = tempFile()
    const store = storeWith()
    try {
      // Simulate a store whose scheduler cannot be reconfigured.
      const scheduler = store.providers.get("acme")!.scheduler as unknown as Record<string, unknown>
      scheduler.reconfigure = undefined

      const result = saveConfig(store, validSnapshot(), file.path)

      expect(result.ok).toBe(false)
      expect(result.errors.join(" ")).toContain("Could not apply the settings")
      // The file was renamed into place, then removed when the apply threw.
      expect(existsSync(file.path)).toBe(false)
      expect(existsSync(`${file.path}.tmp`)).toBe(false)
    } finally {
      file.cleanup()
    }
  })

  test("a malformed existing config file is reported and left unchanged", () => {
    const file = tempFile()
    const store = storeWith()
    const malformed = "{ not json"
    try {
      writeFileSync(file.path, malformed)

      const result = saveConfig(store, validSnapshot(), file.path)

      expect(result.ok).toBe(false)
      expect(result.errors[0]).toContain(`Failed to read ${file.path}`)
      expect(readFileSync(file.path, "utf8")).toBe(malformed)
    } finally {
      file.cleanup()
    }
  })

  test("a failed rename leaves both sides unchanged and removes the temporary file", () => {
    const file = tempFile()
    const store = storeWith(8)
    const previous = `${JSON.stringify({ providers: { acme: 8 } })}\n`
    try {
      writeFileSync(file.path, previous)

      const result = saveConfig(store, validSnapshot(), file.path, {
        readFile: (path) => readFileSync(path, "utf8"),
        rename: () => {
          throw new Error("rename exploded")
        },
      })

      expect(result.ok).toBe(false)
      expect(result.errors.join(" ")).toContain("rename")
      expect(existsSync(`${file.path}.tmp`)).toBe(false)
      expect(readFileSync(file.path, "utf8")).toBe(previous)

      const limit = store.providers.get("acme")!
      expect(limit.scheduler.maxConcurrency).toBe(8)
      expect(limit.scheduler.status().contextCapacity).toBe(1000)
    } finally {
      file.cleanup()
    }
  })

  test("an apply throw restores the previous file bytes", () => {
    const file = tempFile()
    const store = storeWith()
    const previous = `${JSON.stringify({ providers: { acme: 8 }, log: true })}\n`
    try {
      writeFileSync(file.path, previous)
      const scheduler = store.providers.get("acme")!.scheduler as unknown as Record<string, unknown>
      scheduler.reconfigure = () => {
        throw new Error("reconfigure exploded")
      }

      const result = saveConfig(store, validSnapshot(), file.path)

      expect(result.ok).toBe(false)
      expect(result.errors.join(" ")).toContain("Could not apply the settings")
      expect(readFileSync(file.path, "utf8")).toBe(previous)
    } finally {
      file.cleanup()
    }
  })

  test("an apply throw on a fresh install removes the file it wrote", () => {
    const file = tempFile()
    const store = storeWith()
    try {
      const scheduler = store.providers.get("acme")!.scheduler as unknown as Record<string, unknown>
      scheduler.reconfigure = () => {
        throw new Error("reconfigure exploded")
      }

      const result = saveConfig(store, validSnapshot(), file.path)

      expect(result.ok).toBe(false)
      expect(existsSync(file.path)).toBe(false)
      expect(existsSync(`${file.path}.tmp`)).toBe(false)
    } finally {
      file.cleanup()
    }
  })
})

describe("resolveScheduler", () => {
  test("defaults a missing contextCapacity to zero", () => {
    expect(resolveScheduler({}, { scheduler: { queueDeadlineMs: 240_000 } })).toEqual({
      contextCapacity: 0,
      queueDeadlineMs: 240_000,
    })
  })

  test("loads a config file whose scheduler holds only the deadline", () => {
    const file = tempFile()
    try {
      writeFileSync(file.path, JSON.stringify({ scheduler: { queueDeadlineMs: 240_000 } }))

      const loaded = loadConfigFile(file.path)

      expect(resolveScheduler({}, loaded)).toEqual({ contextCapacity: 0, queueDeadlineMs: 240_000 })
    } finally {
      file.cleanup()
    }
  })

  test("still rejects a present contextCapacity that is negative or fractional", () => {
    expect(() => resolveScheduler({}, { scheduler: { contextCapacity: -1 } })).toThrow(
      /contextCapacity must be a non-negative integer/,
    )
    expect(() => resolveScheduler({}, { scheduler: { contextCapacity: 1.5 } })).toThrow(
      /contextCapacity must be a non-negative integer/,
    )
  })
})

describe("resolveTokenBudgets safetyFactor", () => {
  for (const factor of [0, -1, Number.NaN]) {
    test(`rejects a safetyFactor of ${String(factor)} and names the provider`, () => {
      expect(() =>
        resolveTokenBudgets(
          {},
          { tokens: { acme: { capacity: 1_000, refillPerMinute: 500, safetyFactor: factor } } },
        ),
      ).toThrow(/acme/)
    })
  }

  test("applies a valid safety factor", () => {
    const budgets = resolveTokenBudgets(
      {},
      { tokens: { acme: { capacity: 1_000, refillPerMinute: 500, safetyFactor: 1.5 } } },
    )
    expect(budgets.get("acme")?.safetyFactor).toBe(1.5)
  })

  test("a budget holding only capacity and refillPerMinute keeps the default factor", () => {
    const budgets = resolveTokenBudgets(
      {},
      { tokens: { acme: { capacity: 1_000, refillPerMinute: 500 } } },
    )
    expect(new TokenBudget(budgets.get("acme")!).safetyFactor).toBe(1)
  })
})
