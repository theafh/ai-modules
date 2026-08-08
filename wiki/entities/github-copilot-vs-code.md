---
title: GitHub Copilot in VS Code
created: 2026-08-08
updated: 2026-08-08
type: entity
tags: [copilot, agent, skill, plugin, discovery]
sources: []
confidence: medium
---

# GitHub Copilot in VS Code

## Overview

GitHub Copilot in VS Code is a target here on the instruction-and-style surface.
It has the most direct global deposit of any non-Claude harness, and it reads
further into the Claude configuration tree than any other adopter.

Its hook, agent, and plugin specifics are not worked out to the same depth as the
other five targets. Read that as unfinished coverage rather than as a support
decision.

Facts below were verified on 7 August 2026 against
`code.visualstudio.com/docs/copilot/customization` (custom-instructions,
custom-chat-modes, overview) and
`code.visualstudio.com/docs/agent-customization/agent-plugins`. The plugin
surface is documented as preview and the mode file was renamed from
`*.chatmode.md` to `*.agent.md`, so re-verify before relying on any of it.

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

### Adoption of the Claude tree

With Agent Host enabled it reads user-level instructions from `~/.claude/rules`,
finds `CLAUDE.md` at a workspace root, in a `.claude` folder, or at
`~/.claude/CLAUDE.md`, and loads custom agents from a workspace `.claude/agents`
beside its own `.github/agents`.

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
  Copilot reads from in three places.
- [Cursor](cursor.md), the other append-only target, which lacks the documented
  user-level file root Copilot has.

## Derived from

- `code.visualstudio.com/docs/copilot/customization` and
  `/docs/agent-customization/agent-plugins`.
- The `harness_portability` skill in this repository, before its August 2026
  split.
