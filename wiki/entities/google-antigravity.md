---
title: Google Antigravity
created: 2026-08-08
updated: 2026-08-08
type: entity
tags: [antigravity, skill, agent, hook, plugin, discovery, verification-gap]
sources: []
confidence: medium
---

# Google Antigravity

## Overview

Antigravity is Google's agent harness and the replacement target for the retired
Gemini CLI, which Google shut down on 18 June 2026. It is a full target here
across skills, agents, rules and workflows, hooks, plugin bundles, and
supervised background sidecars.

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

Two workspace paths collide with other harnesses. `.agents/skills/` is where
Codex project-level skill deployment and OpenCode discovery converge on
Antigravity's native root, so one directory serves three harnesses and a
duplicate skill id resolves by whichever tool scans last. `.agents/plugins/`
holds Antigravity's `plugin.json` bundles while a Codex marketplace registration
also lands at `.agents/plugins/marketplace.json`, so one directory carries two
harnesses' differently schemad manifests.

### Global roots split by artefact class

Exactly two artefact classes diverge by product and the rest converge, so the
question resolves per class rather than per product.

Skills split three ways: `~/.gemini/config/skills/<skill-folder>/` on
`/docs/skills`, `~/.gemini/antigravity/skills/<skill-folder>/` on
`/docs/ide/skills`, and `~/.gemini/antigravity-cli/skills/` on `/docs/cli/plugins`.
Plugins split two ways: `~/.gemini/config/plugins/` for 2.0 and the IDE against
`~/.gemini/antigravity-cli/plugins/<plugin_name>/` for the CLI. Everything else
is single-rooted under `~/.gemini/config/`: `agents/`, `hooks.json`,
`mcp_config.json`, and `sidecars/`. Global rules are the single file
`~/.gemini/GEMINI.md`, one level above `config/`, and the CLI's own preferences
sit at `~/.gemini/antigravity-cli/settings.json`. So a claim that one global
deploy reaches the IDE, the CLI, and 2.0 holds for agents, hooks, MCP, and
sidecars, and fails for skills and plugins.

Configuration roots are not output paths. Hook payload examples show transcripts
and artifacts landing under a `brain/<conversationId>/` subtree,
`~/.gemini/antigravity/brain/…` on the 2.0 page and
`~/.gemini/antigravity-ide/brain/…` on the IDE page, which is the only place a
fourth `antigravity-ide` tree appears.

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

`tools` is a YAML array of lowercase snake_case names, and the failure mode is
the one to plan around: an unmapped or misspelled name may cause the subagent
process to hang during execution rather than fail validation at load. Two
documented surfaces publish names, and nothing says they are different
namespaces. The subagents page names `view_file`, `grep_search`, and
`run_command`. The hooks page's matcher list adds `write_to_file`,
`replace_file_content`, `multi_replace_file_content`, `list_dir`, `find_by_name`,
`search_web`, `read_url_content`, `manage_task`, `schedule`, `list_permissions`,
`ask_permission`, `invoke_subagent`, `define_subagent`, `send_message`,
`manage_subagents`, `ask_question`, and `generate_image`.

No canonical tool list is published anywhere in the documentation, which is
exactly why the hang matters: there is no registry to validate a name against.
The widely circulating `read_file` and `edit_file` names appear on neither page.

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

A bundle can also carry sidecars: long-running background processes the harness
supervises and restarts, each its own directory holding a `sidecar.json` naming
the command, restart behaviour, and environment. They are discovered at
`~/.gemini/config/plugins/<pluginName>/sidecars/` for a plugin and
`~/.gemini/config/sidecars/` standalone, addressed as
`<pluginName>/<sidecarName>`. A sidecar is the one component that keeps running
between turns, so it is a process-lifecycle surface rather than a configuration
file.

### Rules and workflows

Workspace rules are Markdown under `.agents/rules/`, capped at 12,000 characters
each, with four activation modes: Manual, Always On, Model Decision, and Glob.
Global rules are the single `~/.gemini/GEMINI.md`. Workflows are Markdown files
in either scope, capped at the same 12,000 characters, and invoked as
`/workflow-name` slash commands. The rules documentation describes no tone,
persona, output-format, or system-prompt-replacement feature at all, presenting
rules purely as constraints the agent follows.

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
