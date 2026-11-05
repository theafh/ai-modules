/**
 * Pure mapping from discovered skills to slash-command specs.
 *
 * Kept free of Solid, the TUI, and I/O so the naming, collision, and
 * validation rules are testable as a data transform.
 */

export interface SkillLike {
  readonly id: string
  readonly name?: string
  readonly description?: string
}

export interface SkillCommandSpec {
  /** One-line description shown beside the entry in the slash menu. */
  readonly description: string
  /** The name typed after `/`. Equal to the skill ID. */
  readonly slashName: string
  /** Skill ID passed to the session prompt to load the skill. */
  readonly skillID: string
}

export type SkipReason = "reserved" | "invalid" | "duplicate"

export interface SkippedSkill {
  readonly id: string
  readonly reason: SkipReason
}

export interface BuildResult {
  readonly commands: readonly SkillCommandSpec[]
  readonly skipped: readonly SkippedSkill[]
}

/**
 * Slash names the host already owns. A skill sharing one of these names would
 * shadow or be shadowed by a built-in command, so it is skipped instead.
 *
 * This list is the built-in set only. Server-configured commands are added at
 * runtime by `reservedNames`, because they are data, not a constant.
 */
export const BUILTIN_SLASH_NAMES: readonly string[] = [
  "agents",
  "btw",
  "cd",
  "clear",
  "compact",
  "connect",
  "continue",
  "debug",
  "diff",
  "editor",
  "effort",
  "export",
  "goal",
  "help",
  "init",
  "mcp",
  "mcps",
  "models",
  "new",
  "plugins",
  "redo",
  "review",
  "sessions",
  "share",
  "skills",
  "theme",
  "undo",
]

/**
 * A slash name must survive being typed and parsed as a command head. The
 * skill ID is path-derived, so it is already lowercase and hyphenated; this
 * guard only rejects anything that would not parse.
 */
const SLASH_NAME = /^[a-z0-9]+(?:[-_][a-z0-9]+)*$/

export function isValidSlashName(name: string): boolean {
  return name.length > 0 && name.length <= 64 && SLASH_NAME.test(name)
}

/**
 * Builds one slash command per skill, skipping any skill that would collide
 * with a reserved name, carries an unusable ID, or repeats an earlier skill.
 *
 * Input order is preserved so the menu order follows discovery order. The
 * first skill claiming a name wins, which keeps the result stable when the
 * same skill is reachable through more than one discovery root.
 */
export function buildSkillCommands(skills: readonly SkillLike[], reserved: ReadonlySet<string>): BuildResult {
  const commands: SkillCommandSpec[] = []
  const skipped: SkippedSkill[] = []
  const claimed = new Set<string>()

  for (const skill of skills) {
    const slashName = skill.id
    if (!isValidSlashName(slashName)) {
      skipped.push({ id: skill.id, reason: "invalid" })
      continue
    }
    if (reserved.has(slashName) || claimed.has(slashName)) {
      skipped.push({ id: skill.id, reason: reserved.has(slashName) ? "reserved" : "duplicate" })
      continue
    }
    claimed.add(slashName)
    commands.push({
      description: skill.description ?? `Load the ${skill.name ?? skill.id} skill`,
      slashName,
      skillID: skill.id,
    })
  }

  return { commands, skipped }
}

/**
 * Reserved names as seen at runtime: the built-in set plus every command the
 * server already exposes, plus any names the user configured.
 */
export function reservedNames(serverCommands: readonly { name: string }[], extra: readonly string[] = []): Set<string> {
  const names = new Set<string>(BUILTIN_SLASH_NAMES)
  for (const command of serverCommands) names.add(command.name)
  for (const name of extra) names.add(name)
  return names
}

/**
 * The prompt text sent with the skill attachment. The skill body carries the
 * instructions, so the default is a neutral directive rather than the skill
 * content: pasting `SKILL.md` into the prompt is the behaviour this plugin
 * exists to avoid.
 */
export function promptText(input: string | undefined, skillID: string, fallback?: string): string {
  const trimmed = input?.trim()
  if (trimmed) return trimmed
  return fallback ?? `Use the ${skillID} skill.`
}
