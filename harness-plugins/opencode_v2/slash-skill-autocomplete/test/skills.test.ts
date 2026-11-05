import { describe, expect, test } from "bun:test"
import {
  BUILTIN_SLASH_NAMES,
  buildSkillCommands,
  isValidSlashName,
  promptText,
  reservedNames,
} from "../src/skills.js"

const reserved = new Set(BUILTIN_SLASH_NAMES)

describe("isValidSlashName", () => {
  test("accepts path-derived skill IDs", () => {
    expect(isValidSlashName("git-review")).toBe(true)
    expect(isValidSlashName("task")).toBe(true)
    expect(isValidSlashName("task_select")).toBe(true)
  })

  test("rejects names that would not parse as a command head", () => {
    expect(isValidSlashName("")).toBe(false)
    expect(isValidSlashName("Git Review")).toBe(false)
    expect(isValidSlashName("git/review")).toBe(false)
    expect(isValidSlashName("-leading")).toBe(false)
    expect(isValidSlashName("a".repeat(65))).toBe(false)
  })
})

describe("buildSkillCommands", () => {
  test("maps a skill to a slash command named after its ID", () => {
    const { commands } = buildSkillCommands([{ id: "git-review", description: "Review a branch" }], reserved)
    expect(commands).toEqual([
      {
        description: "Review a branch",
        slashName: "git-review",
        skillID: "git-review",
      },
    ])
  })

  test("uses a default description", () => {
    const { commands } = buildSkillCommands([{ id: "git-review", name: "Git Review" }], reserved)
    expect(commands[0]?.description).toBe("Load the Git Review skill")
  })

  test("skips skills that collide with a built-in command", () => {
    const { commands, skipped } = buildSkillCommands([{ id: "review" }, { id: "task" }], reserved)
    expect(commands.map((command) => command.slashName)).toEqual(["task"])
    expect(skipped).toEqual([{ id: "review", reason: "reserved" }])
  })

  test("skips a skill that collides with a server-configured command", () => {
    const names = reservedNames([{ name: "deploy" }])
    const { commands, skipped } = buildSkillCommands([{ id: "deploy" }], names)
    expect(commands).toEqual([])
    expect(skipped).toEqual([{ id: "deploy", reason: "reserved" }])
  })

  test("keeps the first of duplicate IDs", () => {
    const { commands, skipped } = buildSkillCommands([{ id: "task" }, { id: "task" }], reserved)
    expect(commands).toHaveLength(1)
    expect(skipped).toEqual([{ id: "task", reason: "duplicate" }])
  })

  test("skips an unusable ID", () => {
    const { commands, skipped } = buildSkillCommands([{ id: "Bad Name" }], reserved)
    expect(commands).toEqual([])
    expect(skipped).toEqual([{ id: "Bad Name", reason: "invalid" }])
  })

  test("preserves discovery order", () => {
    const { commands } = buildSkillCommands([{ id: "b" }, { id: "a" }, { id: "c" }], reserved)
    expect(commands.map((command) => command.slashName)).toEqual(["b", "a", "c"])
  })
})

describe("promptText", () => {
  test("passes typed arguments through", () => {
    expect(promptText("  list the tasks  ", "task")).toBe("list the tasks")
  })

  test("falls back to a neutral directive, never the skill body", () => {
    expect(promptText(undefined, "task")).toBe("Use the task skill.")
    expect(promptText("   ", "task")).toBe("Use the task skill.")
  })

  test("honours an explicit fallback", () => {
    expect(promptText(undefined, "task", "Run it.")).toBe("Run it.")
  })
})
