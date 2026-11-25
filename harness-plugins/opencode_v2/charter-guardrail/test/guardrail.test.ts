import { describe, expect, test } from "bun:test"
import { join } from "node:path"
import {
  applyDecision,
  buildEnvelopes,
  evaluateGuardrail,
  interpretResult,
  type GuardrailEnvelope,
  type ScriptResult,
} from "../src/guardrail.js"

const REPO_ROOT = join(import.meta.dir, "..", "..", "..", "..")
const CHARTER_PATH = join(REPO_ROOT, "CHARTER.md")
const STDERR_MESSAGE = "CHARTER.md is protected. Switch to a guardrail/charter-* branch for human-reviewed charter changes."

/** Records every envelope it is handed and answers with the queued results. */
function stubRunner(results: readonly ScriptResult[]) {
  const seen: GuardrailEnvelope[] = []
  const run = async (envelope: GuardrailEnvelope): Promise<ScriptResult> => {
    seen.push(envelope)
    return results[seen.length - 1] ?? { exitCode: 0, stderr: "" }
  }
  return { run, seen }
}

describe("buildEnvelopes", () => {
  test("an edit event carries the resource as tool_input.file_path", () => {
    const envelopes = buildEnvelopes({ action: "edit", resources: [CHARTER_PATH] }, REPO_ROOT)

    expect(envelopes).toHaveLength(1)
    expect(envelopes[0]?.tool_name).toBe("edit")
    expect(envelopes[0]?.tool_input.file_path).toBe(CHARTER_PATH)
    expect(envelopes[0]?.tool_input.command).toBeUndefined()
    expect(envelopes[0]?.cwd).toBe(REPO_ROOT)
  })

  test("a multi-file edit yields one envelope per resource", () => {
    const envelopes = buildEnvelopes({ action: "edit", resources: ["src/a.ts", CHARTER_PATH] }, REPO_ROOT)

    expect(envelopes.map((envelope) => envelope.tool_input.file_path)).toEqual(["src/a.ts", CHARTER_PATH])
  })

  test("a shell event carries its command text as tool_input.command", () => {
    const command = `echo hacked > ${CHARTER_PATH}`
    const envelopes = buildEnvelopes({ action: "shell", resources: [command] }, REPO_ROOT)

    expect(envelopes).toHaveLength(1)
    expect(envelopes[0]?.tool_name).toBe("shell")
    expect(envelopes[0]?.tool_input.command).toBe(command)
    expect(envelopes[0]?.tool_input.file_path).toBeUndefined()
  })

  test("several shell segments are joined for the script's scanner", () => {
    const envelopes = buildEnvelopes(
      { action: "shell", resources: ["cd /tmp", `echo hacked > ${CHARTER_PATH}`] },
      REPO_ROOT,
    )

    expect(envelopes).toHaveLength(1)
    expect(envelopes[0]?.tool_input.command).toBe(`cd /tmp\necho hacked > ${CHARTER_PATH}`)
  })

  test("an unrelated action yields no envelope, so the script is never run", () => {
    expect(buildEnvelopes({ action: "read", resources: [CHARTER_PATH] }, REPO_ROOT)).toEqual([])
    expect(buildEnvelopes({ action: "grep", resources: ["CHARTER.md"] }, REPO_ROOT)).toEqual([])
  })
})

describe("interpretResult", () => {
  test("a zero exit allows", () => {
    expect(interpretResult({ exitCode: 0, stderr: "" })).toEqual({ denied: false })
  })

  test("a non-zero exit denies with the script's stderr as the message", () => {
    expect(interpretResult({ exitCode: 2, stderr: `${STDERR_MESSAGE}\n` })).toEqual({
      denied: true,
      message: STDERR_MESSAGE,
    })
  })

  test("a non-zero exit without stderr still denies with the fallback reason", () => {
    const decision = interpretResult({ exitCode: 2, stderr: "" })

    expect(decision.denied).toBe(true)
    expect(decision.message).toContain("CHARTER.md is protected")
  })
})

describe("evaluateGuardrail", () => {
  test("an edit of CHARTER.md denies with the script's stderr message", async () => {
    const stub = stubRunner([{ exitCode: 2, stderr: `${STDERR_MESSAGE}\n` }])
    const event = { effect: "ask", message: undefined as string | undefined }

    const decision = await evaluateGuardrail({ action: "edit", resources: [CHARTER_PATH] }, REPO_ROOT, stub.run)
    applyDecision(event, decision)

    expect(stub.seen[0]?.tool_input.file_path).toBe(CHARTER_PATH)
    expect(event.effect).toBe("deny")
    expect(event.message).toBe(STDERR_MESSAGE)
  })

  test("a shell redirect into CHARTER.md denies with the same result", async () => {
    const command = `echo hacked > ${CHARTER_PATH}`
    const stub = stubRunner([{ exitCode: 2, stderr: `${STDERR_MESSAGE}\n` }])
    const event = { effect: "allow", message: undefined as string | undefined }

    const decision = await evaluateGuardrail({ action: "shell", resources: [command] }, REPO_ROOT, stub.run)
    applyDecision(event, decision)

    expect(stub.seen[0]?.tool_input.command).toBe(command)
    expect(event.effect).toBe("deny")
    expect(event.message).toBe(STDERR_MESSAGE)
  })

  test("a read-only shell reference leaves the effect untouched", async () => {
    const stub = stubRunner([{ exitCode: 0, stderr: "" }])
    const event = { effect: "ask", message: undefined as string | undefined }

    const decision = await evaluateGuardrail({ action: "shell", resources: ["cat CHARTER.md"] }, REPO_ROOT, stub.run)
    applyDecision(event, decision)

    expect(stub.seen[0]?.tool_input.command).toBe("cat CHARTER.md")
    expect(event.effect).toBe("ask")
    expect(event.message).toBeUndefined()
  })

  test("a denial on an earlier resource stops later envelopes from running", async () => {
    const stub = stubRunner([{ exitCode: 2, stderr: `${STDERR_MESSAGE}\n` }])

    const decision = await evaluateGuardrail(
      { action: "edit", resources: ["src/a.ts", CHARTER_PATH] },
      REPO_ROOT,
      stub.run,
    )

    expect(decision.denied).toBe(true)
    expect(stub.seen).toHaveLength(1)
  })

  test("an unrelated action runs no script and allows", async () => {
    const stub = stubRunner([])

    const decision = await evaluateGuardrail({ action: "read", resources: [CHARTER_PATH] }, REPO_ROOT, stub.run)

    expect(decision.denied).toBe(false)
    expect(stub.seen).toHaveLength(0)
  })
})
