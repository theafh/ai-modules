---
title: SST OpenCode
created: 2026-08-08
updated: 2026-11-05
type: entity
tags: [opencode, skill, agent, hook, system-prompt, frontmatter, discovery]
sources: [raw/notes/auto-check-open-weight-run-observations-2026-10-27.md]
confidence: high
---

# SST OpenCode

## Overview

OpenCode is SST's coding agent. It is a full target for skills, agents,
commands, and hooks, and it diverges from the other harnesses in four ways worth
holding in mind at once: its configuration tree is `~/.config/opencode` rather
than `~/.opencode`, it discovers artefacts from other harnesses' directories, its
hooks are code rather than configuration, and it defines each agent file's
frontmatter under a schema that drops keys it does not know and logs an
`ignored unsupported agent fields` warning.

Much of what is known about it was read off its source rather than its
documentation, which states none of the prompt-assembly behaviour. That makes
the claims here well-grounded and short-lived at the same time: they rest on the
loader source cross-checked against an installed build, which is the strongest
evidence in use anywhere in this wiki, and they describe internals that move
faster than a documented contract would. Re-verify by the date below rather than
by discounting the claims.

## Version boundary

The harness has two incompatible configuration generations under the same
`opencode` command. **V1** (through 1.19.x, the last desktop release of that
line) is the generation every fact on this page described before November 2026.
**V2** (2.x, verified on 2.2.5) changes the agent frontmatter schema, the plugin
API, and the server API, and it reads V1 artefacts through a compatibility
translation rather than rejecting them.

Facts below were verified in July 2026 against `opencode.ai/docs` and the issue
tracker, on 7 August 2026 against
`packages/opencode/src/session/instruction.ts`, `.../llm/request.ts`,
`.../prompt.ts`, and `.../system.ts` on the `dev` branch of
`github.com/sst/opencode`, cross-checked against the OpenCode desktop bundle
installed on that date, and on 5 November 2026 against OpenCode V2 2.2.5 through
its `--standalone` server's `/api/agent` and `/openapi.json` responses plus the
V2 documentation set. Re-verify before relying on any of them.

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
V2 also still discovers the V1 `agent/`, `mode/`, and `modes/` directories, and
treats files under `mode/` or `modes/` as primary agents. An agent's id comes
from its path relative to the agents directory, so a nested
`.opencode/agents/team/reviewer.md` registers as `team/reviewer`.

The frontmatter uses `mode` with values `primary`, `subagent`, or `all`, where
only `subagent` or `all` registers a spawnable subagent. A new custom agent
defaults to `primary`. V2's recognised keys are `description`, `mode`, `model`,
`system`, `permissions`, `steps`, `hidden`, `color`, `disabled`, and `request`;
the schema sets `additionalProperties: false`.

#### One file is read as one generation

V2 decides an agent file's format by its keys, not by a version marker. A file
carrying any of `permissions`, `request`, `system`, or `disabled` is read as V2,
and any V1 field in that same file is then ignored with an
`ignored unsupported agent fields` warning in the log. A file carrying only V1
fields is still translated from V1. Mixing the two formats in one file therefore
silently discards the V1 half rather than erroring, which is why a generated
variant writes one generation's keys only.

This was verified on 2.2.5 by deploying three files and reading the resolved
rules back from the standalone server's `/api/agent`. A V1-only file and a
V2-native file resolved to the same effective read-only policy, and a mixed file
logged the warning and kept only its V2 half.

#### Permissions

V2 replaced V1's `permission` object with an ordered `permissions` list of
`action` / `resource` / `effect` rules. `effect` is `allow`, `deny`, or `ask`,
and a rule matches by whole-value wildcards where `*` spans any character
including `/` and `?` matches exactly one. Rules combine in order and **the last
match wins**, so a broad rule is written first and its specific exceptions after
it. Lower-priority configuration loads first, then global rules, then agent
rules, so an agent rule overrides a broader global allow. When no rule matches
the default is `ask`, and an operation touching several resources denies if any
one resource denies.

