---
title: Isolating Cursor from foreign harness config
created: 2026-08-09
updated: 2026-08-09
type: procedure
tags: [cursor, claude, codex, discovery, portability, skill]
sources: []
confidence: high
---

# Isolating Cursor from foreign harness config

Cursor has exactly one off-switch for reading other harnesses' configuration, it
lives in the settings interface rather than in a file, and it takes `CLAUDE.md`
away along with the skills. Turn it off, restart, and give Cursor a native home
for any instructions that were arriving through the Claude file.

## When this applies

Every skill or agent appears twice in Cursor, once from its own tree and once
from a Claude or Codex deployment, or a `.claude` artefact is overriding a
`.cursor` one. Cursor reads agents from `.claude/agents/` and `.codex/agents/`
beside its own and reads a project `CLAUDE.md` exactly as it reads `AGENTS.md`,
which is what produces the duplication. See [Cursor](../entities/cursor.md).

## The rule

Open Cursor settings, go to **Rules, Skills and Subagents**, labelled just
**Rules** in older builds, and turn off **Include third-party Plugins, Skills,
and other configs**. Restart Cursor afterwards so already-loaded skills drop out.
With it off, Cursor discovers only its native locations and stops reading the
Claude and Codex trees.

Confirm the flip rather than trusting the toggle's appearance. The setting is
stored in Cursor's internal state database at
`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, under the
`ItemTable` key `cursor/thirdPartyExtensibilityEnabled`, which reads `false` once
the toggle is off. Read that database read-only; never write it.

Then replace what the toggle took away. It governs `CLAUDE.md` as well as skills,
so any repository whose only instruction file is `CLAUDE.md` becomes
instruction-less in Cursor. Add an `AGENTS.md` beside each `CLAUDE.md` that
Cursor should still see, and give machine-wide preferences a Cursor-native home
through User Rules in the settings interface.

## Pitfalls

**A deploy script cannot set this.** The value lives in the internal state
database rather than in `settings.json`, so it is a per-machine manual step for
every new machine, and it belongs in whatever post-deploy checklist the project
keeps.

**An older key name circulates.** Secondary material and earlier builds name
`allowThirdPartyPluginImports`. The key observed in the state database on
9 August 2026 is `cursor/thirdPartyExtensibilityEnabled`, so a search for the
older name finds nothing and reads as an absent setting.

**It is all or nothing.** Filtering by provider, keeping Codex while dropping
Claude, is an open feature request rather than shipped behaviour. That costs
nothing where every harness already receives its own deployed variant.

**The command-line interface ignores the toggle.** The setting governs the
editor, so a CLI agent still reads the foreign trees. Where a workflow drives
Cursor from the command line, treat the isolation as unachieved there.

**Two mechanisms that look like they should work do not.** Neither
`.cursorignore` nor the per-item disable control affects loading of `.claude`
content; both operate above the loader. The global toggle is the only mechanism
that takes effect today.

## See Also

- [Cursor](../entities/cursor.md) for what it reads natively and the open
  question about a home-directory rules folder.
- [Foreign directory adoption](../concepts/foreign-directory-adoption.md) for the
  standing position and the per-harness switch inventory.
- [Isolating OpenCode from foreign harness config](isolating-opencode-from-foreign-config.md)
  and [Isolating VS Code from foreign harness config](isolating-vs-code-from-foreign-config.md)
  for the sibling harnesses.
