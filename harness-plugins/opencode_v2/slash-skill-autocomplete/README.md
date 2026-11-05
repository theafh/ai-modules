# slash-skill-autocomplete

An OpenCode 2 server plugin that registers every discovered skill as a `/name`
command, so the skill is listed in the `/` menu on every surface: the terminal
UI, the desktop app, and `opencode run`.

OpenCode 2 builds its `/` menu from commands, not from skills. A skill is
invocable by name but never listed: typing `/task_explain` works while typing
`/task` shows nothing. This plugin closes that gap without changing the skill
mechanism. Each command prompts the session with the skill attached, so the
skill loads with its reference files instead of having its `SKILL.md` pasted
into the prompt.

## Behavior

- One slash command per discovered skill, named after the skill's ID.
- The menu shows the skill's `description` when it has one.
- Text typed after the command becomes the prompt; with no text the prompt is
  a neutral directive, never the skill body.
- Skills are read when the server builds its command list, so `/reload` picks
  up an installed skill without restarting OpenCode.
- A skill whose name collides with a built-in or configured command is skipped,
  not silently shadowed.

## Requirements

- OpenCode 2.2.5 or newer.
- Nothing else. The plugin registers commands on the server, which every
  surface already reads.

## Install

Deploy the plugin package into the OpenCode plugin discovery root:

```bash
./deployment/deployment.sh --global --target opencode --type plugin
```

The deployed copy lands at `~/.config/opencode/plugins/slash-skill-autocomplete`
and is recorded in the deploy log, so `--update` refreshes it and `--uninstall`
removes it. A manual alternative is to symlink the package into place:

```bash
ln -s /absolute/path/to/ai-modules/harness-plugins/opencode_v2/slash-skill-autocomplete \
  ~/.config/opencode/plugins/slash-skill-autocomplete
```

Restart OpenCode, then type `/` and filter by a skill name.

## Why the server, not the TUI or the GUI

OpenCode 2 exposes three plugin surfaces, and only one of them reaches every
client:

| Surface | Plugin entry | Command list |
| --- | --- | --- |
| Server | `.` | `/api/command`, read by every client |
| TUI | `./tui` | the terminal UI only |
| Desktop | `./gui-experimental` | the desktop app only |

A `./tui` plugin lists skills in a terminal and nowhere else; a
`./gui-experimental` bundle lists them in the desktop app and nowhere else. The
server is the shared origin, so registering there covers all of them with one
implementation and no bundling step.

The desktop resolves a typed command against the server's list and dispatches
it through `session.command({ name, text })`, so a server command behaves the
same there as in the terminal.

## Options

Configure through the `plugins` array in `opencode.json(c)` when installing as
a package:

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `log` | boolean | `false` | Logs each registration and invocation to the server console. |

## Collision rules

A skill is skipped when its ID matches a built-in command such as `review`,
`models`, or `skills`, or a command the server already exposes. Skipped skills
stay reachable through `@name` and the `/skills` dialog. The skip is reported
in tests rather than at runtime, so the menu stays free of duplicates.

## Development

```bash
bun install
bun test
bun run typecheck
```

## Limitations

- Upstream tracking: `anomalyco/opencode#35341` requests native slash
  registration for skills. If it lands, this plugin can be removed.

## License

MIT. See the repository [LICENSE](../../../LICENSE).
