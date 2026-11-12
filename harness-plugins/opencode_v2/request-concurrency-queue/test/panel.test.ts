import { afterAll, beforeAll, describe, expect, test } from "bun:test"
import { createHash } from "node:crypto"
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, resolve } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"
import { Panel, Slot, Style } from "@opencode/plugin/gui"
import { renderToString } from "solid-js/web"
import { build, createServer, type ViteDevServer } from "vite"
import gui, { STATUS_UNAVAILABLE, statusBodyState } from "../src/gui.tsx"
import * as guiModule from "../src/gui.tsx"
import type { ProviderStatus, StatusSnapshot, TransitionRecord } from "../src/rpc.js"
import {
  PANEL_TRANSITION_LIMIT,
  loadColor,
  providerRow,
  subscribeStatus,
  transitionRows,
  type StatusClient,
} from "../src/status.js"

const packageDir = resolve(dirname(fileURLToPath(import.meta.url)), "..")

/**
 * The panel source is JSX compiled by the Solid Vite plugin, and the test
 * runner's own JSX transform is not Solid's. Loading the source through Vite's
 * SSR module runner compiles it exactly as the app does, so the panel test
 * renders the real component rather than a hand-built stand-in.
 */
let vite: ViteDevServer
let viteCacheDir: string
let panelModule: {
  StatusBody: (props: { snapshot: StatusSnapshot | null }) => unknown
  StatusBarBody: (props: { snapshot: StatusSnapshot | null; onOpen: () => void }) => unknown
}

beforeAll(async () => {
  viteCacheDir = mkdtempSync(resolve(tmpdir(), "opencode-gui-ssr-"))
  vite = await createServer({
    configFile: resolve(packageDir, "vite.config.ts"),
    root: packageDir,
    logLevel: "silent",
    cacheDir: viteCacheDir,
    server: { middlewareMode: true },
    appType: "custom",
  })
  panelModule = (await vite.ssrLoadModule("/src/gui.tsx")) as typeof panelModule
}, 30_000)

afterAll(async () => {
  await vite?.close()
  rmSync(viteCacheDir, { recursive: true, force: true })
})

function renderPanel(snapshot: StatusSnapshot | null): string {
  return renderToString(() => panelModule.StatusBody({ snapshot }) as never)
}

function renderBar(snapshot: StatusSnapshot | null): string {
  return renderToString(() => panelModule.StatusBarBody({ snapshot, onOpen: () => {} }) as never)
}

function tick(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0))
}

function transition(index: number, overrides: Partial<TransitionRecord> = {}): TransitionRecord {
  return {
    timestamp: 1_700_000_000_000 + index * 1000,
    providerID: "acme",
    kind: "acquired",
    sessionID: `session-${index}`,
    active: 1,
    queued: 0,
    ...overrides,
  }
}

function snapshot(transitions: TransitionRecord[] = []): StatusSnapshot {
  return {
    providers: [{ providerID: "acme", active: 1, queued: 0, max: 2, utilization: 0.5, demand: 0.5 }],
    transitions,
  }
}

function providerSnapshot(provider: Partial<ProviderStatus> & Pick<ProviderStatus, "providerID">): StatusSnapshot {
  const active = provider.active ?? 0
  const queued = provider.queued ?? 0
  const max = provider.max ?? 1
  return {
    providers: [
      {
        providerID: provider.providerID,
        active,
        queued,
        max,
        utilization: max === 0 ? 0 : active / max,
        demand: max === 0 ? 0 : (active + queued) / max,
      },
    ],
    transitions: [],
  }
}

/** The colour of the innermost span whose text is exactly `text`. */
function colorOfText(html: string, text: string): string | undefined {
  const index = html.indexOf(`>${text}<`)
  if (index < 0) return undefined
  const open = html.lastIndexOf("<span", index)
  return html.slice(open, index).match(/style="color:([^"]+)"/)?.[1]
}

/**
 * Imports the prebuilt bundle the way the desktop does: the app provides
 * `@opencode/plugin/gui`, `solid-js`, and `solid-js/web`. A bare in-process
 * `import()` cannot resolve the bundle's CommonJS `require` of those
 * import-condition-only packages, so a child Bun process carries the app's
 * conditions.
 */
function importGuiBundle(path: string): { exitCode: number; stdout: string; stderr: string } {
  const script = `
    const mod = await import(${JSON.stringify(pathToFileURL(path).href)})
    const plugin = mod.default?.setup ? mod.default : mod.default?.default
    console.log(JSON.stringify({ setup: typeof plugin?.setup, panel: typeof mod.panel?.region === "string" }))
  `
  const result = Bun.spawnSync({
    cmd: [process.execPath, "--conditions=browser", "--conditions=import", "-e", script],
    cwd: packageDir,
    stdout: "pipe",
    stderr: "pipe",
  })
  return {
    exitCode: result.exitCode ?? 1,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  }
}