The action names changed with the schema. `shell` replaced `bash`, `subagent`
replaced `task`, and `edit` gates `edit`, `write`, and `patch` alike, so no
separate `write` action exists. The built-in actions are `read`, `edit`, `glob`,
`grep`, `shell`, `subagent`, `skill`, `question`, `webfetch`, `websearch`,
`experimental_image_generate`, `external_directory`, and `execute`, plus one
`<server>_<tool>` action per MCP tool. `doom_loop` and `lsp` are not V2 Core
permission actions.

`execute` is the newest surface and it changes what a shell deny means. A deny on
`execute` removes Code Mode and the tools reachable only through it, while tools
nested inside Code Mode still enforce their own rules.

#### Deprecated and dropped fields

`temperature` is a V1 field with no V2 behaviour. V2 preserves the value but its
session runner does not send it with model requests, so per-agent sampling
belongs on a model variant instead. `name` is likewise not a V2 agent key,
because the id is derived from the filename. V2 logs
`ignored unsupported agent fields` for each key it drops, naming the file, so a
deploy that emits a V1 key is visible in the log rather than silent.

V1 `permission` maps onto the V2 list faithfully enough that both spellings
resolve to the same policy on 2.2.5, but V1 frontmatter is deprecated. A file
written for the long term carries `permissions`.

#### Reasoning level

A subagent's reasoning level follows its model. The subagent tool runs a spawned
subagent on its definition's `model` when one is set and otherwise on the
parent message's model, and it passes the parent's `variant` only in the second
case, so a subagent without a model of its own inherits both the parent's model
and its variant. A definition's own `variant` takes effect only beside a
`model`, and the client's resolver ignores a variant name the model does not
offer. Both read off
the installed desktop bundle's task tool and configuration loader on
27 October 2026, and the session store of a 26 October run showed every helper
on the parent's `max` variant
([run observations](../raw/notes/auto-check-open-weight-run-observations-2026-10-27.md)).
A model-agnostic helper therefore runs at whatever level the operator starts the
session with. V2 joins the pair in configuration as
`model: provider/model#variant`.

That level can starve a helper's answer. On 26 October 2026, five helper calls
on `deepseek/deepseek-v4.1-flash` at `max` each ended with finish reason
`length` after 32,000 reasoning tokens and no output tokens, so the parent
received an empty return
([run observations](../raw/notes/auto-check-open-weight-run-observations-2026-10-27.md)).

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
plugin run by OpenCode's embedded Bun runtime, loaded from `.opencode/plugins/`
or `~/.config/opencode/plugins/` at startup, so a local `.ts` plugin needs no npm
publish and no build step. The V2 loader discovers direct `.ts` and `.js` files
and immediate package directories under a `plugins/` directory. A configured
local plugin path must name a directory; a path to a single file is skipped.

V1's plugin contract does not run in V2. V1 exported an async function returning
a hooks object and blocked by throwing from `tool.execute.before`. V2 registers
hooks on a domain through a setup context instead, and one package can serve both
generations by default-exporting an object with a V1 `server()` and a V2
`setup()`. V2 reads the default export's id and setup.

The V2 hook domains are `session` (`prompt`, `context`, `compaction`, `retry`,
and native HTTP), `permission` (`evaluate`), `shell` (`create.before`), and
`tool` (`execute.before`, `execute.after`). `ctx.tool.hook("execute.before")`
sees the tool name and input before execution; `ctx.shell.hook("create.before")`
sees the command, cwd, timeout, shell, and environment before a shell call runs.

`permission.evaluate` is the better fit for a policy that inspects a path or
command. It runs after configured rules are evaluated and before the action or a
prompt, and it can set `effect` to `allow`, `ask`, or `deny` plus a `message`.
One asymmetry governs the design: the hook runs for `allow` and `ask` decisions
but **an explicit configured `deny` is final and never invokes the hook**. A
guard that must see every attempt therefore starts from an `ask` or `allow` rule
rather than a `deny`.

Three limits carry over from V1 and are worth encoding. Tool names are lowercase,
`edit`, `write`, `bash`, with no `apply_patch`. A before-hook guard remains
bypassable by delegation wherever the host does not run hooks inside spawned
subagents. And an `experimental`-named surface should be pinned to a tested
version.

The trust proposition differs from a Markdown or JSON component in kind, not
degree: a hook here is executable code with the plugin's full runtime reach.

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
