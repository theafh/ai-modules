---
title: Isolating VS Code from foreign harness config
created: 2026-08-09
updated: 2026-11-25
type: procedure
tags: [copilot, claude, codex, discovery, portability, hook]
sources: []
confidence: high
---

# Isolating VS Code from foreign harness config

VS Code is the only harness in this set that documents per-path location maps for
foreign consumption, through `settings.json` keys a deploy step can write. Those
maps scope the editor's **Local** harness; the Copilot harness reads the
repository `.claude` settings files directly whatever they say. Turn off the
third-party agent integration, and treat the aggregated session list as a
separate problem with its own switch.

## When this applies

Copilot in VS Code applies instructions or runs hooks that were deployed for
Claude, or the chat sidebar lists past sessions from other harnesses, including
ones archived elsewhere. VS Code reads user-level instructions from
`~/.claude/rules`, finds `CLAUDE.md` at a workspace root, in a `.claude` folder,
or at `~/.claude/CLAUDE.md`, loads agents from a workspace `.claude/agents`, and
reads hooks from `.claude/settings.json`, `.claude/settings.local.json`, and
`~/.claude/settings.json`. See
[GitHub Copilot in VS Code](../entities/github-copilot-vs-code.md).

## The rule

Handle the two problems separately, because they have different switches.

**For the Local harness's discovery**, use the two location maps. Each maps a path
to a boolean, and a path set to `false` is disabled even when it is a documented
default, so the Local harness stops reading a path while your own entries stay on.

```jsonc
"chat.hookFilesLocations": {
  ".claude/settings.json": false,
  ".claude/settings.local.json": false,
  "~/.claude/settings.json": false
},
"chat.instructionsFilesLocations": {
  "~/.claude/rules": false
}
```

Write only the paths being disabled, so entries the user set survive the edit.
Because these are ordinary settings keys, a deploy step can merge them, unlike
the Cursor equivalent.

**The hooks map does not scope the Copilot harness; the instructions map does.**
The hooks page, re-read on 25 November 2026, documents `chat.hookFilesLocations`
under "Existing Local hooks" and states "Local editor settings such as
`chat.hookFilesLocations` do not configure Copilot discovery". It also states
that the Copilot harness reads inline hook settings in
`.github/copilot/settings.json`, `.github/copilot/settings.local.json`, and
`~/.copilot/settings.json`, plus repository `.claude/settings.json` and
`.claude/settings.local.json`. A Claude hook therefore cannot be switched off for
the Copilot harness from editor settings: ship a Copilot-native hook config
instead and accept the possible duplicate run, which is harmless for a guard that
denies idempotently.

`chat.instructionsFilesLocations` behaves differently. The migration page, re-read
on 26 November 2026, states that VS Code forwards instruction files discovered in
additional configured locations to Agent Host harnesses **including Copilot**, and
that an additional location supplements the harness's built-in locations without
removing them. Setting a documented default such as `~/.claude/rules` to `false`
therefore keeps that folder out of what the editor forwards to Copilot, and also
stops it loading in the Local harness.

**For third-party agent integration**, set
`"github.copilot.chat.claudeAgent.enabled": false`. That removes the Claude
session type and its session listing together.

**For the aggregated session list**, right-click the Chat view header and uncheck
**Show Sessions**, or set `"chat.viewSessions.enabled": false`. Chat keeps
working, and native history stays reachable through the **Chat: Show History**
command. Reach for this when session history is the complaint, since it hides
every provider's list rather than filtering one.

**For Codex sessions specifically**, disable the Codex extension in the
Extensions view. Uninstalling is unnecessary, and no setting suppresses its
session history alone.

## Pitfalls

**Archived elsewhere does not mean archived here.** Archive state lives in each
harness's own metadata rather than in the transcript files on disk, so VS Code
imports the raw history and everything an operator archived in another harness
reappears. Hiding the list is the only lever; there is nothing to re-archive.

**There is no per-provider session filter.** Neither the Chat view nor the Agents
window filters the session list by provider, so the choice is the whole list or
none of it. Per-session right-click actions are the only finer control.

**Keep the agent switch and the file switches apart.**
`github.copilot.chat.claudeAgent.enabled` governs running Claude as a harness
inside VS Code. It does not stop VS Code reading Claude's files, which is what
the two location maps do for the Local harness. Setting one and expecting the
other's effect is the easy mistake here.

**A hook merged into `~/.claude/settings.json` is a two-harness deploy.** Both
Copilot products read that file for hooks and run every matching hook from every
source, so a guard installed for Claude also fires in VS Code. No documented
setting stops the Copilot harness from reading it, so deliver a Copilot-native
config and let the guard deny idempotently rather than expecting the hook
location map to close the route.

## See Also

- [GitHub Copilot in VS Code](../entities/github-copilot-vs-code.md) for the
  instruction roots and the adoption paths these switches scope.
- [Hook surface portability](../concepts/hook-surface-portability.md) for the
  two-harness hook consequence, and
  [hook delivery design](../concepts/hook-delivery-design.md) for how this
  repository delivers around it.
- [Isolating OpenCode from foreign harness config](isolating-opencode-from-foreign-config.md)
  and [Isolating Cursor from foreign harness config](isolating-cursor-from-foreign-config.md)
  for the sibling harnesses.
