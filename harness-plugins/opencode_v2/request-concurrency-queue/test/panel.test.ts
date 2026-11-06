import { describe, expect, test } from "bun:test"
import { createHash } from "node:crypto"
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, resolve } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"
import { build } from "vite"
import { STATUS_UNAVAILABLE, panel, statusBodyState } from "../src/gui.tsx"
import { providerRow } from "../src/status.js"

const packageDir = resolve(dirname(fileURLToPath(import.meta.url)), "..")

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
  test("reports an unavailable status and no provider rows after a failed fetch", () => {
    const state = statusBodyState(null)

    expect(state).toEqual({ unavailable: true, rows: [] })
    expect(STATUS_UNAVAILABLE).toBe("Status unavailable")
  })

  test("carries one row per provider when a snapshot is present", () => {
    const rows = [
      providerRow({ providerID: "acme", active: 1, queued: 0, max: 2, utilization: 0.5, demand: 0.5 }),
    ]

    expect(statusBodyState(rows)).toEqual({ unavailable: false, rows })
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
