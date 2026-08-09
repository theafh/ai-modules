---
title: Google Antigravity
created: 2026-08-08
updated: 2026-08-09
type: entity
tags: [antigravity, skill, agent, hook, plugin, discovery, verification-gap]
sources: []
confidence: medium
---

# Google Antigravity

## Overview

Antigravity is Google's agent harness and the replacement target for the retired
Gemini CLI, which Google shut down on 18 June 2026. This repository deploys
skills, agents, and hooks to it, and the open style work targets the global rules
file. Workflows, plugin bundles, and sidecars are surfaces nothing here writes.

It diverges from the others in four ways: a native `.agents/` workspace tree that
two other harnesses also read, global roots that differ by artefact class rather
than by product, declarative `hooks.json` and `plugin.json` bundles, and a
separate Python SDK whose lifecycle hooks are a second hook surface entirely.

Facts below were verified in July 2026 against `antigravity.google/docs`
(`/skills`, `/subagents`, `/hooks`, `/plugins`, `/mcp`, `/sidecars`,
`/rules-workflows`, `/ide/skills`, `/ide/plugins`, `/ide/hooks`, `/cli/plugins`,
`/cli/settings`, `/cli/gcli-migration`) and on 7 August 2026 against
`/docs/rules-workflows`. Re-verify before relying on them.

## Key facts and dates

### The workspace tree

The workspace tree is uniform across products: `.agents/{skills,agents,rules,plugins}/`
at the workspace root, plus `.agents/hooks.json` and `.agents/mcp_config.json`.
`.agent/` is named as backwards compatibility by the skills and rules pages, and
`_agents/` by the plugins pages.

Two workspace paths collide with other harnesses. `.agents/skills/` is also read
by Codex project deployment and OpenCode discovery, so a duplicate skill id
resolves by whichever tool scans last, worked through in
[foreign directory adoption](../concepts/foreign-directory-adoption.md).
`.agents/plugins/` holds Antigravity's `plugin.json` bundles beside a Codex
`marketplace.json`, two schemas in one directory.

### Global roots split by artefact class

Antigravity ships as three products, and its global configuration diverges by
artefact class rather than by product: skills and plugins split across the
products while everything else converges under `~/.gemini/config/`. So one global
deploy reaches all three products for agents, hooks, MCP, and sidecars, and fails
to for skills and plugins. Global rules are the single file `~/.gemini/GEMINI.md`,
one level above `config/`. The per-class paths, what they mean for a deploy, and
the output tree that is not a configuration root are on
[Antigravity global configuration roots](../concepts/antigravity-global-roots.md).

### Skills

A skill is a `SKILL.md` under the Agent Skills open standard, with `description`
required and `name` optional and defaulting to the folder name. It is
model-invoked through a progressive-disclosure sequence of discovery, activation,
then execution, which makes this repository's own skills near drop-in rather
than a format port.

### Subagents

Subagents are Markdown at `.agents/agents/<name>.md` or
`.agents/agents/<name>/agent.md` in a workspace, at `~/.gemini/config/agents/`
with the same two shapes globally, and at `plugins/<plugin_name>/agents/` inside
a plugin bundle.

Documented frontmatter is `name` and `description`, both required; `tools` as a
string array defaulting to `[]`; `mainAgent` and `subagent` as booleans both
defaulting to `true`, so a definition registers as a spawnable subagent unless
`subagent: false` says otherwise; `model` defaulting to `inherit`;
`commandExecutionPolicy` defaulting to `sandbox`; `mcpServers` as an object
array; and `skills` and `plugins` as string arrays of dependency paths.

The documented `model` tier list is exactly `inherit`, `flash`, and `pro`. A
`flash_lite` tier circulates in secondary sources but appears neither in the
frontmatter table nor among the models `/docs/models` lists, and `hidden` and
`inheritMcp` are likewise community sourced only. Treat all three as unsupported.

The CLI reads the same definitions from the same roots and refers back to this
one specification, so the subagent schema is unified across products even where
skill and plugin roots diverge.

No reasoning-effort key is documented at all. The `model` tier field is the only
depth control the subagents page sources.

### Tool vocabulary and its failure mode

