---
title: Claude Code delegation surfaces
created: 2026-10-04
updated: 2026-11-21
checked: 2026-09-05
type: concept
tags: [claude, agent, verification-gap]
sources: [raw/notes/agent-delegation-host-observations-2026-09.md, raw/notes/agent-spinner-run-evidence-2026-09.md, raw/notes/delegation-probes-2026-10-04.md]
confidence: medium
---

# Claude Code delegation surfaces

## Definition

Claude Code's delegation surfaces are the routes it gives an orchestrating agent
for running helper agents. The Workflow and Agent tools spawn helpers and return
their results. The shell tool is where an orchestrator waits and searches. The
print-mode CLI runs a headless worker, a session with no interactive user. This
page holds what the September 2026 agent delegation research and the print-mode
probes of 4 October 2026 observed of each surface on
[Anthropic Claude Code](../entities/anthropic-claude-code.md). The
[Cursor](../entities/cursor.md) and [OpenAI Codex](../entities/openai-codex.md)
pages hold what was observed on those hosts.

Each passage carries its date and the kind of source it rests on
([host observations](../raw/notes/agent-delegation-host-observations-2026-09.md)).
The research checker left most of the entries behind these passages unchecked.
The passages flag the entries that the research names as resting on analyst
observation alone, and the research gives that list as partial. The design
proposed for agent_spinner draws on these observations, so their unchecked and
analyst-only entries cap this page at medium confidence. Passages dated
4 October 2026 rest instead on live probes of the standalone CLI build 2.1.226
([probes](../raw/notes/delegation-probes-2026-10-04.md)). Re-verify before
relying on any of them.

## Current state of knowledge

### Delegation to helpers

These observations come from Claude Code desktop sessions and their Workflow
tool, and one session recorded build 2.1.260
([host observations](../raw/notes/agent-delegation-host-observations-2026-09.md)).
Workflow helpers run at spawn depth 1, one level below the main loop, and
inherit the main loop's model and effort (5 and 6 September 2026, workflow
records). In two sessions of 5 September 2026, the Workflow pool ran at most 12
helpers at once, which fits first-in-first-out queuing. One of those sessions
was checker-verified
([run evidence](../raw/notes/agent-spinner-run-evidence-2026-09.md)). In one
run at about width 160, the writers far outnumbered the pool, and no verifier
started until every writer had left the queue. A stop partway through that run therefore found no
checker started. In a narrower run, the first checker started while writers
still ran, and the two stages overlapped at the tail. The tool description
carries a default size guideline, "keep workflows under 10 agents", which the
user's prompt may override (23 September 2026).

A schema-bound helper, whose return has to match a schema, retries inside its
own turn, and its first schema-valid call ends its turn, even when that call is
a probe. After five failures the helper's slot resolves to a falsy value, and
the run still completes (15 September 2026). A check that reads a "done" state
and filters out nulls counts a schema-valid placeholder as a success (15 and
23 September 2026). Result entries in the run's journal carry no label and
arrive in the order the helpers finish, and labels need not be unique
(15 September 2026). The workflow output file holds progress entries with
truncated previews, and a plain read of the file comes back truncated. Each
progress entry's token figure is the size of the helper's context at its final
request. That differs from fresh-token spend, so a cost share needs its basis
stated (5 September 2026).

A resume replays agent calls from the start for as long as they are unchanged.
A call placed after a changed one therefore runs fresh, even when it is
byte-identical, and the claim that the cache is keyed on content was refuted
(24 September 2026). A resume reruns killed helpers against the current disk
state (5 September 2026). A stop kills the helpers still running, so they return
no results, and their edits persist. After a pause request, freed slots kept
starting queued helpers, and whether the tool offers a pause at all is
unverified (5 and 23 September 2026).

A background Workflow run returns a task id at once, and the main loop keeps
running tools meanwhile. When the run completes, its notice carries the result
inline, truncated in some sessions, and the full result sits in a task output
file (5 to 23 September 2026). That is notice delivery with the result,
recorded for the Workflow tool only, and how a background spawn outside that
tool delivers is unrecorded. A completion notice that arrives during a blocking
poll waits until the poll returns. A user message sent during an unbounded
foreground wait never reached the model (15 September 2026). A file that stays
quiet for a while is no completion signal, which rests on analyst observation
alone (15 September 2026).

General-purpose helpers keep every tool, and the Explore type keeps Bash even
though it describes itself as a search role that does not review
(5 September 2026). A custom agent spawned through the Agent tool reached
depth 2, a helper spawned by a helper. Helpers start with about 55,000 tokens of
context and receive the triggering request verbatim, and the skill listing they
receive comes from the deployed copies, which can lag behind the working tree.
Those three rest on analyst observation alone (5, 15, and 23 September 2026).
Outside the Workflow tool, one repair session fanned out seven background survey
agents over ranges of pages, and the record leaves open whether they were sent
in one message (22 September 2026).

Two aids help an orchestrator continue. An orchestrator set a fallback wake-up
as a guard against a stall while a background run worked (5 September 2026).
A session also lists a loop skill that reruns a prompt on an interval or at a
self-chosen pace, which no run has exercised (listing read 27 September 2026).

