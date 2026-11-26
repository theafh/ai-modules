---
title: OpenAI Codex
created: 2026-08-08
updated: 2026-11-26
type: entity
tags: [codex, skill, agent, hook, plugin, system-prompt, frontmatter, discovery, verification-gap]
sources: [raw/notes/delegation-probes-2026-10-04.md]
confidence: high
---

# OpenAI Codex

## Overview

Codex is OpenAI's coding agent and the second primary target for everything this
repository ships. It differs from Claude in three ways that shape most
portability decisions: its agent roles are TOML rather than Markdown, its plugin
schema carries no agent component, and it exposes a single whole-prompt
instructions slot rather than a layered style mechanism.

Facts below were verified on 7 August 2026 against
`learn.chatgpt.com/docs/config-file` and `developers.openai.com/codex/plugins/build`,
and against the `openai/codex` repository on `main`. On that date no local Codex
build had been located, so the configuration claims rest on documentation and
source rather than on observation. On 13 August 2026 an installed CLI was found
and read directly: `codex-cli 0.147.0-alpha.6.5`, shipped inside the ChatGPT
desktop application bundle rather than on `PATH`. The skill-loading facts read
from it are on [skill load paths](../concepts/skill-load-paths.md). The
configuration claims were not re-checked against it. Live probes of `codex exec`
on build 0.160.0 ran on 4 October 2026, and the passages that rest on them carry
that date ([probes](../raw/notes/delegation-probes-2026-10-04.md)).
Re-verify before relying on any of them.

## Key facts and dates

### Configuration roots and layer order

The user tree is `~/.codex/`, holding `config.toml`, `hooks.json`, `agents/`,
`skills/`, `prompts/`, and `plugins/cache/`. The project tree is `.codex/`.
Global instructions live at `~/.codex/AGENTS.md`, and per-project `AGENTS.md`
files are discovered with a size bound set by `project_doc_max_bytes` and
alternate filenames by `project_doc_fallback_filenames`.

Layers override in this order: system defaults, user `~/.codex/config.toml`, the
`--profile` file when one is passed, the project `.codex/config.toml` closest to
the working directory, then CLI flags and `--config` overrides. A profile or a
project configuration therefore outranks a global deploy.

Project `.codex/` layers load only for a trusted project. An instructions file
wired through a project configuration does nothing until the user trusts that
project, and the skip is silent rather than reported. A relative path inside a
project configuration resolves against the `.codex/` directory holding that
`config.toml`. A launcher can trust a project for a single run with
`-c 'projects."<dir>".trust_level="trusted"'`. The probes of 4 October 2026
trusted their projects that way, and the project roles and skill they staged
then loaded ([probes](../raw/notes/delegation-probes-2026-10-04.md)).

### Skill loading and the bundled binary

The skill load path read out of the installed CLI on 13 August 2026 is on
[skill load paths](../concepts/skill-load-paths.md) beside Claude's, with the
project skill discovery a probe observed on 4 October 2026. Finding the binary is
itself the first fact. It ships inside the ChatGPT desktop application rather
than on `PATH`. For build 0.160.0 on macOS it sits at
`ChatGPT.app/Contents/Resources/codex-cli/bin/codex`, and the account was signed
in through ChatGPT (4 October 2026,
[probes](../raw/notes/delegation-probes-2026-10-04.md)). A `PATH` lookup, a
package manager listing, and a shell `which` all miss an installed Codex, which
the instructions-slot section below already warns about for `codex debug models`.

### Agent roles

Codex registers spawnable roles only from standalone TOML files. Those are the
user's `~/.codex/agents/*.toml` and, in a trusted project, the project's
`.codex/agents/*.toml`. They sit beside the built-in roles `default`,
`explorer`, and `worker`, as `codex exec` on build 0.160.0 showed on
4 October 2026 ([probes](../raw/notes/delegation-probes-2026-10-04.md)).
Required keys are `name`, `description`, and `developer_instructions`; optional
keys are `model`, `model_reasoning_effort`, `sandbox_mode`, and `mcp_servers`.
There is no per-agent tool allowlist. Setting `sandbox_mode = "read-only"` did
not make a spawned role read-only, as
[agent definition portability](../concepts/agent-definition-portability.md)
records beside the other hosts' levers.

The plugin schema carries no agent component, so a plugin-bundled Markdown agent
lands in the plugin cache without ever becoming a spawnable role. Generating TOML
is the only route.

Inheritance is expressed by omitting a key. A `model = "inherit"` line is
invalid output, because Codex reads it as a literal model name and
ChatGPT-backed sessions can reject it before the agent starts. Effort pins top
out at `xhigh` on current first-party models; `max` and `ultra` are accepted only
by preview models, and an unsupported pin surfaces as API errors on the child
agent's turns rather than as a clamp.

### Delegation to helpers

On build 0.160.0, `codex exec` exposes built-in sub-agent tools:
`collaboration.spawn_agent`, `wait_agent`, `send_message`, `list_agents`,
`interrupt_agent`, and `followup_task`. It also exposes the goal tools
`create_goal`, `get_goal`, and `update_goal`. Passing `--disable multi_agent`
did not stop spawning (4 October 2026,
[probes](../raw/notes/delegation-probes-2026-10-04.md)).

### Headless runs through codex exec

A test runner drives Codex through `codex exec`, and the probes of 4 October
2026 recorded how that works on build 0.160.0
([probes](../raw/notes/delegation-probes-2026-10-04.md)).
`codex exec --json --dangerously-bypass-approvals-and-sandbox -C <dir> <prompt>`
runs one turn, and `codex exec ... resume <thread_id> <prompt>` resumes it. The
events are `thread.started`, carrying `thread_id`; `turn.started`;
`item.started` and `item.completed`, carrying the item types `agent_message`,
`command_execution`, `file_change`, and `collab_tool_call`; and
`turn.completed`, carrying `usage`. The stream listed only the `wait`
collaboration call as an item, with empty receiver ids. It held no spawn item,
yet the spawned helper's file appeared. A session started with `-s read-only` is
confined as a whole, as
[agent definition portability](../concepts/agent-definition-portability.md)
records among the session-level levers.

