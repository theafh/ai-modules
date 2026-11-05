import { Plugin } from "@opencode/plugin"
import { buildSkillCommands, promptText, reservedNames } from "./src/skills.js"

/**
 * Registers every discovered skill as a `/name` command on the server.
 *
 * The host builds its `/` menu from server commands on every surface: the
 * terminal UI, the desktop app, and `opencode run` all read the same list. A
 * skill is invocable by name but never listed, because the host lists commands
 * rather than skills. Contributing one command per skill closes that gap
 * without changing the skill mechanism: each command prompts the session with
 * the skill attached, so the skill loads with its reference files instead of
 * having its `SKILL.md` pasted into the prompt.
 */
export default Plugin.define({
  id: "slash-skill-autocomplete",
  async setup(context) {
    const log = (context.options.log as boolean | undefined) ?? false
    const debug = (message: string) => {
      if (log) console.log("[slash-skill-autocomplete]", message)
    }

    await context.command.transform(async (editor) => {
      const skills = await context.skill.list()
      const rows = (skills as { data?: readonly unknown[] })?.data ?? skills
      const existing = await context.command.list()
      const commands = (existing as { data?: readonly { name: string }[] })?.data ?? existing
      const { commands: specs, skipped } = buildSkillCommands(
        (rows as readonly { id: string; name?: string; description?: string }[]) ?? [],
        reservedNames((commands as readonly { name: string }[]) ?? []),
      )

      for (const spec of specs) {
        editor.add({
          name: spec.slashName,
          description: spec.description,
          async execute(input) {
            const text = promptText(input.prompt?.text, spec.skillID)
            debug(`/${spec.slashName} -> skill ${spec.skillID}`)
            await context.session.prompt({
              sessionID: input.sessionID,
              text,
              skills: [{ id: spec.skillID }],
              delivery: input.delivery,
            })
          },
        })
      }

      debug(
        `registered ${specs.length} skill commands, skipped ${skipped.length}` +
          (skipped.length ? `: ${skipped.map((s) => `${s.id} (${s.reason})`).join(", ")}` : ""),
      )
    })

    return () => {}
  },
})
