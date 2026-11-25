import { existsSync } from "node:fs"
import { join } from "node:path"
import { Plugin } from "@opencode/plugin"
import {
  applyDecision,
  evaluateGuardrail,
  type GuardrailEnvelope,
  type ScriptResult,
} from "./src/guardrail.js"

/**
 * Runs the repository's shared charter guardrail from an OpenCode 2 permission
 * hook.
 *
 * The policy lives in one POSIX script, `charter_guardrail.sh`, which Claude,
 * Codex, and Antigravity already invoke. This package reuses that script
 * unchanged: it marshals the permission event onto the script's stdin envelope
 * and turns a non-zero exit into a `deny` effect carrying the script's stderr as
 * the message. Setting `effect` is the V2 block mechanism; a V1-style throw is
 * not the contract.
 *
 * The script is deployed beside the plugin package, so it resolves at
 * `../../hooks/charter_guardrail.sh` from this package's directory:
 * `~/.config/opencode/hooks/charter_guardrail.sh` globally and
 * `<project>/.opencode/hooks/charter_guardrail.sh` in project scope.
 */
const SCRIPT_RELATIVE_PATH = join("..", "..", "hooks", "charter_guardrail.sh")

/**
 * Feeds one envelope to the script and captures its exit status and stderr.
 *
 * `Bun.spawn` carries the envelope over a stdin pipe because Bun 1.2.13's `$`
 * shell reports a pipeline's exit status rather than the script's and exposes no
 * usable stdin stream, and a redirect through a temporary file would put tool
 * arguments on disk. The spawn keeps the script's own exit 2 as the signal the
 * guardrail contract is built on.
 */
async function runGuardrailScript(scriptPath: string, envelope: GuardrailEnvelope): Promise<ScriptResult> {
  const child = Bun.spawn([scriptPath], {
    stdin: "pipe",
    stdout: "ignore",
    stderr: "pipe",
  })

  child.stdin.write(JSON.stringify(envelope))
  await child.stdin.end()

  const stderr = await new Response(child.stderr).text()
  const exitCode = await child.exited

  return { exitCode, stderr }
}

export default Plugin.define({
  id: "charter-guardrail",
  async setup(context) {
    const scriptPath = join(import.meta.dir, SCRIPT_RELATIVE_PATH)
    const cwd = context.location.directory
    let warnedMissingScript = false

    await context.permission.hook("evaluate", async (event) => {
      if (!existsSync(scriptPath)) {
        // The package is loaded but the script was not deployed beside it. The
        // guard is simply inactive rather than blocking every action; report
        // the identifier once and keep working.
        if (!warnedMissingScript) {
          warnedMissingScript = true
          console.warn("[charter-guardrail] charter_guardrail.sh is not deployed; the guardrail is inactive")
        }
        return
      }

      try {
        const decision = await evaluateGuardrail(
          { action: event.action, resources: event.resources },
          cwd,
          (envelope) => runGuardrailScript(scriptPath, envelope),
        )
        applyDecision(event, decision)
      } catch {
        // A deployed script that cannot be executed is a broken guard, not an
        // absent one: fail closed so the charter stays protected.
        event.effect = "deny"
        event.message = "charter_guardrail could not run, so the action was blocked."
      }
    })

    return () => {}
  },
})