describe("concurrency status panel body", () => {
  test("reports an unavailable status and no rows or feed after a failed fetch", () => {
    const state = statusBodyState(null)

    expect(state).toEqual({ unavailable: true, rows: [], transitions: [] })
    expect(STATUS_UNAVAILABLE).toBe("Status unavailable")
  })

  test("carries one row per provider when a snapshot is present", () => {
    const state = statusBodyState(snapshot())

    expect(state.unavailable).toBe(false)
    expect(state.rows).toEqual([
      providerRow({ providerID: "acme", active: 1, queued: 0, max: 2, utilization: 0.5, demand: 0.5 }),
    ])
    expect(state.transitions).toEqual([])
  })

  test("renders labelled, separated columns with a colour for each load value", () => {
    const html = renderPanel(snapshot())

    for (const label of ["Provider", "Active", "Queued", "Util", "Demand"]) {
      expect(html).toContain(`>${label}<`)
    }
    expect(html).toContain(">acme<")
    expect(html).toContain(">50%<")
    expect(html).toMatch(/style="color:hsl\(/)
  })

  test("labels each feed row's kind and keeps its counts on one line", () => {
    const html = renderPanel(snapshot([transition(0, { kind: "queued", active: 2, queued: 1 })]))

    expect(html).toContain("request-concurrency-feed-kind is-queued")
    expect(html).toContain("2 active · 1 queued")
  })

  test("renders the feed newest first below the provider rows", () => {
    const html = renderPanel(
      snapshot([
        transition(0, { kind: "acquired", sessionID: "older" }),
        transition(1, { kind: "released", sessionID: "newer" }),
      ]),
    )

    expect(html).toContain("request-concurrency-status-provider")
    expect(html).toContain("request-concurrency-feed")
    expect(html.indexOf("request-concurrency-status-row")).toBeLessThan(html.indexOf("request-concurrency-feed"))

    const older = html.indexOf("older")
    const newer = html.indexOf("newer")
    expect(older).toBeGreaterThan(-1)
    expect(newer).toBeGreaterThan(-1)
    expect(newer).toBeLessThan(older)
    expect(html).toContain("released")
    expect(html).toContain("acquired")
  })

  test("caps the rendered feed window while the store keeps more history", () => {
    const many = Array.from({ length: PANEL_TRANSITION_LIMIT + 5 }, (_, index) => transition(index))
    const rows = transitionRows(snapshot(many))

    expect(rows).toHaveLength(PANEL_TRANSITION_LIMIT)
    expect(rows[0].sessionID).toBe(`session-${many.length - 1}`)

    const html = renderPanel(snapshot(many))
    expect(html.match(/request-concurrency-feed-row/g)).toHaveLength(PANEL_TRANSITION_LIMIT)
  })

  test("renders the window-bottom bar with one combined load count per provider", () => {
    const html = renderBar(snapshot())

    expect(html).toContain("request-concurrency-bar")
    expect(html).toContain(">Concurrency<")
    expect(html).toContain(">acme<")
    expect(html).toContain(">1/2<")
    expect(html).toContain("Open concurrency details")
    expect(html).toMatch(/style="color:hsl\(/)
  })

  test("shows active plus queued over max and colours it by the combined load", () => {
    const overloaded = renderBar(providerSnapshot({ providerID: "acme", active: 8, queued: 4, max: 8 }))

    expect(overloaded).toContain(">12/8<")
    expect(overloaded.toLowerCase()).not.toContain("queued")
    expect(overloaded).toContain("12 of 8 slots in demand")
    expect(colorOfText(overloaded, "12/8")).toBe(loadColor(150))
    expect(colorOfText(overloaded, "12/8")).toBe("hsl(60 85% 70%)")

    const full = renderBar(providerSnapshot({ providerID: "acme", active: 6, queued: 2, max: 8 }))

    expect(full).toContain(">8/8<")
    expect(colorOfText(full, "8/8")).toBe(loadColor(100))
    expect(colorOfText(full, "8/8")).toBe("hsl(120 60% 60%)")
  })

  test("drops the queued segment and its separator from a provider item", () => {
    const html = renderBar(snapshot())

    expect(html).not.toContain("request-concurrency-bar-sep")
    expect(html).not.toContain("·")
  })

  test("reports an unavailable status in the bar", () => {
    const html = renderBar(null)

    expect(html).toContain("request-concurrency-bar")
    expect(html).toContain(STATUS_UNAVAILABLE)
  })

  test("hides the bar when no provider is configured", () => {
    const html = renderBar({ providers: [], transitions: [] })

    expect(html).not.toContain("request-concurrency-bar")
  })

  test("updates the rendered feed when a changed event delivers a new snapshot", async () => {
    let current = snapshot([transition(0, { kind: "acquired" })])
    const handlers = new Set<() => void | Promise<void>>()
    const client: StatusClient = {
      status: async () => current,
      events: {
        on: (_name, handler) => {
          handlers.add(handler)
          return () => {
            handlers.delete(handler)
          }
        },
      },
    }
    let latest: StatusSnapshot | null = null
    const unsubscribe = subscribeStatus(() => client, (next) => {
      latest = next
    })
    await tick()
    expect(statusBodyState(latest).transitions.map((row) => row.kind)).toEqual(["acquired"])
    expect(renderPanel(latest)).toContain(">acquired<")

    current = snapshot([transition(0, { kind: "acquired" }), transition(1, { kind: "queued" })])
    for (const handler of [...handlers]) await handler()
    await tick()

    expect(statusBodyState(latest).transitions.map((row) => row.kind)).toEqual(["queued", "acquired"])
    const html = renderPanel(latest)
    expect(html).toContain(">queued<")
    expect(html.indexOf(">queued<")).toBeLessThan(html.indexOf(">acquired<"))
    unsubscribe()
  })
})

describe("concurrency desktop surfaces", () => {
  test("exports no side-region panel", () => {
    const exported = guiModule as unknown as Record<string, unknown>

    expect("panel" in exported).toBe(false)
    expect(exported.panel).toBeUndefined()
  })

  test("contributes one window-bottom slot and one Style, and no Panel", () => {
    const added: Array<{ registry: unknown; item: unknown }> = []
    gui.setup!({
      add: (registry: unknown, item: unknown) => {
        added.push({ registry, item })
        return () => {}
      },
    } as never)

    expect(added.some((entry) => entry.registry === Panel)).toBe(false)
    const slots = added.filter((entry) => entry.registry === Slot)
    expect(slots).toHaveLength(1)
    expect(slots[0].item).toMatchObject({ at: "window.bottom" })
    expect(added.filter((entry) => entry.registry === Style)).toHaveLength(1)
  })

  test("publishes the prebuilt GUI bundle beside the server entry", () => {
    const pkg = JSON.parse(readFileSync(resolve(packageDir, "package.json"), "utf8")) as {
      exports: Record<string, string>
    }

    expect(pkg.exports["."]).toBe("./index.ts")
    expect(existsSync(resolve(packageDir, "index.ts"))).toBe(true)

    const guiExport = pkg.exports["./gui-experimental"]
    expect(typeof guiExport).toBe("string")
    const guiPath = resolve(packageDir, guiExport)
    expect(existsSync(guiPath)).toBe(true)

    const imported = importGuiBundle(guiPath)
    expect(imported.stderr).toBe("")
    expect(imported.exitCode).toBe(0)
    expect(JSON.parse(imported.stdout.trim())).toEqual({ setup: "function", panel: false })
  })

  /**
   * The desktop runs `dist/gui.cjs`, never the plugin's source, so a source
   * edit that skips `bun run build:gui` ships stale code that the load check
   * above cannot see. Rebuilding with the package's own `vite.config.ts` and
   * comparing bytes turns that drift into a failure here.
   */
  test(
    "rebuilds the GUI bundle from source and matches the committed bundle",
    async () => {
      const outDir = mkdtempSync(resolve(tmpdir(), "opencode-gui-build-"))
      try {
        await build({
          configFile: resolve(packageDir, "vite.config.ts"),
          root: packageDir,
          logLevel: "silent",
          // The package's `gui()` plugin names `dist/gui.cjs`. This post
          // `config` hook wins the merge and redirects the build into the
          // scratch directory, so the committed bundle is never rewritten.
          plugins: [
            {
              name: "redirect-gui-build-output",
              enforce: "post",
              config: () => ({ build: { outDir } }),
            },
          ],
        })

        const rebuilt = readFileSync(resolve(outDir, "gui.cjs"))
        const committed = readFileSync(resolve(packageDir, "dist/gui.cjs"))
        if (!rebuilt.equals(committed)) {
          const digest = (bytes: Buffer) => createHash("sha256").update(bytes).digest("hex")
          throw new Error(
            "dist/gui.cjs does not match a fresh build of src/gui.tsx; run `bun run build:gui` and commit the result.\n" +
              `  rebuilt:   ${digest(rebuilt)}\n` +
              `  committed: ${digest(committed)}`,
          )
        }
      } finally {
        rmSync(outDir, { recursive: true, force: true })
      }
    },
    60_000,
  )
})
