---
title: Cursor
created: 2026-08-08
updated: 2026-10-09
type: entity
tags: [cursor, agent, skill, frontmatter, discovery, verification-gap]
sources:
  - raw/notes/agent-delegation-host-observations-2026-09.md
  - raw/notes/delegation-probes-2026-10-04.md
  - raw/notes/cursor-style-injection-probes-2026-10-06.md
  - raw/notes/cursor-skill-shadowing-probes-2026-10-08.md
  - raw/notes/eval-worker-dependency-skill-reads-2026-10-08.md
  - raw/notes/micro-deployed-worker-home-probes-2026-10-08.md
  - raw/notes/cursor-helper-transcript-probes-2026-10-09.md
  - raw/notes/cursor-print-mode-shell-probes-2026-10-09.md
confidence: high
checked: 2026-10-09
---

# Cursor

## Overview

Cursor is an AI-first code editor and a target here for the agent-definition
surface and for standing instructions. Its deployable style path is project
scope: an always-apply `.mdc` under `.cursor/rules/`. Machine-wide voice still
lives in settings User Rules, which a deploy step cannot write.

Facts below were verified on 7 August 2026 against `cursor.com/docs/context/rules`,
`/docs/agent/modes`, and the separate `cursor.com/help/customization/rules` page,
unless a passage names its own date and source. The delegation passages come from
the September 2026 agent delegation research. It drew on local agent
transcripts, the editor's local state store, the installed build, a process
listing, and the agent CLI's help text, and each passage dates the source it uses
([host observations](../raw/notes/agent-delegation-host-observations-2026-09.md)).
Those passages describe the IDE unless they name the CLI. Passages dated
4 October 2026 rest on live probes of agent CLI 2026.10.01 in print mode, and
each probe ran with `--force` and `--sandbox disabled`
([probes](../raw/notes/delegation-probes-2026-10-04.md)). Re-verify before
relying on any of them.

## Key facts and dates

### Agent definitions

Cursor reads Markdown agents from `.cursor/agents/`, `.claude/agents/`, and
`.codex/agents/`, in both project and user variants, and `.cursor` wins a name
conflict. It recognises `name`, `description`, `model`, `readonly`, and
`is_background`, and it tolerates foreign frontmatter keys, which is what lets
one shared Markdown file carry several harnesses' fields.

In a sandboxed print-mode session, a role file staged in the project's
`.cursor/agents/` directory spawned by name. Deployed user-level roles from the
user's agents directory did not appear among the subagent types, although the
documentation lists user variants. Deployed user-level skills did reach that
session, which read the user-level agent_spinner `SKILL.md` (4 October 2026).

A deployed user-level skill can also take the place of a staged copy of the same
skill. On 8 October 2026 a print-mode worker of CLI 2026.10.01, told to read a
staged `SKILL.md` that sat outside its workspace, read the deployed user-level
copy of the same name in three of three runs and never opened the staged one in
two of them. Staged as a project skill of the workspace
(`<root>/.cursor/skills/<name>/` with `--workspace <root>`) and named by path in
the prompt, the copy was the one read, in both runs that tried it
([probes](../raw/notes/cursor-skill-shadowing-probes-2026-10-08.md)). A project
copy does not displace a deployed copy on its own, though: with every repository
skill in the workspace's `.cursor/skills/` and no path in the prompt, the worker
read the deployed copies. `CURSOR_CONFIG_DIR`, which the CLI reads before
`XDG_CONFIG_HOME` for its configuration directory, kept authentication but left
skill discovery on the home directory, where the CLI looks under `.cursor`,
`.claude`, `.codex`, `.grok`, and `.agents`. A scratch `HOME` authenticated once
its `Library` linked back to the real one, and a skill copied into that scratch
home's `.cursor/skills/` was then the copy read when the prompt named it
([micro-home probes](../raw/notes/micro-deployed-worker-home-probes-2026-10-08.md)).
A skill the
harness had not staged at all, such as a base skill the staged one reaches by
name, resolved to its deployed copy as well
([dependency reads](../raw/notes/eval-worker-dependency-skill-reads-2026-10-08.md)).
An eval that path-reads a staged skill from outside the workspace can therefore
measure the deployed skill instead of the one under test.

