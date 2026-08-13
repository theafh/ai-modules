---
title: OpenAI Codex
created: 2026-08-08
updated: 2026-08-13
type: entity
tags: [codex, skill, agent, hook, plugin, system-prompt, frontmatter, discovery, verification-gap]
sources: []
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
and read directly — `codex-cli 0.147.0-alpha.6.5`, shipped inside the ChatGPT
desktop application bundle rather than on `PATH` — and the skill-loading facts
below carry that stamp. The configuration claims were not re-checked against it.
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
`config.toml`.

### Skill loading

Read on 13 August 2026 out of the installed CLI binary, `codex-cli
0.147.0-alpha.6.5`. Finding the binary is itself the first fact: it ships inside
the ChatGPT desktop application at a fixed bundle path
(`ChatGPT.app/Contents/Resources/codex` on macOS), so a `PATH` lookup, a package
manager listing, and a shell `which` all miss an installed Codex, which the
instructions-slot section below already warns about for `codex debug models`.

Codex splits skill validation from skill loading, and the two enforce different
things. The skill-creation and install tooling requires `name` and `description`
in `SKILL.md` frontmatter and validates every key against a closed allowlist —
`name`, `description`, `license`, `allowed-tools`, `metadata` — rejecting
anything else with an `Unexpected key(s) in SKILL.md frontmatter` error. The
runtime loader is tolerant of what that allowlist rejects: skill files placed
under `skills/` by direct copy carrying keys outside the allowlist (`version`,
`author`) load and run. A skill's `version:` is therefore not merely unread here,
it is outside the tooling's allowlist entirely, while still tolerated at load
time. The skill's name comes from frontmatter, with the tooling offering a name
override that "defaults to SKILL.md frontmatter"; no equality between the name
and its directory is enforced.

At the listing layer the runtime truncates skill metadata to fit a skills
context budget, omits a skill whose metadata is too large to list, and caps the
`/skills` scan at a traversal limit — each visible in the binary's own strings
(`truncated skill metadata to fit skills context budget`, `Some skills were
omitted because their metadata is too large.`, `/skills scan reached its
traversal limit`).

One negative is worth recording because a task in this repository asserted the
opposite: the per-file loader messages the Claude Code build emits — `Skipping
plugin skill <path>: not a regular file or exceeds <N> byte limit`, `Multiple
skill files found`, `Failed to load skill from` — appear nowhere in the Codex
binary. That message family, and the one-mebibyte plugin-skill byte limit it
names, belong to
[Anthropic Claude Code](anthropic-claude-code.md)'s skill load path. Codex's
tooling resolves the exact uppercase `SKILL.md` spelling; whether its runtime
matches the filename case-insensitively is unverified.

### Agent roles

Codex registers spawnable roles only from standalone TOML files under
`~/.codex/agents/` or `<repo>/.codex/agents/`. Required keys are `name`,
`description`, and `developer_instructions`; optional keys are `model`,
`model_reasoning_effort`, `sandbox_mode`, and `mcp_servers`. There is no
per-agent tool allowlist.

The plugin schema carries no agent component, so a plugin-bundled Markdown agent
lands in the plugin cache without ever becoming a spawnable role. Generating TOML
is the only route.

Inheritance is expressed by omitting a key. A `model = "inherit"` line is
invalid output, because Codex reads it as a literal model name and
ChatGPT-backed sessions can reject it before the agent starts. Effort pins top
out at `xhigh` on current first-party models; `max` and `ultra` are accepted only
by preview models, and an unsupported pin surfaces as API errors on the child
agent's turns rather than as a clamp.

Built-in roles include `default`, `explorer`, and `worker`, which is worth
knowing when checking what actually registered.

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
`codex debug models` renders the model catalog as JSON with a resolved
`base_instructions` string and an `instructions_template` per model, and that
output is the only route: the on-disk `~/.codex/models_cache.json` carries no
base instructions. Any step invoking the binary needs feature detection rather
than a bare command name, because the executable can sit off `PATH` inside an
application bundle.

Resolved text is ordinary Markdown organised under named headings covering
personality and writing style, how to talk to the user, how to format a final
answer, editing and autonomy rules, destructive actions, and skill use. Both the
heading set and the overall length vary by model, and neither is documented
anywhere, so they are internal structure rather than a contract. A generator
that assembles a prompt by locating those headings re-derives them per model on
every run and fails loudly when an expected one is gone.

### Personality, verbosity, and profiles

`personality` is a closed enum of `none`, `friendly`, and `pragmatic`, honoured
only by models advertising `supportsPersonality`, and it is the one setting
switchable inside a running session through `/personality` or a per-thread
override. `model_verbosity` takes `low`, `medium`, or `high` on Responses API
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
  application, read on 13 August 2026, for the skill-loading facts.
- The `harness_portability` skill in this repository, before its August 2026
  split.
