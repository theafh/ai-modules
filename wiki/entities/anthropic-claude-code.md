---
title: Anthropic Claude Code
created: 2026-08-08
updated: 2026-11-24
type: entity
tags: [claude, skill, agent, hook, plugin, output-style, frontmatter, discovery, verification-gap]
sources: [raw/notes/delegation-probes-2026-10-04.md, raw/notes/micro-deployed-worker-home-probes-2026-10-08.md]
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
application bundle, unless a passage names its own later date. The settings
precedence order and the `claude config` closure were re-verified on 10 August
2026 against build 2.1.226 and carry that stamp where they appear; the passages
still resting on the earlier pass say so rather than inheriting the newer date.
Re-verify before relying on any of them.

## Key facts and dates

### Configuration roots

The user tree is `~/.claude/`, holding `skills/`, `agents/`, `commands/`,
`hooks/`, `output-styles/`, and `settings.json`. The project tree is `.claude/`
with the same shape, plus `settings.local.json` for local-scope settings. A
managed-settings directory exists as a third layer.

Settings resolve in a three-file order, strongest first: local project settings
in `.claude/settings.local.json`, then checked-in project settings in
`.claude/settings.json`, then the user-level `settings.json`. That order was
re-verified on 10 August 2026 against build 2.1.226, from the scope ordering the
build itself applies and from observed behaviour where a project-local value beat
a user-level one for the same key. Output styles layer their own discovery and
collision rules on top of it, recorded on
[Claude output styles](../concepts/claude-output-styles.md).

A headless `claude -p` worker started with `--setting-sources project,local`
reads only the project and local settings files, so the user-level
`settings.json`, and any `outputStyle` it carries, stays out of that worker. In
print mode a settings file that fails validation is dropped without an error: a
project `settings.json` with a trailing comma left its `outputStyle` unapplied
and printed nothing, which the CLI's own help also states for print mode. Both
were observed on 2 October 2026 against build 2.1.226 on one machine, with a
marker style whose reply token showed whether the style had loaded.

On 4 October 2026 a print-mode session of build 2.1.226 in a scratch repository
listed the user's deployed `auto_*` roles and skills at startup, so they reach a
sandboxed session as well. A worker given a scratch `CLAUDE_CONFIG_DIR`, with
`CLAUDE_SECURESTORAGE_CONFIG_DIR` set to the empty string and the test runner's
`_claude_worker_env()` environment, authenticated. It listed only the built-in
roles and skills ([probes](../raw/notes/delegation-probes-2026-10-04.md)). On
8 October 2026, against build 2.1.289, the same environment listed the skills in
the working directory's `.claude/skills/` beside the built-in and
organisation-managed skills, with only built-in agents. A skill deployed into the
scratch directory's own `skills/` was the copy the Skill tool loaded when the
prompt named it without a path
([probes](../raw/notes/micro-deployed-worker-home-probes-2026-10-08.md)).

### Standing instruction files

Two filenames carry project standing instructions to the model, `CLAUDE.md` and
`AGENTS.md`, and the build treats that pair as fixed rather than configurable.
Build 2.1.226, read on 1 September 2026, says so about itself on its
Codex-configuration import path: it lists Codex's `project_doc_*` settings among
the keys with no Claude equivalent, giving as the reason that Claude Code
hardcodes `CLAUDE.md` / `AGENTS.md` discovery. That entry sits in the same
import table as the notes on `sandbox_mode`, `web_search`, `hooks`, and
`[features]`, so it is the build's own account of what fails to carry over
rather than documentation about it. The two Codex settings it names are the ones
that make the filename set and its size bound configurable on that side, which
[OpenAI Codex](openai-codex.md) records.

