---
title: GitHub Copilot in VS Code
created: 2026-08-08
updated: 2026-08-09
type: entity
tags: [copilot, agent, skill, plugin, hook, discovery]
sources: []
confidence: high
---

# GitHub Copilot in VS Code

## Overview

GitHub Copilot in VS Code is a target here on the instruction-and-style surface
and on hooks. It has the most direct global deposit of any non-Claude harness,
and it reads further into the Claude configuration tree than any other adopter.

Facts below were verified on 7 August 2026 against
`code.visualstudio.com/docs/copilot/customization` (custom-instructions,
custom-chat-modes, overview) and
`code.visualstudio.com/docs/agent-customization/agent-plugins`, and on
9 August 2026 against `code.visualstudio.com/docs/agent-customization/hooks`
plus GitHub's own `docs.github.com/en/copilot/reference/hooks-reference` and
`/concepts/agents/hooks`. The plugin and hook surfaces are both documented as
preview and the mode file was renamed from `*.chatmode.md` to `*.agent.md`, so
re-verify before relying on any of it.

## Two products share one user root

"Copilot in VS Code" and GitHub Copilot CLI are separate products that read the
same `~/.copilot/` user tree. VS Code names `~/.copilot/instructions` and
`~/.copilot/hooks`; the CLI reads `~/.copilot/hooks/*.json`,
`~/.copilot/settings.json`, and machine policy directories of its own. Anything
deposited under `~/.copilot/` therefore reaches both products, which is wider
than a target named for the editor suggests, and it is the reason the hook
contract below has to be read as two overlapping specifications rather than one.

## Key facts and dates

### Instruction roots

Instructions are the always-on carrier, and they combine rather than compete.
Copilot's own roots are `.github/copilot-instructions.md` at the workspace root,
`*.instructions.md` files whose `applyTo` glob scopes them to matching files, an
auto-detected workspace `AGENTS.md`, and `~/.copilot/instructions` for the user
profile. The `chat.instructionsFilesLocations` setting adds further workspace
locations.

The user-profile root applies across every workspace and sits at the top of the
documented precedence, above repository and organization instructions. No
settings key activates it, which is one moving part fewer than the Claude, Codex,
and OpenCode global deposits each need, and it makes this the cheapest target to
reach.

### Hooks

Agent hooks are documented as **Preview**, with the configuration format and
behaviour stated as subject to change, so anything built on them is pinned to a
version rather than to a contract.

VS Code looks in four places. At workspace scope it reads `.github/hooks/*.json`,
`.claude/settings.json`, and `.claude/settings.local.json`. At user scope it reads
`~/.copilot/hooks` and `~/.claude/settings.json`. The scope table names the user
directory without stating the filename pattern inside it, which the CLI reference
settles as `*.json`.

The schema puts hook objects directly under the event name:

```json
{"hooks": {"PreToolUse": [{"type": "command", "command": "./guard.sh",
  "timeout": 30, "cwd": "", "env": {}, "osx": "", "linux": "", "windows": ""}]}}
```

That shape is the trap for anything ported from Claude or Codex. Those two put
**matcher groups** in the event array, each group carrying its own nested `hooks`
array, while VS Code puts the hook objects there directly and documents no
`matcher` field at all. A Claude or Codex hook file dropped in unchanged parses as
valid JSON and then fails item-level validation, because the matcher group carries
no `command`.

Eight events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
`PreCompact`, `SubagentStart`, `SubagentStop`, and `Stop`.

A hook receives JSON on stdin carrying `timestamp`, `cwd`, `session_id`,
`hook_event_name`, and `transcript_path`, which is snake_case and the same shape
family as Claude's envelope. It returns JSON on stdout carrying `continue`,
`stopReason`, and `systemMessage`. Exit 0 means success and stdout is parsed;
**exit 2 is a blocking error**. A `PreToolUse` decision rides inside
`hookSpecificOutput` as `permissionDecision`, valued `allow`, `deny`, or `ask`.

