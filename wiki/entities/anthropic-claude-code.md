---
title: Anthropic Claude Code
created: 2026-08-08
updated: 2026-08-09
type: entity
tags: [claude, skill, agent, hook, plugin, output-style, frontmatter, discovery]
sources: []
confidence: high
---

# Anthropic Claude Code

## Overview

Claude Code is Anthropic's coding agent, available as a terminal CLI, a desktop
application, a web application, and IDE extensions. It is one of the two primary
targets for everything this repository ships, and it is the harness with the
richest plugin component set: skills, agents, hooks, MCP servers, and output
styles all load from a plugin.

It is also the only harness with a configurable system-prompt style layer, which
is why [Claude output styles](../concepts/claude-output-styles.md) is a page of
its own rather than a section here.

Facts below were verified on 7 August 2026 against `code.claude.com/docs/en/`
and against the Claude Code build installed on that date plus the desktop
application bundle, unless stated otherwise. Re-verify before relying on any of
them.

## Key facts and dates

### Configuration roots

The user tree is `~/.claude/`, holding `skills/`, `agents/`, `commands/`,
`hooks/`, `output-styles/`, and `settings.json`. The project tree is `.claude/`
with the same shape, plus `settings.local.json` for local-scope settings. A
managed-settings directory exists as a third layer.

Project settings outrank user settings. Output styles layer their own discovery
and collision rules on top of that, recorded on
[Claude output styles](../concepts/claude-output-styles.md).

### Agent definitions

Agents are Markdown files with YAML frontmatter. Claude silently ignores unknown
frontmatter keys, which is what allows one shared file to carry several
harnesses' native fields side by side. The `tools:` field takes a comma-separated
string of capitalised names such as `Read, Grep, Glob, Bash`, and omitting the
field inherits every tool.

Plugin-bundled `agents/*.md` load natively from an installed plugin, but three
keys are ignored for security when the agent arrives that way: `hooks`,
`mcpServers`, and `permissionMode`.

Since version 2.1.198 a subagent inherits the parent session's extended-thinking
state and effort level, with a frontmatter `effort` key acting as a per-agent
override. Releases before 2.1.198 spawn subagents without extended thinking
whatever the frontmatter says.

### Hooks

Plugin hooks live at `hooks/hooks.json` in the plugin root or inline in the
plugin manifest. Command hooks receive event JSON on stdin and commonly resolve
plugin files through `${CLAUDE_PLUGIN_ROOT}`. Blocking is by exit code over a
snake_case envelope, which is the detail that breaks a script shared with
Antigravity. See
[hook surface portability](../concepts/hook-surface-portability.md).

A plugin component change other than a skill needs `/reload-plugins` or a
restart before a running session sees it.

### Safe mode

Safe mode disables a custom output style whichever way it arrived, so any rule
that must hold in every session belongs somewhere other than a style. The
annotation it writes on the saved value is on
[Claude output styles](../concepts/claude-output-styles.md) with the rest of the
style behaviour.

### Retired surfaces

Two documented activation routes are gone, and instructions naming either will
fail for whoever follows them. The standalone `/output-style` command was
deprecated in v2.1.73 and removed in v2.1.91. `claude config` is no longer a CLI
subcommand at all.

`/config` is an interactive terminal dialog, so a desktop-application session
cannot reach the picker. On the desktop build inspected on 7 August 2026 the
settings file was the only route.

## Relationships to other entities

- [OpenAI Codex](openai-codex.md) is the other primary target, and the pair
  drives most of the union-of-native-fields design.
- [SST OpenCode](sst-opencode.md), [Cursor](cursor.md), and
  [GitHub Copilot in VS Code](github-copilot-vs-code.md) all read files from the
  `~/.claude` tree or from a project `.claude` directory, which makes Claude the
  most adopted harness of the set. See
  [foreign directory adoption](../concepts/foreign-directory-adoption.md).
- [Google Antigravity](google-antigravity.md) borrows Claude's hook event names
  while implementing none of its hook behaviour.

## Derived from

- `code.claude.com/docs/en/output-styles` and `/docs/en/plugins-reference`.
- The Claude Code build and desktop bundle installed on 7 August 2026.
- The `harness_portability` skill in this repository, before its August 2026
  split.