Either filename works alone. Observed on 1 September 2026 across two runs on one
machine: a `claude -p` invocation whose working directory held an `AGENTS.md`
and no `CLAUDE.md` honoured a standing pre-commit rule written only in that
file, naming the rule back before acting on it. A test sandbox therefore needs
nothing but an `AGENTS.md` in the working directory to plant an agent-directed
obligation a worker will see, which is what
[verification surfaces](../concepts/verification-surfaces.md) depends on for any
eval that stages standing instructions.

The search for those files runs past the repository root. Observed on 2 October
2026 against build 2.1.226: marker instructions planted in one ancestor
directory's `CLAUDE.md`, and in another ancestor's `.claude/CLAUDE.md`, both
above the worker's git root, each reached a `claude -p` worker even under
`--setting-sources project,local`. A worker whose working directory sits under
the home directory therefore reaches `<home>/.claude/CLAUDE.md`, the user-level
file, through that walk whatever the setting sources say. A worker inside this
repository named the user-level file among its instructions under the flag,
while a sandbox outside the home directory named none; that pair rests on the
worker's report of its own context rather than on a marker. A worker that must
run free of every host instruction file therefore needs both the flag and a
working directory outside the home directory and outside any repository.

### Skill loading

What makes a skill file load and route here was read out of the installed
build's own load path, and it is on
[skill load paths](../concepts/skill-load-paths.md) beside the Codex equivalent.

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

### Delegation to helpers

[Claude Code delegation surfaces](../concepts/claude-delegation-surfaces.md)
covers how the Workflow and Agent tools delegate, how the shell tool handles
waits and searches, and the print-mode flags a headless worker relies on.

### File-edit read state

Verified on 29 August 2026 against the installed Claude Code build 2.1.226.
The `Edit` input validator checks a per-session file-read state and returns
`File has not been read yet. Read it first before writing to it.` when the
target has no complete `Read` record. Inspecting the target through Bash tools
such as `grep`, `cat`, or `tail` does not populate that state, so a workflow
that intends to call `Edit` stages the target with `Read`; Bash can still locate
an offset or narrow an oversized file before that `Read`.

### Oversized tool output

Observed on 15 November 2026 in a print-mode eval run: when a tool output is too
large to show inline, Claude Code writes it to a file under the session's
`tool-results/` directory and points the model at that file as the place to read
the full output. That file is harness session state rather than project content,
so a workflow that must read a large file in full pages it from that file's own
path with `sed -n` line ranges instead. What a bounded-isolation check counts as
an out-of-bounds read is on
[verification surfaces](../concepts/verification-surfaces.md); the print-mode
tool surfaces are on
[Claude Code delegation surfaces](../concepts/claude-delegation-surfaces.md).

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

`claude config` is gone, and instructions naming it will fail for whoever follows
them. It is no longer a CLI subcommand at all. That was re-verified on 10 August
2026 against build 2.1.226 by reading the build's own subcommand list, which
contains no `config` entry.

The `/output-style` command was retired as well, and v2.1.269 restored it. Its
history, and the settings file each remaining style route writes, are on
[Claude output style selection](../concepts/claude-output-style-selection.md).

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
- The Claude Code build 2.1.226 inspected on 29 August 2026, for the file-edit
  read-state guard and its exact error.
- The Claude Code build 2.1.226 inspected on 1 September 2026, for the hardcoded
  `CLAUDE.md` / `AGENTS.md` discovery, read out of its Codex-import warning
  table, together with two observed worker runs that honoured an `AGENTS.md`
  standing rule in a directory holding no `CLAUDE.md`.
- Claude Code build 2.1.226 on one machine, probed on 2 October 2026 with marker
  styles and marker instruction files in throwaway sandboxes, for the setting
  sources a headless worker reads, the silently dropped settings file, and the
  `CLAUDE.md` walk past the repository root.
- The `harness_portability` skill in this repository, before its August 2026
  split.
- The 2026-11-15 row for `immediate_ready_citations_survive` in
  `tests/task_auto_check/evals/README.md`, for the persisted copy Claude Code
  writes an oversized tool output to under the session's `tool-results/`
  directory.
