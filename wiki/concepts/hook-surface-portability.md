---
title: Hook surface portability
created: 2026-08-08
updated: 2026-08-09
type: concept
tags: [hook, portability, claude, codex, opencode, antigravity, copilot, plugin]
sources: []
confidence: high
---

# Hook surface portability

## Definition

A hook is a policy that runs at a point in the agent's lifecycle, usually before
or after a tool call. Among the five harnesses whose hook contracts the research
here has worked out, Claude, Codex, Antigravity, OpenCode, and Copilot in VS
Code, no two agree on the configuration format, the event payload, or the way a
handler says no. Cursor is the one target left whose surface is unworked here,
which is unfinished coverage rather than a support decision.

The portable design that follows from that is one shared executable policy script
called from per-harness configuration, with the script itself written to detect
which harness invoked it.

## Current state of knowledge

### Four configuration schemas, plus one that is code

Claude and Codex both nest event names under a top-level `hooks` key, but their
schemas, event coverage, matcher names, trust model, and command environment
differ enough that the two configuration files stay separate.

Copilot in VS Code shares that top-level `hooks` key and then diverges on the one
level that matters. Claude and Codex fill the event array with **matcher groups**,
each group carrying its own nested `hooks` array. Copilot fills it with the hook
objects directly and documents no `matcher` field at all. The two shapes are close
enough to look interchangeable and far enough apart that a Claude file dropped
into a Copilot hook directory parses as valid JSON and then fails item validation,
because a matcher group carries no `command`. Near-miss compatibility is worse
than none, because it defers the failure to load time and hides it in a log.

Antigravity is a fourth declarative slot rather than a variant of any of them. Its
file is keyed by a named hook first and the event second, and it can sit loose in
a workspace or global directory or be bundled inside its plugin package.

OpenCode has no declarative hook configuration at all. A hook there is a
JavaScript or TypeScript plugin run by the embedded Bun runtime, which makes it a
different review and trust proposition from a Markdown or JSON component.

A four-harness plugin therefore ships four hook configurations over one shared
script, and reaches OpenCode through a thin bridge plugin that builds the
script's stdin envelope, runs it, and throws on a non-zero exit.

The layout this repository uses makes that concrete: `hooks/hooks.json` at the
plugin root for Claude, a `.codex-plugin/plugin.json` `hooks` entry pointing at a
Codex-native hook file beside it, an Antigravity `hooks.json` as a third file,
and an optional further Codex hook file kept outside the manifest for users who
deliberately merge it into their own user or project configuration layers. An
empty Codex hook file containing only an empty `hooks` object is the right
placeholder when a Claude hook exists but no Codex equivalent is ready yet.

### Four signalling contracts

This is the part a shared script gets wrong most easily. Claude and Codex block
by exit code over a snake_case envelope. Copilot also sends a snake_case envelope
on stdin and also treats exit 2 as a block, which makes it the closest thing to a
free target for a script already written for Claude; its considered decision is a
`permissionDecision` of `allow`, `deny`, or `ask` nested under
`hookSpecificOutput`, and it is fail-closed on `PreToolUse`, so a crash denies the
call. Antigravity reads a camelCase envelope and expects a JSON `decision` on
stdout. OpenCode blocks by throwing inside the plugin.

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

## Open questions

Two coverage decisions are unsettled. Whether an OpenCode bridge is worth its
experimental dependency is open work. And Cursor is now the only target whose
hook contract is unworked here, which is what stops the shared script claiming a
uniform guarantee across every tree it lands in; its deploy branch matches on a
Cursor-named configuration file that nobody has been able to write.

One question the Copilot research raised is settled rather than open. Both Copilot
products read `~/.claude/settings.json` for hooks, so a Claude hook merged there
would fire in VS Code too, and shipping both that merge and a Copilot-native file
would run the same guard twice in one session. The decision, taken on
9 August 2026, is to deliver natively and close the adoption path: Copilot gets
its own configuration in its own schema, the deploy switches the Claude hook
sources off through `chat.hookFilesLocations`, and Claude's hook configuration
stays out of `~/.claude/settings.json` entirely. The reasoning is on
[foreign directory adoption](foreign-directory-adoption.md), and the delivery work
is a task in the backlog.

## Related concepts

- [Agent definition portability](agent-definition-portability.md), the other
  surface where one file cannot serve every target.
- [The deployment model](deployment-model.md), which merges hook configuration as
  a JSON key rather than replacing the target file.

## Derived from

- Provider documentation for Claude, Codex, OpenCode, Antigravity, and Copilot,
  verified July and August 2026 and cited on the per-harness entity pages.
- A dry run of this repository's deploy script scoped to the hook type,
  9 August 2026, for the per-target routing recorded above.
- The `harness_portability` skill in this repository, before its August 2026
  split.
