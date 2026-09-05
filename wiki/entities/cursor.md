---
title: Cursor
created: 2026-08-08
updated: 2026-09-05
type: entity
tags: [cursor, agent, frontmatter, discovery, verification-gap]
sources: []
confidence: high
---

# Cursor

## Overview

Cursor is an AI-first code editor and a target here for the agent-definition
surface and for standing instructions. It is the most limited target of the six
for anything that has to be deployed as a file, because its machine-wide
instruction carrier is not a file at all.

Facts below were verified on 7 August 2026 against `cursor.com/docs/context/rules`,
`/docs/agent/modes`, and the separate `cursor.com/help/customization/rules` page.
Re-verify before relying on them.

## Key facts and dates

### Agent definitions

Cursor reads Markdown agents from `.cursor/agents/`, `.claude/agents/`, and
`.codex/agents/`, in both project and user variants, and `.cursor` wins a name
conflict. It recognises `name`, `description`, `model`, `readonly`, and
`is_background`, and it tolerates foreign frontmatter keys, which is what lets
one shared Markdown file carry several harnesses' fields.

There is no tools field. The current tool identifiers are `Shell`, `Read`,
`Grep`, `Glob`, `LS`, `StrReplace`, and `Write`, with the shell tool named
`Shell` rather than `Bash`. A read-only role is expressed with `readonly: true`,
which restricts write permissions.

### Rules are the whole instruction mechanism

Rules are Markdown under `.cursor/rules/` with `*.mdc` filenames, and the
frontmatter selects one of four activation modes: Always Apply through
`alwaysApply: true`, Apply Intelligently from a `description`, Apply to Specific
Files from `globs`, and Apply Manually by mention. An applied rule is included at
the start of the model context rather than replacing anything already in it.

Nested `AGENTS.md` files are the frontmatter-free alternative, with the more
specific file taking precedence. Cursor also reads a project `CLAUDE.md` exactly
as it reads `AGENTS.md`, which makes it one of the harnesses adopting a
Claude-named file, at project scope rather than from the home directory.

Precedence among the documented kinds is Team Rules over Project Rules over User
Rules.

### The user rule is not a file

Two documentation pages agree that a user-level rule is stored in Cursor's own
settings rather than in any project directory. It applies across all projects on
that machine, and it is excluded from profile exports, so moving machines means
re-entering it or moving it into a project rule file.

An exhaustive enumeration of every path on the help page returns
`.cursor/rules/`, `*.mdc`, `AGENTS.md`, `CLAUDE.md`, and the legacy
`.cursorrules`, and no home-directory rules folder at all.

A User Rule also reaches Agent chat only, not Inline Edit or Tab, so a voice set
there governs part of the product rather than all of it.

### Modes

Modes exist and switch from the picker or with Shift and Tab, but the modes
documentation describes no user-defined mode carrying its own instructions. Treat a
mode as a tool-and-behaviour preset rather than a style slot until that changes.

## Verification gaps

A `~/.cursor/rules/` directory exists on at least one machine running Cursor, and
was empty there when checked on 8 August 2026, while no documentation page
mentions it. Treat a global rules file there as an
undocumented possibility to test empirically rather than as either a supported
path or a settled negative, and record which of observation or documentation any
claim about it rests on.

The empirical test is cheap: place a Markdown rule file carrying
`alwaysApply: true` and a distinctive, easily observed instruction in that
folder, start a fresh chat in a project with no rules of its own, and see whether
the instruction takes effect.

## Relationships to other entities

- [Anthropic Claude Code](anthropic-claude-code.md), whose agent directory and
  project `CLAUDE.md` Cursor reads.
- [GitHub Copilot in VS Code](github-copilot-vs-code.md), the other append-only
  target with a documented user-level instruction root, which Cursor lacks.

## Derived from

- `cursor.com/docs/context/rules`, `/docs/agent/modes`, and
  `cursor.com/help/customization/rules`.
- The `harness_portability` skill in this repository, before its August 2026
  split.
