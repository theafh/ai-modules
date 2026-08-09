---
title: SST OpenCode
created: 2026-08-08
updated: 2026-08-09
type: entity
tags: [opencode, skill, agent, hook, system-prompt, frontmatter, discovery]
sources: []
confidence: high
---

# SST OpenCode

## Overview

OpenCode is SST's coding agent. It is a full target for skills, agents,
commands, and hooks, and it diverges from the other harnesses in four ways worth
holding in mind at once: its configuration tree is `~/.config/opencode` rather
than `~/.opencode`, it discovers artefacts from other harnesses' directories, its
hooks are code rather than configuration, and it passes unrecognised agent
frontmatter through to the model provider instead of ignoring or rejecting it.

Much of what is known about it was read off its source rather than its
documentation, which states none of the prompt-assembly behaviour. That makes
the claims here well-grounded and short-lived at the same time: they rest on the
loader source cross-checked against an installed build, which is the strongest
evidence in use anywhere in this wiki, and they describe internals that move
faster than a documented contract would. Re-verify by the date below rather than
by discounting the claims.

Facts below were verified in July 2026 against `opencode.ai/docs` and the issue
tracker, and on 7 August 2026 against
`packages/opencode/src/session/instruction.ts`, `.../llm/request.ts`,
`.../prompt.ts`, and `.../system.ts` on the `dev` branch of
`github.com/sst/opencode`, cross-checked against the OpenCode desktop bundle
installed on that date. Re-verify before relying on any of them.

## Key facts and dates

### Configuration tree

The global tree is `~/.config/opencode/` and the project tree is `.opencode/`,
each holding plural subdirectories `skills/`, `agents/`, `commands/`, and
`plugins/`. Singular names are tolerated for backwards compatibility; write the
plural form. A deploy step that hardcodes `~/.opencode` misses the real tree
entirely.

### Discovery of other harnesses' directories

Skills come from `.opencode/skills/`, and in the same walk up to the git
worktree also from `.claude/skills/` and `.agents/skills/`. Globally it reads
`~/.config/opencode/skills/`, `~/.claude/skills/`, and `~/.agents/skills/`, plus
any directory or HTTP catalog named in the `skills` array of `opencode.json`.
The later-scanned source wins on a duplicate skill id.

Rules resolve by first match rather than by accumulation, and that is the detail
that turns a deploy into a silent suppression. Globally the loader tests
`~/.config/opencode/AGENTS.md`, then `~/.claude/CLAUDE.md`, and stops at the
first that exists. Per project it tests `AGENTS.md`, then `CLAUDE.md`, then the
deprecated `CONTEXT.md`, walking up to the worktree, and stops at the first
filename with any match. Writing a global `~/.config/opencode/AGENTS.md`
therefore does not sit alongside a user's `~/.claude/CLAUDE.md`, it stops that
file loading at all.

Agents and commands load only from OpenCode's own directories, never from
`.claude/agents` or `.claude/commands`.

Three environment variables scope the adoption off. `OPENCODE_DISABLE_CLAUDE_CODE=1`
disables Claude Code compatibility broadly and, since v1.1.50, also stops
`.agents/skills` discovery. `OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1` stops only
the `~/.claude/CLAUDE.md` fallback. `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` stops
only `.claude` skill discovery. A configuration file toggle is an open feature
request rather than a shipped option.

The broad switch has a reach worth weighing before recommending it: `.agents/skills/`
is [Google Antigravity](google-antigravity.md)'s own native skill root, not a
Claude compatibility deposit, so setting it scopes away both a sibling tool's
`~/.claude` artefacts and the Google harness's native workspace skills in one
stroke.

### Agent definitions

Agents are Markdown under `.opencode/agents/` and `~/.config/opencode/agents/`.
The frontmatter uses `mode` with values `primary`, `subagent`, or `all`, where
only `subagent` or `all` registers a spawnable subagent, plus `description`,
`model` as `provider/model-id` inheriting the session model when omitted,
`temperature`, `prompt`, and a `permission` object.

`permission` maps lowercase capability keys to `allow`, `ask`, or `deny`. The
documented keys include `read`, `edit`, `glob`, `grep`, `bash`, `task`, `skill`,
`lsp`, `question`, `webfetch`, `websearch`, `external_directory`, and
`doom_loop`. The `edit` key gates all file modification, covering the `write`,
`edit`, and `patch` tools, so no separate `write` key exists. The older boolean
`tools` object is deprecated as of v1.1.1 and merged into `permission`.