There is no tools field, and a tools allowlist written into the frontmatter
anyway goes unenforced (observed 26 September 2026). Print mode listed these
tools on 4 October 2026: `Shell`, `Grep`, `Glob`, `Read`, `Write`,
`StrReplace`, `Delete`, `EditNotebook`, `TodoWrite`, `Task`, `AwaitShell`,
`AskQuestion`, `SwitchMode`, `WebSearch`, `WebFetch`, `ReadLints`, `CreateGoal`,
`UpdateGoal`, `GenerateImage`, and dynamic or MCP tools. The shell tool is
`Shell` rather than `Bash`. The documentation read on 7 August 2026 also named
an `LS` tool, which that list lacks.

A read-only role is expressed with `readonly: true`, which the documentation
says restricts write permissions.
[Agent definition portability](../concepts/agent-definition-portability.md)
records how far that setting held when observed in the IDE and in print mode,
and how far a `readonly` set on a single Task call held, beside the other hosts'
read-only levers.

Effort keys in agent definitions had no observable effect on 16 September 2026,
when helpers ran on `default` with max mode off. A model pinned in an agent
definition took effect in July transcripts.

### Skills attached by hand

When a user attaches a skill by hand, Cursor inlines only its SKILL.md body into
the user turn. The frontmatter and the references stay out, and a note beside
the body says the files need reading only if needed (16 and 23 September 2026).
A subagent's first turn holds only its prompt, so skills attached in the parent
never reach it (16 September 2026).

### Delegation to helpers

The Task tool spawns helpers. Its call accepts `description`, `subagent_type`,
`prompt`, `model`, `run_in_background`, `resume`, and `readonly`, and custom
agents are callable by name (16 and 22 September 2026). A requested model of
`fast` was recorded as `default`, so its effect is unverified
(16 September 2026). In print mode the spawn tool is `Task` as well. Its stream
record holds `description`, `prompt`, `subagentType`, `model`, `agentId`, and
`mode`, where `subagentType` reads `custom.name` for a named role and
`unspecified` otherwise. The built-in subagent types there are
`generalPurpose`, `explore`, `shell`, `cursor-guide`, `ci-investigator`,
`bugbot`, `security-review`, and `best-of-n-runner` (4 October 2026).

Cursor shows both delivery properties, batch delivery and notice delivery
(16 and 17 September 2026). Several foreground Task calls in one message run
concurrently and return together inside the turn. They act as a barrier, so the
parent waits for all of them, and that is batch delivery. A background call
returns at once, and that is notice delivery. Its completion re-invokes the
parent only after the parent's turn ends, carries no result, and can arrive in
bursts (16 and 22 September 2026). The largest batches observed were seven
background Task calls in one message and five foreground calls in one response.
Helper progress updates never reach the parent (22 September 2026). In print
mode a helper's result reaches the parent as its final text inside the `Task`
result (`conversationSteps`), and the helper's own tool calls stay out of the
parent's stream (4 October 2026). They land in the helper's own chat transcript
instead, whose print-mode location the next section records (9 October 2026).

Nested spawning, where a subagent spawns helpers of its own, worked on
2 July 2026. That day a subagent dispatched background reviewers and polled
their transcripts. No subagent transcript since August records a Task call,
while main sessions kept making them, so whether a subagent can still spawn is
unverified. A dynamic-tool search returned a false negative for delegation
(26 September 2026).

[Orchestration failure families](../concepts/orchestration-failure-families.md)
holds the run evidence these observations served.

### Helper state and isolation

