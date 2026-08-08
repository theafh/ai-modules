---
title: Hook surface portability
created: 2026-08-08
updated: 2026-08-08
type: concept
tags: [hook, portability, claude, codex, opencode, antigravity, plugin]
sources: []
confidence: high
---

# Hook surface portability

## Definition

A hook is a policy that runs at a point in the agent's lifecycle, usually before
or after a tool call. Among the four harnesses whose hook contracts the research
here has worked out, Claude, Codex, Antigravity, and OpenCode, no two agree on
the configuration format, the event payload, or the way a handler says no.
Cursor and Copilot in VS Code expose hook surfaces of their own, and the deploy
script already copies hook files into both configuration trees, but their
contracts are not worked out here, so read them as unfinished coverage rather
than absence.

The portable design that follows from that is one shared executable policy script
called from per-harness configuration, with the script itself written to detect
which harness invoked it.

## Current state of knowledge

### Three configuration schemas, plus one that is code

Claude and Codex both nest event names under a top-level `hooks` key, but their
schemas, event coverage, matcher names, trust model, and command environment
differ enough that the two configuration files stay separate.

Antigravity is a third declarative slot rather than a variant of either. Its file
is keyed by a named hook first and the event second, and it can sit loose in a
workspace or global directory or be bundled inside its plugin package.

OpenCode has no declarative hook configuration at all. A hook there is a
JavaScript or TypeScript plugin run by the embedded Bun runtime, which makes it a
different review and trust proposition from a Markdown or JSON component.

A three-harness plugin therefore ships three hook configurations over one shared
script, and reaches OpenCode through a thin bridge plugin that builds the
script's stdin envelope, runs it, and throws on a non-zero exit.

The layout this repository uses makes that concrete: `hooks/hooks.json` at the
plugin root for Claude, a `.codex-plugin/plugin.json` `hooks` entry pointing at a
Codex-native hook file beside it, an Antigravity `hooks.json` as a third file,
and an optional further Codex hook file kept outside the manifest for users who
deliberately merge it into their own user or project configuration layers. An
empty Codex hook file containing only an empty `hooks` object is the right
placeholder when a Claude hook exists but no Codex equivalent is ready yet.

### Three signalling contracts

This is the part a shared script gets wrong most easily. Claude and Codex block
by exit code over a snake_case envelope. Antigravity reads a camelCase envelope
and expects a JSON `decision` on stdout. OpenCode blocks by throwing inside the
plugin.

A script that only ever exits non-zero therefore fails open silently on
Antigravity. Matching event names make this worse rather than better: Antigravity
uses Claude's event names while implementing none of Claude's behaviour, so a
`PreToolUse` hook that works under Claude parses the wrong field names and exits
into a handler that wanted a decision value. The event name matching is a reason
to check the envelope, not a reason to skip the check.

A portable script parses the envelope by the field names the invoking harness
actually sends, and branches its response shape the same way. It reads event
input from stdin when available, tolerates missing or extra fields, detects the
harness through documented environment variables, and resolves the plugin root
from an environment variable with a script-relative fallback.

### Layers are additive, so duplicates are the normal failure

Codex loads hooks from user configuration, project configuration, managed
configuration, and enabled plugins, and a higher-precedence layer does not
replace a lower one. All matching hooks run. The same command present in a plugin
hook and a user hook produces duplicate reviews and duplicate execution.

Diagnose a surprising hook count by enumerating active sources before touching
any script: the plugin manifest hook path, the plugin root hook file, user and
project files, inline tables, managed policy, the installed plugin cache, and the
review interface. A displayed count can reflect separate sources, separate
matcher groups, parse errors beside valid hooks, or stale cached plugin files.

### Guarantees differ by harness

A hook's guarantee is only as strong as its interception point. On OpenCode,
`tool.execute.before` does not intercept tool calls made by task-tool subagents,
so a before-hook guard is bypassable by delegation and gives a weaker guarantee
than the same guard on Claude or Codex. Its `permission.ask` hook is defined but
never fired, so interception has to use the before hook regardless.

Where a harness offers a declarative permission model, that model can cover
simple path protection without a hook at all, but it cannot express conditional
logic such as a branch check.

### Runtime loading is verified before shipping

Confirm a target actually loads plugin-bundled hooks before shipping a blocking
or lifecycle hook inside a plugin, and document the trust, enablement, or reload
step that makes it active. On Codex a non-managed command hook is listed but
skipped until the user reviews and trusts the current definition, and an edit
requires review again. On Claude a plugin component change needs a reload or
restart.

## Open questions

The repository ships hook configurations for Claude, Codex, and Antigravity, and
no OpenCode bridge yet. Whether the bridge is worth its experimental dependency
is open backlog work.

## Related concepts

- [Agent definition portability](agent-definition-portability.md), the other
  surface where one file cannot serve every target.
- [The deployment model](deployment-model.md), which merges hook configuration as
  a JSON key rather than replacing the target file.

## Derived from

- Provider documentation for Claude, Codex, OpenCode, and Antigravity, verified
  July and August 2026 and cited on the per-harness entity pages.
- The `harness_portability` skill in this repository, before its August 2026
  split.