The CLI's surface is a superset worth knowing before writing one file for both. It
adds `http` and `prompt` hook types beside `command`, `bash` and `powershell` keys
for per-platform scripts, a `version` key, a `disableAllHooks` switch, matcher
regexes compiled as `^(?:PATTERN)$`, machine policy directories under
`/etc/github-copilot/policy.d/*.json`, repository `.github/hooks/*.json`, inline
`hooks` fields in several settings files, and further events including
`SessionEnd`, `UserPromptTransformed`, `PostToolUseFailure`, `PermissionRequest`,
`ErrorOccurred`, and `Notification`.

The CLI reference is also the only place the loading rules are written down, and
they decide what a stray file in the directory costs. Files in a hook directory
load in alphabetical order, every matching hook from every source runs, a
malformed **item** is dropped and logged while valid siblings in the same file
still load, and a structural error (invalid JSON, a bad `version`, a non-array
event list) rejects the whole file. `PreToolUse` command hooks are fail-closed, so
a crash or a non-zero exit denies the tool call, while a timeout is always
fail-open.

### Adoption of the Claude tree

Copilot reaches further into `.claude` than any other harness here, and hooks are
the deepest reach of all. For instructions it reads user-level rules from
`~/.claude/rules`, finds `CLAUDE.md` at a workspace root, in a `.claude` folder,
or at `~/.claude/CLAUDE.md`, and loads custom agents from a workspace
`.claude/agents` beside its own `.github/agents`. For hooks it reads
`.claude/settings.json` and `.claude/settings.local.json` at workspace scope and
`~/.claude/settings.json` at user scope, which is the same file Claude's own hook
configuration is merged into.

That last one has a consequence worth stating plainly: a hook merged into
`~/.claude/settings.json` for Claude fires in VS Code as well, whether or not
anyone intended a second harness to run it.

Unlike every other adopter here, VS Code lets each of those paths be switched off
individually. `chat.hookFilesLocations` and `chat.instructionsFilesLocations` each
map a path to a boolean, and setting one to `false` disables it even when it is a
documented default, so `.claude/settings.json`, `~/.claude/settings.json`, and
`~/.claude/rules` come off one at a time. Keep
`github.copilot.chat.claudeAgent.enabled` separate in your head: it governs
running Claude as a harness inside VS Code, not reading Claude's files.

Those are adoption paths rather than deploy targets. Writing to `~/.claude/rules`
would put one file in front of two harnesses and hand Copilot a Claude-shaped
artefact. See
[foreign directory adoption](../concepts/foreign-directory-adoption.md).

### Custom agents

A custom agent is a `*.agent.md` file carrying `description`, `name`, `tools`,
`model`, `handoffs`, and `agents` frontmatter, kept in `.github/agents` for a
workspace and `~/.copilot/agents` for the user, and picked from a dropdown in the
chat view.

Its body is prepended to the user chat prompt rather than merged into the system
prompt. That is a third injection position, beside a Claude style's system-prompt
placement and OpenCode's appended system section, and prose written to read as
standing system instruction arrives inside the user turn instead.

### Plugins

An agent plugin bundles MCP servers, skills, agents, hooks, and slash commands
under a `plugin.json`. The documented component list carries no instructions
entry, so a standing style has no plugin channel. A bundled agent delivers the
prose as a persona the user has to select, and a bundled skill loads on demand
when the model judges it relevant. Neither is standing.

## Relationships to other entities

- [Anthropic Claude Code](anthropic-claude-code.md), whose configuration tree
  Copilot reads from for instructions, agents, and now hooks.
- [Cursor](cursor.md), the other append-only target on the instruction surface,
  which lacks the documented user-level file root Copilot has.
- [Hook surface portability](../concepts/hook-surface-portability.md) for how
  this contract sits beside the other four.

## Derived from

- `code.visualstudio.com/docs/copilot/customization`,
  `/docs/agent-customization/agent-plugins`, and
  `/docs/agent-customization/hooks`.
- `docs.github.com/en/copilot/reference/hooks-reference` and
  `/en/copilot/concepts/agents/hooks` for the CLI superset and the loading rules.
- The `harness_portability` skill in this repository, before its August 2026
  split.