The parent and a background helper share one working tree and one git index
(16 September 2026). Helpers can read their siblings' transcripts, and nothing
isolates them from one another (16 and 22 September 2026). Given a path outside
the workspace, Grep and Glob silently search the workspace instead
(26 September 2026).

In the IDE, helper transcripts are JSONL files, written live, at
`agent-transcripts/<parent>/subagents/<id>.jsonl`. They end in a `turn_ended`
record and hold no tool results (22 and 23 September 2026), and no transcript
records token counts (16 to 26 September 2026). In print mode the CLI writes
one such file per chat under the home directory, the parent's and each
helper's alike, at
`.cursor/projects/<workspace>/agent-transcripts/<chat-id>/<chat-id>.jsonl`. The
parent's chat id is the stream's `session_id`, and a helper's is the `agentId`
in its `Task` result. An assistant line's `tool_use` blocks name each tool and
its input, so a helper's reads, which the parent's stream leaves out, can be
read back from its transcript (9 October 2026,
[transcript probes](../raw/notes/cursor-helper-transcript-probes-2026-10-09.md)).
The eval runners' read check relies on that, as
[verification surfaces](../concepts/verification-surfaces.md) records. The
editor's local state store
keeps the tool results and termination reasons that the transcripts omit. Its
change tally per session matched the working-tree diff of the target
(26 September 2026).

Each helper starts with a fixed load of about 24,000 to 25,000 tokens. One parent
context holding five rounds of returns reached 141,765 tokens of its
256,000-token window, or 55 percent. About 24,000 of that was fixed host
overhead. The rest was conversation: the inlined skill, repeated full reads of
the task file, the orchestrator's own prompts, and the returns (17 and
26 September 2026).

### Continuation across turns

Two built-in skills can keep work going across turns. A goal skill calls a
`CreateGoal` tool, whose goal persists across turns with no turn budget. A loop
skill reruns a prompt on an interval. Both skill files sit in Cursor's built-in
skills folder in the user's home directory (listed 27 September 2026). The
research recorded no run that exercised either. One orchestrator looked the goal
tool up and left it unused (22 September 2026). A print-mode probe then called
`CreateGoal` and `UpdateGoal`. The goal was created and later marked complete,
and a resumed turn recalled it (4 October 2026). Whether a goal, once set, keeps
work going past the end of a turn is untested.

### Helper hook events

The installed IDE build, read on 27 September 2026, defines `subagentStart` and
`subagentStop` hook events for when a subagent starts and stops. The stop event
carries status, duration, summary, modified files, tool-call count, error
message, and loop count. The research studied a session of 22 September 2026,
and that session did not use them.

### The agent shell

The IDE agent's shell tool spawns non-login `zsh -i` shells (process listing,
18 September 2026). A non-login shell skips the login profile, so a tool that
only the login profile puts on `PATH` does not resolve there. On the workstation
measured on 27 September 2026, markdownlint and shellcheck reached `PATH` only
through the login profile. Wherever that holds, this repository's lint gates
cannot run in that shell.
[Interpreter and tool-path portability](../concepts/interpreter-and-tool-path-portability.md)
explains the mechanism and what such a shell resolves.

The print-mode agent CLI 2026.10.01 builds a command's environment from a login
shell instead (probes of 9 October 2026). Each shell call ran as `/bin/zsh -c`
with a wrapper that prepends `/usr/bin:/bin:/usr/sbin:/sbin` to `PATH` and then
evaluates a saved shell-state snapshot, and inside it the shell reported the
`login` option set. That snapshot follows the login profiles under the worker's
`HOME`. With `HOME` at a scratch home holding no profile, `bash` resolved to the
stock 3.2 because macOS's `path_helper` put the system directories first. A
`.zprofile` in the scratch home that exports the worker's launch `PATH` brought
the package-manager bash back
([shell probes](../raw/notes/cursor-print-mode-shell-probes-2026-10-09.md)).
The eval runners' scratch homes carry such a profile for that reason
([Verification surfaces for a shipped skill](../concepts/verification-surfaces.md)).