`tools` is a YAML array of lowercase snake_case names, drawn from a vocabulary
that two documentation pages publish incompletely and none publishes in full. The
failure mode is the one to plan around: an unmapped or misspelled name may cause
the subagent process to hang during execution rather than fail validation at load,
and with no canonical list there is nothing to check a name against first. Both
name lists, the one-namespace question, and what follows for a generator are on
[Antigravity tool vocabulary](../concepts/antigravity-tool-vocabulary.md).

### Hooks

Configuration is a `hooks.json` in `.agents/` for a workspace and
`~/.gemini/config/` globally, with five events: `PreToolUse`, `PostToolUse`,
`PreInvocation`, `PostInvocation`, and `Stop`.

The file is keyed by a named hook first and the event second, unlike Claude and
Codex which nest event names under a top-level `hooks` key:

```json
{"my-linter-hook": {"PostToolUse": [{"matcher": "run_command",
  "hooks": [{"type": "command", "command": "./scripts/lint.sh", "timeout": 10}]}]}}
```

`matcher` selects tools by exact name, `""` or `"*"` for all, `"a|b"`
alternatives, or a regex such as `"browser_.*"`.

The stdin payload carries two casings at once. The envelope is camelCase, with
`toolCall`, `stepIdx`, `conversationId`, `workspacePaths`, `transcriptPath`, and
`artifactDirectoryPath`, while the per-tool arguments nested under
`toolCall.args` are PascalCase, so a `run_command` call arrives as
`toolCall.args.CommandLine` and `toolCall.args.Cwd`. There is no top-level `cwd`,
and only `run_command`'s argument keys are documented, so a guard inspecting file
paths is more robust scanning every string value under `toolCall.args` than
guessing a per-tool key.

On stdout a `PreToolUse` handler returns a `decision` of `allow`, `deny`, `ask`,
or `force_ask`, optionally with a `reason` and a `permissionOverrides` array of
entries shaped like `command(npm test)`, and a `Stop` handler returns `continue`
to keep going. That is a decision value rather than an exit code, which is the
trap described in
[hook surface portability](../concepts/hook-surface-portability.md).

The Antigravity SDK (`pip install google-antigravity`, Python only) is a second
hook surface: programmatic lifecycle hooks in three categories, inspect, decide,
and transform, across nine lifecycle points. Those are in-process Python
callbacks for an agent the SDK builds, not a configuration file the IDE or CLI
reads.

### Plugin bundles and sidecars

The manifest is a `plugin.json`, and bundles live at `.agents/plugins/` in a
workspace and `~/.gemini/config/plugins/` globally, alongside the CLI's own root.
Documented components are skills under `skills/`, rules under `rules/`, MCP
servers through `mcp_config.json`, and hooks through `hooks.json`.

A bundle can also carry sidecars, long-running background processes the harness
supervises between turns. They are a process-lifecycle surface rather than a
configuration one, and nothing here deploys them, so the detail stays with
Google's `/docs/sidecars`.

### Rules and workflows

Workspace rules are Markdown under `.agents/rules/`, global rules are the single
`~/.gemini/GEMINI.md` applied across all workspaces, and workflows are Markdown
in either scope invoked as `/workflow-name` slash commands. The 12,000-character
cap is stated for rules files and workflow files generally, without exempting the
global one, so read it as binding on `~/.gemini/GEMINI.md` too. The four
activation modes, Manual, Always On, Model Decision, and Glob, are documented for
workspace rules only, and the global file names no mode because it is always
applied. The rules documentation describes no tone, persona, output-format, or
system-prompt-replacement feature at all, presenting rules purely as constraints
the agent follows. This section was re-checked against `/docs/rules-workflows` on
9 August 2026.

## Verification gaps

Four questions are open, each recorded as a gap rather than guessed, and they are
collected with their evidence in
[what remains unverified about Google Antigravity](../queries/antigravity-open-verification-gaps.md):
frontmatter tolerance, whether plugin-bundled agents register, which of
`GEMINI.md` and `AGENTS.md` wins, and whether the harness reads another tool's
directories.

## Relationships to other entities

- [OpenAI Codex](openai-codex.md) and [SST OpenCode](sst-opencode.md) both touch
  the `.agents/` workspace tree.
- [Anthropic Claude Code](anthropic-claude-code.md), whose hook event names
  Antigravity reuses with entirely different semantics.

## Derived from

- `antigravity.google/docs`, the pages listed above.
- The `harness_portability` skill in this repository, before its August 2026
  split.
