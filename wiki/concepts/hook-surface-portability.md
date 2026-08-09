---
title: Hook surface portability
created: 2026-08-08
updated: 2026-08-09
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
Cursor and Copilot in VS Code expose hook surfaces of their own whose contracts
are not worked out here, which is unfinished coverage rather than a support
decision.

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

### What this repository ships and deploys today

One shared policy script and three harnesses' worth of configuration. The script
is a single shell file. The configurations are Claude's plugin-native
`hooks.json`, a Codex pair splitting the plugin-manifest file from the
config-layer file, and one Antigravity file.

The deploy script routes them unevenly, and the unevenness is worth knowing
before reading a deployed tree. It copies the shell script into the hook
directory of Claude, Cursor, Codex, Antigravity, and Copilot, and marks it
executable. It merges the Codex config-layer file into that harness's own hook
configuration under the `hooks` key, and the Antigravity file under its own
named-hook key. Claude and Cursor each have a merge branch that matches on a
harness-named configuration file the repository does not ship, so Claude's hook
configuration reaches a machine through plugin install rather than through the
deploy, and Cursor receives the script with nothing wired to call it. OpenCode
has no branch at all.

Copilot is the one route with no name filter, so every hook configuration in the
tree lands in its hook directory, including the files written for other
harnesses. That is the same foreign-file deposit
[foreign directory adoption](foreign-directory-adoption.md) argues against, made
here by this repository's own installer rather than by a harness reading someone
else's tree, and it should be filtered to the files Copilot can act on.

## Open questions

Three coverage decisions are unsettled. Whether an OpenCode bridge is worth its
experimental dependency is open work. Whether Claude and Cursor should receive
the harness-named configuration files their deploy branches already match on has
never been argued either way, so the branches sit ready for a source that may
never be written. And whether Cursor's and Copilot's contracts get worked out to
the depth of the other four decides whether the shared script can claim a uniform
guarantee across every target it lands on.

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