### The single instructions slot

`BaseInstructions` in `codex-rs/protocol/src/models.rs` is one `text` string
plus a provenance that is either `Model { model }`, generated from that model's
template, or `Custom`, explicitly configured and documented as surviving model
changes unchanged. Nothing composes the two.

Pointing `model_instructions_file` at a file therefore fills the whole slot and
freezes it across model switches. The built-in templates ship as one Markdown
prompt file per model family under `codex-rs/core`, so the shipped set turns
over with the model lineup. Tool schemas travel separately as a tools JSON, so a
replacement loses operating prose rather than tool definitions.

The resolved text is readable, which is what makes a substitution possible.
`codex debug models` renders the installed build's model catalog as JSON, with
each model's resolved `base_instructions` string beside the
`instructions_template` it was rendered from, and that render is the
authoritative source (verified 26 November 2026 against `codex-cli
0.169.0-alpha.11.1`). The on-disk `~/.codex/models_cache.json` is a snapshot
rather than an empty cache: each model carries its instructions text as
`model_messages.instructions_template`, stamped with the `client_version` that
fetched it, so it can lag the installed build. Any step invoking the binary
needs feature detection rather than a bare command name, because the
executable can sit off `PATH` inside an application bundle.

Resolved text is ordinary Markdown organised under named headings covering
personality and writing style, how to talk to the user, how to format a final
answer, editing and autonomy rules, and skill use. `# Destructive actions` is a
heading some models carry rather than a universal member of the set: the
`gpt-5.6` and `gpt-reserve` models and the `codex-auto-review` model carry it,
while the `gpt-6` family omits it (verified 26 November 2026 across the twelve
models in the installed catalog). Both the heading set and the overall length
vary by model, and neither is documented anywhere, so they are internal
structure rather than a contract. A generator that assembles a prompt by
locating those headings re-derives them per model on every run and fails loudly
when an expected one is gone.

### Personality, verbosity, and profiles

`personality` is a deprecated compatibility setting, sourced from the
`personality` entry in the configuration reference
(`learn.chatgpt.com/docs/config-file/config-reference`, read 25 November 2026).
It takes `none`, `friendly`, or `pragmatic`; `friendly` and `pragmatic` no
longer select a style, and `none` scopes to the built-in personality section it
would otherwise compose while leaving an explicit instruction override
unchanged. `model_verbosity` takes `low`, `medium`, or `high` on Responses API
providers.

A profile is `~/.codex/<profile>.config.toml`, selected with `--profile <name>`
and holding top-level keys rather than a nested table. One profile can set an
instructions file, a personality, and a verbosity together, which makes it the
nearest composite of a Claude output style, at the cost that selection is a
launch flag rather than a persisted key.

### Hooks

Hook sources are additive layers: user `~/.codex/hooks.json` or inline `[hooks]`
in the user config, the same pair at project level, managed configuration, and
plugin-bundled hooks. Higher-precedence layers do not replace lower ones, so the
same command present in two layers runs twice.

The plugin default hook file is `hooks/hooks.json` at the plugin root, and a
`.codex-plugin/plugin.json` `hooks` entry overrides it with Codex-native files,
inline objects, an empty `{"hooks": {}}`, or several files. Manifest hook paths
resolve against the plugin root, stay inside it, and start with `./`.

The JSON is strict and minimal: a top-level `hooks` key, event names mapping to
matcher groups, matcher groups holding handlers. A custom top-level field such
as `description` does not belong there; descriptive prose goes in the plugin
manifest, the README, or the skill body instead. Use one matcher group with a
regex such as `^(apply_patch|Bash)$` when the same handler, timeout, and status
message apply to several tools, and separate groups when behaviour, arguments,
timeout, status text, or policy differs.

A project `.codex/` hook is the right choice for repository-local activation
without a plugin install, for an experiment before packaging, or for a repository
that intentionally owns its hook policy. It is the wrong choice inside a plugin's
own source repository, where the installed plugin already contributes the hook
and the committed project hook becomes a second active source.

Non-managed command hooks are listed but skipped until the user reviews and
trusts the current definition, and trust is tied to that definition, so an edit
requires review again. After editing a marketplace-installed plugin, refresh the
cache with `codex plugin add <plugin>@<marketplace>` and inspect
`~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/`. Restarting Codex
alone can reuse stale cached files.

## Relationships to other entities

- [Anthropic Claude Code](anthropic-claude-code.md) is the other primary target.
- [SST OpenCode](sst-opencode.md) is the other harness whose base prompt can be
  re-derived and substituted. See
  [system prompt substitution across harnesses](../comparisons/system-prompt-substitution-across-harnesses.md).
- [Google Antigravity](google-antigravity.md) shares the workspace
  `.agents/plugins/` path with the Codex marketplace registration, so one
  directory carries two harnesses' differently schemad manifests.

## Derived from

- `learn.chatgpt.com/docs/config-file` (`config-basic`, `config-advanced`,
  `config-reference`) and `developers.openai.com/codex/plugins/build`.
- `github.com/openai/codex` on `main`, `codex-rs/protocol/src/models.rs` and
  `codex-rs/core`.
- The `codex-cli 0.147.0-alpha.6.5` binary bundled in the ChatGPT desktop
  application, read on 13 August 2026, for where the binary ships.
- The `harness_portability` skill in this repository, before its August 2026
  split.
