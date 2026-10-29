---
title: Hook delivery design
created: 2026-10-01
updated: 2026-10-29
checked: 2026-08-09
type: concept
tags: [hook, deployment, portability, plugin, claude, codex, antigravity, copilot, cursor, opencode]
confidence: high
---

# Hook delivery design

## Definition

This page records how this repository delivers its one shared hook policy: the
files it ships, where the deploy script routes each of them, what that routing
does on Copilot, and the decision that settles Copilot delivery. The harness
contracts those choices answer to are on
[hook surface portability](hook-surface-portability.md).

The routing facts come from a dry run of the deploy script on 9 August 2026, and
the Copilot loader facts come from the Copilot research of the same date.
Re-verify before relying on either.

## Current state of knowledge

### The layout

The layout this repository uses makes the shared-script design concrete:
`hooks/hooks.json` at the plugin root for Claude, a `.codex-plugin/plugin.json`
`hooks` entry pointing at a Codex-native hook file beside it, an Antigravity
`hooks.json` as a third file, and an optional further Codex hook file kept
outside the manifest for users who deliberately merge it into their own user or
project configuration layers. An empty Codex hook file containing only an empty
`hooks` object is the right placeholder when a Claude hook exists but no Codex
equivalent is ready yet.

### What ships and where the deploy routes it

The repository ships one shared policy script and three harnesses' worth of
configuration. The script is a single shell file. The configurations are
Claude's plugin-native `hooks.json`, a Codex pair splitting the plugin-manifest
file from the config-layer file, and one Antigravity file.

The deploy script routes them unevenly, and the unevenness is worth knowing
before reading a deployed tree. It copies the shell script into the hook
directory of Claude, Cursor, Codex, Antigravity, and Copilot, and marks it
executable. It merges the Codex config-layer file into that harness's own hook
configuration entry by entry, so an entry ai-modules owns is added, updated at
the position it holds, or removed while every foreign entry stays where it was,
and it merges the Antigravity file under its own named-hook key. Claude and
Cursor each have a merge branch that matches on a
harness-named configuration file the repository does not ship, so Claude's hook
configuration reaches a machine through plugin install rather than through the
deploy, and Cursor receives the script with nothing wired to call it. OpenCode
has no branch at all.

### Copilot receives every file

Copilot is the one route with no name filter, so every hook configuration in the
tree lands in its hook directory, including the four written for other harnesses.
That deposit is not idle clutter. `~/.copilot/hooks` is the documented user-scope
hook root for **both** Copilot in VS Code and GitHub Copilot CLI, and the CLI
reference states that every `*.json` in it loads at start, in alphabetical order,
with every matching hook running. Four foreign files land where two products
actively parse them, which is the deposit
[foreign directory adoption](foreign-directory-adoption.md) argues against, made
by this repository's own installer rather than by a harness overreaching.

Nothing executes today, and only because two independent failures both hold. The
three files shaped `{"hooks": {"PreToolUse": […]}}` are structurally valid, so
each is accepted and then each item is dropped, since a Claude or Codex matcher
group carries no `command` field; the Antigravity file has no top-level `hooks`
key at all and contributes nothing. Independently, every `command` value is
unusable here anyway, because two name `${CLAUDE_PLUGIN_ROOT}` or `${PLUGIN_ROOT}`
which no Copilot product sets, and two are relative `./hooks/…` paths that only
the merge routes rewrite, never the copy route Copilot is on. What remains is a
validation error logged per file at every session start of two products. The
drop-the-item rule is documented in GitHub's CLI reference and is not restated on
the Preview VS Code page, so the VS Code loader's behaviour here is inferred.

The finding cuts the other way too. Copilot's stdin envelope is snake_case like
Claude's and exit 2 blocks, which is the signalling the shared script already
implements, so what is missing is not capability but a Copilot-shaped file: hook
objects flattened directly under the event name rather than wrapped in matcher
groups, and an absolute command path.

### Copilot gets native delivery

Both Copilot products read `~/.claude/settings.json` for hooks, as
[hook surface portability](hook-surface-portability.md) records, so a merged
Claude hook and a Copilot-native file would run the same guard twice in one
session. The decision, taken on 9 August 2026, is to deliver natively and close
the adoption path: Copilot gets its own configuration in its own schema, the
deploy switches the Claude hook sources off through `chat.hookFilesLocations`,
and Claude's hook configuration stays out of `~/.claude/settings.json` entirely.
The reasoning is on [foreign directory adoption](foreign-directory-adoption.md),
and the delivery work is a task in the backlog.

## Open questions

The coverage questions this delivery inherits stay on
[hook surface portability](hook-surface-portability.md): whether an OpenCode
bridge is worth its experimental dependency, and the Cursor hook contract that
is still unworked.

## Related concepts

- [Hook surface portability](hook-surface-portability.md), for the contracts each
  configuration answers to.
- [The deployment model](deployment-model.md), whose entry merge writes the
  Codex hook configuration and whose named-key merge writes Antigravity's.
- [Foreign directory adoption](foreign-directory-adoption.md), for why delivery
  goes native instead of through an adopted tree.
- [GitHub Copilot in VS Code](../entities/github-copilot-vs-code.md), for the hook
  root both Copilot products read.

## Derived from

- A dry run of this repository's deploy script scoped to the hook type,
  9 August 2026, for the per-target routing recorded above.
- GitHub's Copilot CLI reference, for the load-at-start and drop-the-item rules,
  as cited on the Copilot entity page.
