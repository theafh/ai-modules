import { describe, expect, test } from "bun:test"
import { existsSync, readFileSync } from "node:fs"
import { dirname, resolve } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"
import { panel } from "../src/gui.tsx"

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
})
