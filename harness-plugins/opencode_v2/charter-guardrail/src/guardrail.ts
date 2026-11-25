/**
 * Maps an OpenCode permission event onto the shared guardrail script's stdin
 * envelope and turns the script's exit status into a hook effect.
 *
 * Kept free of the plugin runtime, Bun, and I/O so the mapping is testable as a
 * data transform with a stubbed script runner. The policy itself lives in
 * `plugins/ai_dev/hooks/charter_guardrail.sh`, which this package reuses
 * unchanged; this module only marshals the event and relays the decision.
 *
 * The action vocabulary is V2's, not the tool names an agent sees: `edit` gates
 * `edit`, `write`, and `patch` alike, and shell calls arrive as `shell` rather
 * than `bash`. An `edit` event's resources are file paths relative to the
 * session directory (absolute only outside it), while a `shell` event's
 * resources are the raw command text segments the host parsed. The script
 * resolves a relative `file_path` against `cwd`, so both arrive as the script
 * already expects them.
 */

export interface PermissionEventLike {
  readonly action: string
  readonly resources: ReadonlyArray<string>
}

export interface GuardrailEnvelope {
  readonly tool_name: string
  readonly tool_input: {
    readonly file_path?: string
    readonly command?: string
  }
  readonly cwd: string
}

export interface ScriptResult {
  readonly exitCode: number
  readonly stderr: string
}

export type ScriptRunner = (envelope: GuardrailEnvelope) => Promise<ScriptResult>

export interface GuardrailDecision {
  readonly denied: boolean
  readonly message?: string
}

/** Actions that gate a file mutation and carry file paths as their resources. */
const FILE_ACTIONS: ReadonlySet<string> = new Set(["edit", "write", "patch"])

/** The shell action, whose resources are command text rather than paths. */
const SHELL_ACTION = "shell"

/** Message used when the script exits non-zero without writing to stderr. */
const FALLBACK_MESSAGE = "CHARTER.md is protected. Switch to a guardrail/charter-* branch for human-reviewed charter changes."

/**
 * Builds one envelope per resource the script must inspect.
 *
 * A file action can carry several paths (a multi-file patch), so each becomes
 * its own envelope: the script reads a single `file_path` and a single
 * `command`, and one envelope per resource lets it see every candidate. A shell
 * action's resources are command segments, joined with a newline so the
 * script's shell scanner reads all of them. Any other action yields no
 * envelope, because the guardrail has nothing to inspect and the plugin skips
 * the script entirely.
 */
export function buildEnvelopes(event: PermissionEventLike, cwd: string): GuardrailEnvelope[] {
  const resources = event.resources.filter((resource) => resource.length > 0)

  if (event.action === SHELL_ACTION) {
    if (resources.length === 0) return []
    return [{ tool_name: SHELL_ACTION, tool_input: { command: resources.join("\n") }, cwd }]
  }

  if (FILE_ACTIONS.has(event.action)) {
    return resources.map((resource) => ({
      tool_name: event.action,
      tool_input: { file_path: resource },
      cwd,
    }))
  }

  return []
}

/** Turns the script's exit status into a decision, reading the reason from stderr. */
export function interpretResult(result: ScriptResult): GuardrailDecision {
  if (result.exitCode === 0) return { denied: false }
  const message = result.stderr.trim()
  return { denied: true, message: message.length > 0 ? message : FALLBACK_MESSAGE }
}

/** Applies a deny decision to a mutable permission event, leaving an allow untouched. */
export function applyDecision(event: { effect: string; message?: string }, decision: GuardrailDecision): void {
  if (!decision.denied) return
  event.effect = "deny"
  if (decision.message !== undefined) event.message = decision.message
}

/**
 * Runs the script for every envelope and stops at the first denial.
 *
 * A denial is final: later envelopes cannot re-allow an action the script
 * already blocked. A zero exit from every envelope leaves the event untouched,
 * so the host keeps whatever effect its configured rules produced.
 */
export async function evaluateGuardrail(
  event: PermissionEventLike,
  cwd: string,
  run: ScriptRunner,
): Promise<GuardrailDecision> {
  for (const envelope of buildEnvelopes(event, cwd)) {
    const decision = interpretResult(await run(envelope))
    if (decision.denied) return decision
  }
  return { denied: false }
}