Unrecognised frontmatter is neither ignored nor rejected. The agents
documentation states that any unrecognised option is passed through directly to
the provider as a model option, so a stray `version:` or `effort:` arrives in the
provider call as a bogus model parameter. That is why OpenCode always needs a
generated variant rather than a shared multi-harness file.

### Prompt assembly

Request preparation emits `agent.prompt ? [agent.prompt] : SystemPrompt.provider(model)`.
A set `prompt` therefore replaces the per-model base prompt that `system.ts`
selects, among them `anthropic.txt`, `gpt.txt`, `codex.txt`, and `gemini.txt`,
rather than joining it. The environment block, the `AGENTS.md` and `instructions`
content, the MCP instructions, and the skills catalogue are appended afterwards
unconditionally and survive the swap, as does a user-supplied system string.

The vendor prompts are sectioned Markdown, each organised under its own headings
covering tone, autonomy, editing constraints, tool policy, and response
formatting. Neither the heading set nor the length is documented, both differ per
vendor file, and both turn over with the build, so treat them as internal
structure to re-derive rather than as a contract to code against.

There is no supported way to read the resolved text, since OpenCode ships no
equivalent of `codex debug models`. Two routes reach it, and each has a cost. A
generator can read the prompt files from the public repository, at the risk of a
version mismatch against whatever build is installed locally. Or it can extract
the string from the `app.asar` bundle inside the application package, which was
confirmed to work against an installed build and which pins the text to that
exact build. Both are reads of an unsupported surface, so whichever is used, the
build the text came from gets recorded alongside it.

### The instructions array

`opencode.json` carries an `instructions` array accepting file paths and remote
URLs, and every discovered file is combined rather than one winning. This is the
member of the configuration tree a deploy should target, because it adds to the
user's own rules where a written `AGENTS.md` would suppress them.

Resolution rules matter for a deploy step. An entry beginning with an HTTP or
HTTPS scheme is fetched at prompt-assembly time under a five-second timeout and
contributes nothing on failure, making a remote entry a runtime dependency
rather than a deployed artefact. An entry beginning `~/` expands against the home
directory. An absolute path is globbed by its basename within its own directory,
and a relative entry globs upward from the working directory to the worktree.
Every match resolves to an absolute path collected in a set, so a repeated deploy
of the same entry is idempotent.

Each file is injected as `Instructions from: <path>` followed by its content, and
the block sits in the appended tail after the environment section. The tail is
appended to every request whatever agent is running, so instructions deployed
this way govern subagents too, which is wider reach than a Claude output style
has.

### Hooks

There is no declarative hook configuration. A hook is a JavaScript or TypeScript
plugin loaded from `.opencode/plugins/` or `~/.config/opencode/plugins/` at
startup and run by OpenCode's embedded Bun runtime, so a local `.ts` plugin needs
no npm publish and no build step. The plugin exports an async function returning
a hooks object; `tool.execute.before` fires before a tool runs, may mutate the
arguments, and aborts by throwing.

Three limits are worth encoding. `tool.execute.before` does not intercept tool
calls made by task-tool subagents (issue #5894), so a before-hook guard is
bypassable by delegation. The `permission.ask` plugin hook is defined but never
fired (issue #7006). Tool names are lowercase, `edit`, `write`, `bash`, with no
`apply_patch`.

An `experimental.chat.system.transform` hook fires on the assembled system array
and lets a plugin mutate it in place. It carries `experimental` in its own name,
so any dependency on it should be pinned to a tested version.

## Relationships to other entities

- [Anthropic Claude Code](anthropic-claude-code.md), whose configuration tree
  OpenCode reads from by default.
- [OpenAI Codex](openai-codex.md), the other harness whose base prompt can be
  re-derived and substituted.
- [Google Antigravity](google-antigravity.md), whose native `.agents/skills/`
  root OpenCode also scans.

## Derived from

- `opencode.ai/docs/plugins`, `/docs/permissions`, `/docs/agents`, `/docs/rules`.
- `github.com/sst/opencode` on `dev`, the session source files named above.
- The OpenCode desktop bundle installed on 7 August 2026.
- The `harness_portability` skill in this repository, before its August 2026
  split.