### Builds and the print-mode agent CLI

On 4 October 2026 the IDE build read 3.23.12 and the agent CLI 2026.10.01. On
27 September 2026 the two had stood eight months apart in build dates, IDE 3.22.7
against CLI 2026.01.23, and that gap no longer holds. Most observations above
predate the installation of IDE build 3.22.7 on 24 September 2026, and the
attachment and spawn behaviour comes from the IDE. The print-mode probes of
4 October 2026 agree with the IDE that a named role spawns. They disagree on how
far `readonly` reaches, so a runner on the CLI may still measure a different
host wherever no probe has compared the two.

The CLI's help text is the only source for its print mode, because no official
documentation was read. It was read for build 2026.01.23 on 27 September 2026
and for 2026.10.01 on 4 October 2026. It says that `-p`
"has access to all tools, including write and shell", where the earlier build
said bash. `--output-format` takes text, json, or stream-json. `--mode` takes
plan or ask, and the help describes both modes as read-only. `-f, --force` reads
"Force allow commands unless explicitly denied", with `--yolo` as its alias.
`--sandbox enabled|disabled` now states that it overrides the configuration.
`--model` accepts parameter overrides in brackets on a model name, and the
help's example sets an effort key. The help also lists `--list-models`,
`--workspace`, `--resume`, and `create-chat`. Build 2026.10.01 adds
`--auto-review`, `--trust`, `--approve-mcps`, `--add-dir`, `--plugin-dir`,
`-w/--worktree` with `--worktree-base`, and the `persist` command. Neither build
lists a schema, budget, or effort flag of its own.

Live print-mode probes of CLI 2026.10.01 on 4 October 2026 recorded how a test
runner drives it ([probes](../raw/notes/delegation-probes-2026-10-04.md)). The
CLI reads a project-level permission file, `.cursor/cli.json`, holding
`{"permissions": {"allow": [], "deny": [...]}}`, with and without `--trust`. Its
deny entries can refuse the shell and edits, and
[agent definition portability](../concepts/agent-definition-portability.md)
records which entries and modes confine a worker. The deny entries `Task(*)` and
`Task` did not withhold the spawn tool, though: the helper spawned and wrote its
file. A second turn resumes with `--resume <session_id>`, taking the
`session_id` from the first turn's stream, so no `create-chat` call is needed.

In the stream-json output, the `system`/`init` event carries `model`,
`permissionMode`, and `session_id` but no tool list. `assistant` events carry
text, `thinking` events carry deltas, and `tool_call` events carry a `subtype`
of `started` or `completed`. The `result` event carries `result`, `session_id`,
and `usage` (`inputTokens`, `outputTokens`, `cacheReadTokens`,
`cacheWriteTokens`). A `tool_call` object holds one key naming the tool kind,
with `args`, beside `toolCallId`, `startedAtMs`, and `hookAdditionalContexts`,
and it gains `completedAtMs` on completion (9 October 2026). On completion the
tool-kind entry also holds a `result` with `success`,
`permissionDenied`, `writePermissionDenied`, or `error`. The kinds seen were
`readToolCall`, `shellToolCall`, `editToolCall`, `taskToolCall`,
`createGoalToolCall`, `updateGoalToolCall`, and `getMcpToolsToolCall`.

### Rules are the whole instruction mechanism

Rules are Markdown under `.cursor/rules/` with `*.mdc` filenames, and the
frontmatter selects one of four activation modes: Always Apply through
`alwaysApply: true`, Apply Intelligently from a `description`, Apply to Specific
Files from `globs`, and Apply Manually by mention. An applied rule is included at
the start of the model context rather than replacing anything already in it. A
plain `.md` file in that folder is ignored; project rules need the `.mdc`
extension. When `alwaysApply` is `true`, the loader ignores `description` and
`globs`, so those fields cannot narrow an always-on rule to prose-only surfaces.