### Helpers in print mode

On 4 October 2026, probes ran the standalone CLI build 2.1.226 in print mode and
observed the spawn surface a headless session offers
([probes](../raw/notes/delegation-probes-2026-10-04.md)). The spawn tool appears
as `Task` in the tool list of the session's init event, and as `Agent` in the
stream's `tool_use` records. The Workflow tool also spawns agents, so a session
meant to run without spawning needs both the spawn tool and the Workflow tool
withheld. A role file staged in the project's `.claude/agents/` directory
appears in the init event's `agents` list and spawns by name through
`subagent_type: <name>`. The user's deployed roles reach such a session when it
reads the user tree; a scratch configuration directory removes them, as
[Anthropic Claude Code](../entities/anthropic-claude-code.md) records. Tools
denied to the parent session are denied inside its spawned helpers as well, with
a refusal that reads "disabled for this session, in subagents as well as here".
A spawned helper's own tool calls appear in the parent's stream, marked with
`parent_tool_use_id`. Print mode offers no goal tool. Its session lists
`ScheduleWakeup`, `CronCreate`, `CronDelete`, `CronList`, and `Monitor`, and no
probe exercised any of them.

### The shell tool

In these desktop sessions, the shell tool blocks foreground and chained sleep
commands and points to a monitor or a background run instead. That rests on
analyst observation alone
([host observations](../raw/notes/agent-delegation-host-observations-2026-09.md)).
The tool moves any command that runs past 600 seconds into the background, and
shell until-loop waits that ran past that mark moved there too (15 and
16 September 2026). Whether the task-output tool caps a blocking wait is
unverified, because the 600-second timeouts observed that day used the value
the orchestrator passed.

Claude Code's shell snapshot, the shell setup its commands run under, defines
`grep` as a function that runs ugrep with `--ignore-files --hidden -I`. Inside a
directory whose own `.gitignore` holds `*`, that function finds nothing, while
the system grep finds a file planted there (workstation command,
27 September 2026). The desktop shell's grep function also omits the `./` prefix
(6 September 2026).
[Interpreter and tool-path portability](interpreter-and-tool-path-portability.md)
records two zsh constructs that misfired in these sessions.

### Print-mode CLI flags

The help text of the standalone CLI build 2.1.226 lists the flags a headless
worker relies on. It was read on 27 September 2026, and no official
documentation backs it
([host observations](../raw/notes/agent-delegation-host-observations-2026-09.md)).
For the reply and the model, it lists `--json-schema`, `--output-format`,
`--model`, and `--effort`, whose levels are low, medium, high, xhigh, and max.
For tool access, it lists `--permission-mode`, `--tools`, `--allowedTools`, and
`--disallowedTools`. For limits and placement, it lists `--max-budget-usd`,
`-w/--worktree`, `--no-session-persistence`, and `--bg`. The `--agents <json>`
flag defines custom agents for one session, so an eval runner can stage a role
without deploying it. The `-r/--resume [value]`, `-c/--continue`,
`--session-id <uuid>`, and `--fork-session` flags carry a conversation across
invocations.

Probes of the same build on 4 October 2026 recorded how a launcher drives a
worker with these flags ([probes](../raw/notes/delegation-probes-2026-10-04.md)).
These facts are about launching workers and serve the test runner, and
agent_spinner relies on none of them. `--disallowedTools Agent,Task` removes the
spawn tool, while `Workflow` stays callable unless the flag names it too.
[Agent definition portability](agent-definition-portability.md) records which
tool-access flags give a read-only session, and why `--permission-mode plan` is
unfit for evals. `--session-id <uuid>` on the first turn and `--resume <uuid>`
on the second carry the conversation from one turn to the next.
`--output-format stream-json` needs `--verbose`. In that stream, the
`system`/`init` event carries `tools`, `agents`, `skills`, `model`,
`permissionMode`, and `session_id`. `tool_use` blocks (`id`, `name`, `input`)
appear inside the content of `assistant` messages, and `tool_result` blocks
(`tool_use_id`, `content`, `is_error`) inside the content of `user` messages.
The `result` event carries `result`, `session_id`, and `usage`.

## Open questions

Of the probes the research planned on the standalone CLI, the ones run on
4 October 2026 settled the disallowed-tools flags, standard-output capture, and
the resume path a two-turn eval needs. Still open are how a worker behaves when
its reply violates the schema, and whether the worktree flag confines a worker.
Also open are the authentication of a nested CLI launched from the agent shell,
session-scoped agent definitions for staging roles, and whether a background
helper outlives a single-shot headless run.

## Related concepts

- [Anthropic Claude Code](../entities/anthropic-claude-code.md), the host whose
  entity page holds its configuration, instruction files, agents, and hooks.
- [Cursor](../entities/cursor.md), for the same research's observations of the
  other host it studied.
- [Agent definition portability](agent-definition-portability.md), for the
  role-level and session-level read-only levers and how far each one held.
- [Orchestration failure families](orchestration-failure-families.md), for the
  run evidence these observations served.
- [Interpreter and tool-path portability](interpreter-and-tool-path-portability.md),
  for the stock interpreters and the login-shell `PATH` trap an agent shell
  meets.
