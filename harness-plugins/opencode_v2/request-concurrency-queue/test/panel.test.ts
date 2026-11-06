import { afterAll, beforeAll, describe, expect, test } from "bun:test"
import { createHash } from "node:crypto"
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, resolve } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"
import { renderToString } from "solid-js/web"
import { build, createServer, type ViteDevServer } from "vite"
import { STATUS_UNAVAILABLE, panel, statusBodyState } from "../src/gui.tsx"
import type { StatusSnapshot, TransitionRecord } from "../src/rpc.js"
import {
  PANEL_TRANSITION_LIMIT,
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

describe("concurrency status panel", () => {
  test("is a side-region panel with one pinned tab", () => {
    expect(panel.region).toBe("side")
    expect(typeof panel.list).toBe("function")
    expect(typeof panel.render).toBe("function")

    const tabs = panel.list({ open: [], session: {} as never, screen: {} as never })
    expect(tabs).toHaveLength(1)
    expect(tabs[0]).toMatchObject({ id: "status", pinned: true })
  })

  test("exports no Slot part", async () => {
    const gui = await import("../src/gui.tsx")
    expect("Slot" in gui).toBe(false)
    expect("slot" in gui).toBe(false)
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
    expect(JSON.parse(imported.stdout.trim())).toEqual({ setup: "function", panel: true })
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
