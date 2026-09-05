---
title: Anthropic Claude Code
created: 2026-08-08
updated: 2026-09-05
type: entity
tags: [claude, skill, agent, hook, plugin, output-style, frontmatter, discovery, verification-gap]
sources: []
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

### Skill loading

Five mechanics govern whether a skill file is found, loaded, and routable. All
five were read on 13 August 2026 out of the installed Claude Code build 2.1.226
and its desktop counterpart 2.1.227, which agree, and they are the load path's
own code rather than documentation about it.

The skill filename is matched **case-insensitively** against the pattern
`skill.md` over the file's basename, so `SKILL.md`, `skill.md`, and `Skill.md`
all load. When one directory holds more than one file matching that pattern, the
loader takes the first and logs `Multiple skill files found in <dir>, using
<name>`, which makes the file it loads a matter of directory order rather than
of authorial intent.

A plugin skill is read through a guard that stats the path and requires a
**regular file no larger than 1048576 bytes**, one mebibyte. Failing either
condition the loader skips the skill entirely and warns `Skipping plugin skill
<path>: not a regular file or exceeds <N> byte limit`, interpolating the limit
from its own constant. The stat follows symbolic links, so a symlink resolving to
a regular file loads normally and only a broken link, a link to a directory, or a
non-regular file trips the guard. A frontmatter the parser cannot destructure
fails separately with `Failed to load skill from <path>: <error>`.

The name a skill is **registered and routed under** is its frontmatter `name:`
when that field is a non-empty string, falling back to the containing
directory's basename only otherwise. The result is sanitised by replacing every
character outside `[a-zA-Z0-9_-]` with a hyphen, then namespaced as
`<plugin>:<skill>`. A `name:` disagreeing with its directory therefore loads,
lists, and routes without complaint. The alignment this repository requires is
its own convention rather than a harness constraint, which is why
[skill family architecture](../concepts/skill-family-architecture.md) records the
auditor reporting the mismatch below its blocking tier.

A skill's `version:` is read by no field that gates loading or routing. The
frontmatter key is recognised, and every schema that accepts it marks it
optional, so a skill with no `version:` loads and activates normally. Any
requirement for the field is a repository convention.

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

### File-edit read state

Verified on 29 August 2026 against the installed Claude Code build 2.1.226.
The `Edit` input validator checks a per-session file-read state and returns
`File has not been read yet. Read it first before writing to it.` when the
target has no complete `Read` record. Inspecting the target through Bash tools
such as `grep`, `cat`, or `tail` does not populate that state, so a workflow
that intends to call `Edit` stages the target with `Read`; Bash can still locate
an offset or narrow an oversized file before that `Read`.

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

Two documented activation routes are gone, and instructions naming either will
fail for whoever follows them. The standalone `/output-style` command was
deprecated in v2.1.73 and removed in v2.1.91; those two version boundaries rest
on the 7 August 2026 pass and were not re-checked, while build 2.1.226 was
confirmed on 10 August 2026 to carry no such command, holding
`.claude/output-styles/` only as a path string. `claude config` is no longer a CLI
subcommand at all, re-verified on 10 August 2026 against that build by reading its
own subcommand list, which contains no `config` entry.

Both closures land on one consequence worth stating outright: no interactive and
no CLI surface writes the user-level `outputStyle`, so editing the user-level
settings file is the only route to a machine-wide style. The `/config` picker is
not that route, because it writes project-local scope, as recorded on
[Claude output styles](../concepts/claude-output-styles.md).

`/config` is an interactive terminal dialog, so a desktop-application session
cannot reach the picker. On the desktop build inspected on 7 August 2026 the
settings file was the only route. This is the page's weakest claim and the reason
it carries the `verification-gap` tag: it was not re-checked on 10 August 2026,
and the only support added since is an operator report that the style cannot be
changed from the desktop application, which observes the symptom rather than the
mechanism. Treat the desktop route as owed verification rather than settled.

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
- The skill load path read out of installed builds 2.1.226 and 2.1.227 on
  13 August 2026, for the skill-loading facts above.
- The Claude Code build 2.1.226 inspected on 29 August 2026, for the file-edit
  read-state guard and its exact error.
- The Claude Code build 2.1.226 inspected on 1 September 2026, for the hardcoded
  `CLAUDE.md` / `AGENTS.md` discovery, read out of its Codex-import warning
  table, together with two observed worker runs that honoured an `AGENTS.md`
  standing rule in a directory holding no `CLAUDE.md`.
- The `harness_portability` skill in this repository, before its August 2026
  split.