Nested `AGENTS.md` files are the frontmatter-free alternative, with the more
specific file taking precedence. Cursor also reads a project `CLAUDE.md` exactly
as it reads `AGENTS.md`, which makes it one of the harnesses adopting a
Claude-named file, at project scope rather than from the home directory. The
legacy `.cursorrules` file is deprecated; the help page migrates it into an
Always Apply project rule.

Precedence among the documented kinds is Team Rules over Project Rules over User
Rules. Rules reach Agent chat only, not Inline Edit, Tab, or Bugbot.

### User rules and machine-local rule files

Account User Rules are plain text under Customize → Rules. They apply across
projects, sync with the Cursor account, and are the documented slot for a
machine-wide communication style. A deploy step cannot write them.

The help page also names machine-local user rule files under the user
configuration tree's `rules/` folder. Those files stay on the machine and do not
sync. The rules reference still describes User Rules only as the settings text.
Print-mode probes on 6 October 2026 against agent CLI `2026.10.01` settled
injection for a deploy:

- A project `.cursor/rules/*.mdc` with `alwaysApply: true` was quoted in
  context
  ([probes](../raw/notes/cursor-style-injection-probes-2026-10-06.md)).
- The same shape of file under the user `rules/` folder was not
  ([probes](../raw/notes/cursor-style-injection-probes-2026-10-06.md)).
- A user-local plugin under `plugins/local/` with a `rules/` always-apply
  `.mdc` did not inject that rule, while a skill in the same plugin was
  available, both under auto-discovery and under `--plugin-dir`
  ([probes](../raw/notes/cursor-style-injection-probes-2026-10-06.md)).

So the file-based path a deploy can write and that print mode actually loads is
project `.cursor/rules/*.mdc`. Machine-wide voice still goes through settings
User Rules, or through whatever IDE-only channel a later probe confirms.

### Modes

Modes exist and switch from the picker or with Shift and Tab, but the modes
documentation describes no user-defined mode carrying its own instructions. Treat a
mode as a tool-and-behaviour preset rather than a style slot until that changes.

## Verification gaps

Home-directory rule injection and user-local plugin rule injection in print mode
are settled negatives as of 6 October 2026
([probes](../raw/notes/cursor-style-injection-probes-2026-10-06.md)). Whether an
IDE Agent chat after a window reload injects either surface remains untested.

The delegation research planned probes that had not run when it closed. The
print-mode probes of 4 October 2026 settled part of that list. Print mode
exposes the spawn tool and spawns a named role. How far the read-only modes and
the `readonly` lever reach has now been observed, as
[agent definition portability](../concepts/agent-definition-portability.md)
records. The stream-json capture, read-only workers included, is recorded above.
Several questions stay open. Does print mode match the IDE's skill attachment
and its batch and notice delivery? What does `default` resolve to, and does a
per-call model take effect? Can a subagent spawn today? Does a background helper
outlive a headless session? Does a goal, once set, keep work going past the end
of a turn? And what happens when the CLI is launched from the agent shell?

Re-reading the help on 4 October 2026 raised two questions. The probes settled
the deny-entry one, as the print-mode passage above records. The other stays
open: whether the effort key in a bracketed model parameter takes effect for a
print-mode worker. How well Cursor's router recalls a skill from its description
is unmeasured as well.

## Relationships to other entities

- [Anthropic Claude Code](anthropic-claude-code.md), whose agent directory and
  project `CLAUDE.md` Cursor reads.
- [GitHub Copilot in VS Code](github-copilot-vs-code.md), the other append-only
  target with a documented user-level instruction root, which Cursor lacks.

## Derived from

- `cursor.com/docs/context/rules`, `/docs/agent/modes`,
  `cursor.com/help/customization/rules`, and `cursor.com/docs/reference/plugins`,
  re-read 6 October 2026 for the rules and plugin surfaces the style deploy uses.
- The `harness_portability` skill in this repository, before its August 2026
  split.
