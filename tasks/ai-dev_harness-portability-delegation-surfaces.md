---
description: Add harness_portability's references/delegation-surfaces.md, dated facts on how Claude Code, Cursor, and Codex run sub-agents, with a pointer to it and a sub-agent-only spawn rule.
scope: plugins/ai_dev/skills/harness_portability
created: 2026-10-03T15:54:08
updated: 2026-11-06T20:40:51
status: ready
reported-by: Andreas Hoffmann
---

# Record how Claude Code, Cursor, and Codex run sub-agents, and the sub-agent spawn rule, in harness_portability

## Goal

harness_portability is the skill that keeps skills and agents working across agent harnesses. agent_spinner, the skill for running helper agents, sends every per-harness question to it. Today harness_portability records no facts about how each host runs helper agents. Those facts sit only in this repository's wiki, which travels nowhere else.

After this task, an agent that plans helper work on Claude Code, Cursor, or Codex finds each host's sub-agent facts in one file: harness_portability's new `references/delegation-surfaces.md`. A sub-agent is a helper agent that the host itself spawns from inside a session. The file says how each host spawns helpers, where named roles register, and which read-only and model levers take effect. A lever is a setting the host enforces, such as a read-only flag in a role's definition. The file also says how a helper's result and completion reach the parent, what a helper sees, and which continuation aids exist. Continuation aids are the tools that keep work going across turns. Every entry carries its observation date, the build, and its source kind, the kind of evidence behind it.

The harness_portability body gains one sentence that points to the new reference. It also gains a rule that sets the spawn route, meaning how every delegating skill starts its helpers. Helpers run only as sub-agents of the host. A skill whose spawn fails degrades by its own rules and launches no agent CLI in a helper's place. Degrading by its own rules means falling back to what the skill itself prescribes, such as inline passes or its stop-and-ask boundary.

## Context

- **Current state, read on 2026-10-04.** harness_portability has no `references/` directory. Its `<where_snapshots_live>` rule, which says where verified harness facts are kept, already names two homes for such a fact: the working repository's wiki and the skill's own `references/` directory. The body carries the shell floor that shipped on 2026-10-03, the baseline shell environment its scripts must work in. The floor consists of the rule beginning "Target bash 3.2 as the interpreter floor" and the rule beginning "Treat a package-manager PATH entry that a login-shell profile contributes as unavailable in a non-login shell".
- **Builds read on 2026-10-04.** The Cursor IDE reads 3.23.12, and its `agent` CLI, also installed as `cursor-agent`, reads 2026.10.01, so the CLI is current with the IDE. The `claude` CLI on PATH reads 2.1.226, while the Claude desktop application keeps newer builds of its own, 2.1.286 the newest. `codex-cli` reads 0.160.0. The probe runs of that day each ran in a scratch git repository with its event stream captured. Print mode is a CLI's non-interactive `-p` mode. The runs used `claude` 2.1.226 in print mode on `sonnet`, which resolved to `claude-sonnet-5`, Cursor's `agent` 2026.10.01 in print mode on `auto`, and `codex-cli` 0.160.0 through `codex exec`.
- **Decision of 2026-10-03.** The owner decided to keep every per-harness fact in harness_portability and the wiki. agent_spinner routes every per-harness question to harness_portability. Its static greps, the grep checks in its script tests, keep such facts out of its own directory. The orchestrator is the agent that runs agent_spinner and spawns the helpers. When it sizes its waves, the groups of helpers it starts together, it reads a host's largest batch, context window, and delivery property from this reference.
- **Spawn route, decided 2026-10-04.** The owner decided that helpers run only as sub-agents of the harness the orchestrator runs in, because the modern harnesses this repository works with all offer sub-agents. The same day the owner dropped the planned headless-worker launcher, which would have run helpers as separate headless processes of the host's agent CLI. A second launch route adds machinery, and it can engage where a sub-agent would have worked. A `claude -p` run is also billed at a higher rate than a helper spawned inside a session. `grep -rlE 'claude -p|agent -p|codex exec' plugins` prints nothing today, so no shipped file launches a headless CLI worker.
- **The wiki.** The research behind this task entered the wiki on 2026-10-04 as anonymized raw notes. Their import put the dated delegation observations on the host pages, such as `wiki/entities/cursor.md` and `wiki/entities/anthropic-claude-code.md`, and on the concept pages that own them. The probe facts of 2026-10-04, print-mode CLI flags and stream shapes included, go to the wiki directly.

## Approach

### The reference file

Write `plugins/ai_dev/skills/harness_portability/references/delegation-surfaces.md` as plain markdown in the skill's positive register, the positive wording its body uses:

- An opening paragraph says what the file holds: each host's sub-agent delegation facts, and the agent-shell facts. The agent shell is the shell in which a host's agent runs its commands. Each entry carries its observation date, build, and source kind. A reader re-verifies an entry before relying on it, per `<verify_before_encoding>`, the skill's rule that every harness fact is perishable and needs confirming before a change depends on it.
- An entry's build reads `unrecorded` unless the entry rests on a 2026-10-04 probe run. Such an entry carries the build the Context bullet **Builds read on 2026-10-04** records for the probe run on its host: `claude` 2.1.226, Cursor's `agent` 2026.10.01, or `codex-cli` 0.160.0. A host section's opening builds line is that section's 2026-10-04 read stamp, not an entry's observation build.
- `## Claude Code`, `## Cursor`, and `## Codex` each open with that host's builds from the Context bullet **Builds read on 2026-10-04**. Each then holds exactly five subsections, in this order: `### Spawn surface`, `### Registered roles and levers`, `### Delivery and concurrency`, `### What a helper sees`, and `### Continuation`. A subsection whose host has no recorded fact says so in one sentence.
- The file opens with `<!-- markdownlint-disable MD024 -->` on its first line, because the three host sections repeat the same five subsection heading texts while the repo's markdownlint config keeps `default: true`. The five heading texts stay exactly as named above.
- Each fact under **Facts to record** goes to the subsection its row names. Each Cursor entry names the mode it was observed in, IDE or print mode. The two modes differ in transcript layout, in the read-only lever, and in whether a later turn exists. Where a print-mode observation of 2026-10-04 differs from a September IDE observation, the entry records both, each with its mode. Cursor's `readonly: true` is that case.
- Each `### Delivery and concurrency` states the host's delivery property, whether a notice carries the result, and the context window. It also states the fixed load per helper, the context-fill figure, the largest observed batch, and where a helper's own tool calls are recorded. Where no record shows one of these, the entry says so.
  - The delivery property says how spawned work comes back. Batch delivery means a batch of spawns returns together inside the turn. Notice delivery means a spawn returns at once and its completion arrives later as a notice.
  - The fixed load per helper is the context a helper holds before it starts work. The context-fill figure is how full a parent's context grew in a recorded run.
  - Claude Code has no recorded single-message batch. Its `### Delivery and concurrency` says so in the largest-observed-batch slot and then records the two figures that do exist, each named for what it measures: the Workflow pool ran at most 12 helpers at once, a pool concurrency cap, and seven background agents were in flight at once, with their dispatch unrecorded. Neither figure is the batch.
- `## Agent shells and scratch locations` holds the shell facts under **Facts to record**.

Carry host measurements only as the figures `### Delivery and concurrency` names. Session counts, per-session latencies, a run's writer count, and the size of any single output stay out of the reference.

### Facts to record

A probe run below means one of the print-mode probe runs of 2026-10-04 on the builds the Context names. A row's source kind says what evidence backs it, such as a probe run or local agent transcripts. Where the research note marks a row analyst observation alone or a local workflow record, that source kind governs the row.

Claude Code:

| Subsection | Fact | Observed | Source kind |
| --- | --- | --- | --- |
| Spawn surface | The spawn tool appears as `Task` in the session's init tool list and as `Agent` in the stream's `tool_use` records. The `Workflow` tool also spawns agents, so a session meant to run without spawning needs both tools withheld | 2026-10-04 | a probe run |
| Spawn surface | A custom agent spawned through the Agent tool reached spawn depth 2 | 2026-09-05 | analyst observation alone |
| Registered roles and levers | A role file staged in the project's `.claude/agents/` directory appears in the init `agents` list and spawns by name, as `subagent_type: <name>` | 2026-10-04 | a probe run |
| Registered roles and levers | Deployed user-level roles reach a sandboxed session: the init `agents` list includes the user's deployed `auto_*` roles | 2026-10-04 | a probe run |
| Registered roles and levers | A role whose frontmatter `tools:` lists `Read, Grep, Glob` ran with exactly those tools. Its write and shell attempts found no tool, so the allowlist holds | 2026-10-04 | a probe run |
| Registered roles and levers | Tools denied to the parent session are denied inside its spawned helpers too. The refusal reads "disabled for this session, in subagents as well as here" | 2026-10-04 | a probe run |
| Registered roles and levers | Workflow helpers run at spawn depth 1 and inherit the main loop's model and effort | 2026-09-05, 2026-09-06 | local agent transcripts |
| Registered roles and levers | General-purpose helpers keep every tool. The Explore type keeps the shell and describes itself as a search role that does not review | 2026-09-05 | local agent transcripts |
| Delivery and concurrency | A background Workflow run returns a task id at once while the main loop keeps running tools. Its completion notice carries the result inline, truncated in some sessions, and the full result sits in a task output file. That is notice delivery with the result, for the Workflow tool only. How a background spawn outside it delivers is unrecorded | 2026-09-05 to 2026-09-23 | local agent transcripts |
| Delivery and concurrency | A spawned helper writes its own transcript, `subagents/agent-<id>.jsonl` inside the parent session's transcript directory. Its records carry `isSidechain` set to true and the helper's `agentId`. Their `message.content` lists each tool call as a `tool_use` block with `id`, `name`, and `input` | 2026-10-04 | local agent transcripts |
| Delivery and concurrency | Helpers start with about 55,000 tokens of context | 2026-09-15, 2026-09-23 | analyst observation alone |
| Delivery and concurrency | The Workflow pool ran at most 12 helpers at once, consistent with first-in-first-out queuing. A checker queued behind writers therefore starts only once the writers ahead of it have left the queue | 2026-09-05 | local agent transcripts |
| Delivery and concurrency | The Workflow tool's description carries a default size guideline of keeping workflows under 10 agents, which the user's prompt may override | 2026-09-23 | local agent transcripts |
| Delivery and concurrency | Outside the Workflow tool, seven background agents were in flight at once. Whether one message dispatched them is unrecorded | 2026-09-22 | local agent transcripts |
| Delivery and concurrency | A schema-bound helper, one whose return must match a schema, retries inside its own turn. Its first schema-valid call ends it, even when that call is only a probe. After five failures the slot resolves falsy and the run completes | 2026-09-15 | local agent transcripts |
| Delivery and concurrency | Judging success by a state of `done` plus a filter that drops null results counts a schema-valid placeholder as a success | 2026-09-15, 2026-09-23 | local agent transcripts |
| Delivery and concurrency | The workflow journal's result entries carry no label and arrive in completion order, and labels need not be unique | 2026-09-15 | local agent transcripts |
| Delivery and concurrency | The workflow output file holds progress entries with truncated previews, and a plain read of it truncates. Each entry's token figure is the helper's final request context size, which differs from the fresh tokens it spent | 2026-09-05 | local agent transcripts |
| Delivery and concurrency | A quiet-file interval, a stretch in which a watched file does not change, is not a completion signal | 2026-09-15 | analyst observation alone |
| Delivery and concurrency | A notice that completes during a blocking poll waits until the poll returns. A user message sent during an unbounded foreground wait never reached the model | 2026-09-15 | local agent transcripts |
| Delivery and concurrency | The shell tool blocks foreground and chained sleeps and points to a monitor or a background run instead. It moves any command running past 600 seconds into the background. A blocking task-output wait given 600 seconds returned at that value; whether the tool caps the wait is unverified | 2026-09-15, 2026-09-16 | analyst observation alone |
| Delivery and concurrency | A stop kills helpers in flight without results, and their edits persist. After a pause request, freed slots kept starting queued helpers, and whether the tool offers a pause is unverified | 2026-09-05, 2026-09-23 | local agent transcripts |
| What a helper sees | Helpers receive the triggering request verbatim | 2026-09-15, 2026-09-23 | analyst observation alone |
| What a helper sees | The skill listing helpers receive comes from deployed copies, which can lag the working tree | 2026-09-05 | analyst observation alone |
| What a helper sees | Deployed user-level skills reach a sandboxed session: the init `skills` list includes the user's deployed skills | 2026-10-04 | a probe run |
| What a helper sees | The shell snapshot, the captured shell setup the shell tool runs in, defines `grep` as a function running ugrep with `--ignore-files --hidden -I`. It omits the `./` prefix on results. It finds nothing inside a directory whose own `.gitignore` holds `*`, where the operating system's own `grep -rl` finds the file | 2026-09-06; 2026-09-27 | local agent transcripts; a command run |
| Continuation | Two continuation aids exist. One is a fallback wake-up, which an orchestrator set as a stall guard while a background run worked. The other is a loop skill that reruns a prompt on an interval or at a self-chosen pace. No run has exercised the loop skill | 2026-09-05; skill listing read 2026-09-27 | local agent transcripts; a skill listing |
| Continuation | Print mode offers no goal tool. The session lists `ScheduleWakeup`, `CronCreate`, `CronDelete`, `CronList`, and `Monitor`, and no probe exercised them | 2026-10-04 | a probe run |
| Continuation | Resume replays the longest unchanged prefix of agent calls, so a byte-identical call placed after a changed one runs fresh. The cache is not keyed on content alone | 2026-09-24 | local agent transcripts |
| Continuation | A resume reruns killed helpers against the current disk state | 2026-09-05 | local agent transcripts |

Cursor:

| Subsection | Fact | Mode | Observed | Source kind |
| --- | --- | --- | --- | --- |
| Spawn surface | The spawn tool, `Task`, accepts `description`, `subagent_type`, `prompt`, `model`, `run_in_background`, `resume`, and `readonly`. Custom agents are callable by name | IDE | 2026-09-16, 2026-09-22 | local agent transcripts |
| Spawn surface | The orchestrator issued `Task` calls with `subagent_type: explore` and `model: inherit`, five in one message, so print mode exposes the spawn tool | print mode | 2026-10-03 | eval runs on the installed CLI |
| Spawn surface | A `Task` record holds `description`, `prompt`, `subagentType`, `model`, `agentId`, and `mode`. Its `subagentType` reads `custom.name` for a named role and `unspecified` otherwise | print mode | 2026-10-04 | a probe run |
| Spawn surface | The session's tools are `Shell`, `Grep`, `Glob`, `Read`, `Write`, `StrReplace`, `Delete`, `EditNotebook`, `TodoWrite`, `Task`, `AwaitShell`, `AskQuestion`, `SwitchMode`, `WebSearch`, `WebFetch`, `ReadLints`, `CreateGoal`, `UpdateGoal`, `GenerateImage`, and dynamic or MCP tools | print mode | 2026-10-04 | a probe run |
| Spawn surface | A dynamic tool search that finds no spawn tool gives a false negative for delegation | IDE | 2026-09-26 | local agent transcripts |
| Spawn surface | Nested spawning, a helper spawning a helper of its own, worked on 2026-07-02, with the parent resuming the child. No helper transcript since August 2026 holds a spawn call | IDE | as stated | local agent transcripts |
| Registered roles and levers | A role file staged in the project's `.cursor/agents/` directory spawns by name | print mode | 2026-10-04 | a probe run |
| Registered roles and levers | The built-in subagent types are `generalPurpose`, `explore`, `shell`, `cursor-guide`, `ci-investigator`, `bugbot`, `security-review`, and `best-of-n-runner` | print mode | 2026-10-04 | a probe run |
| Registered roles and levers | Deployed user-level roles from the user's agents directory did not appear among the subagent types of a sandboxed session | print mode | 2026-10-04 | a probe run |
| Registered roles and levers | `readonly: true` maps a helper to chat mode, removes its edit tools, and leaves the shell callable | IDE | 2026-09-17, 2026-09-26 | local agent transcripts |
| Registered roles and levers | A role whose frontmatter says `readonly: true` ran in ask mode. Both its file write and its shell command were refused, and no file was created | print mode | 2026-10-04 | a probe run |
| Registered roles and levers | A `Task` call asked to set `readonly` recorded no read-only field (`mode: TASK_MODE_UNSPECIFIED`). That helper wrote its file and ran its shell command, so a per-call read-only setting was not observed | print mode | 2026-10-04 | a probe run |
| Registered roles and levers | A tools allowlist in agent frontmatter is not enforced | IDE | 2026-09-26 | local agent transcripts |
| Registered roles and levers | A requested per-call model of `fast` was recorded as `default`, so a per-call model's effect is unverified | IDE | 2026-09-16 | local agent transcripts |
| Registered roles and levers | Effort keys in agent definitions had no observable effect, and helpers ran on `default` with max mode off. Per-definition model pins took effect in July 2026 | IDE | 2026-09-16 | local agent transcripts |
| Delivery and concurrency | Several foreground `Task` calls in one message run concurrently and return together inside the turn. They act as a barrier, so the parent goes on only when all have returned: batch delivery | IDE | 2026-09-17 | local agent transcripts |
| Delivery and concurrency | A background `Task` call returns at once. Its completion re-invokes the parent only after the parent's turn ends, carries no result, and can arrive in bursts: notice delivery without the result | IDE | 2026-09-16, 2026-09-22 | local agent transcripts |
| Delivery and concurrency | The largest observed batches were seven background calls in one message and five foreground calls in one response | IDE | 2026-09-16, 2026-09-17 | local agent transcripts |
| Delivery and concurrency | A helper's result reaches the parent as its final text inside the `Task` result, under `conversationSteps`. The helper's own tool calls appear only in the helper's own transcript | print mode | 2026-10-04 | a probe run |
| Delivery and concurrency | Print-mode helper transcripts sit beside the parent's as top-level transcripts. Each record holds `role` and `message`, whose `content` lists tool calls as `tool_use` blocks with `name` and `input`, several to a record | print mode | 2026-10-03; record shape 2026-10-04 | eval runs on the installed CLI; a probe run |
| Delivery and concurrency | IDE helper transcripts are live JSONL files under `agent-transcripts/<parent>/subagents/<id>.jsonl`. They end in a `turn_ended` record and hold no tool results | IDE | 2026-09-22, 2026-09-23 | local agent transcripts |
| Delivery and concurrency | The editor's state store keeps tool results and change tallies that the transcripts omit, and the transcripts record no token counts | IDE | 2026-09-16 to 2026-09-26 | local agent transcripts |
| Delivery and concurrency | Helper progress updates never reach the parent | IDE | 2026-09-22 | local agent transcripts |
| Delivery and concurrency | Each helper starts with a fixed load of about 24,000 to 25,000 tokens. One parent context reached 55 percent of its 256,000-token window after five rounds of returns, about 24,000 tokens of it fixed host overhead | IDE | 2026-09-17, 2026-09-26 | local agent transcripts |
| Delivery and concurrency | The build defines `subagentStart` and `subagentStop` hook events carrying status, duration, summary, and modified files | IDE | 2026-09-22 | the installed build, read in a local session |
| What a helper sees | Manual attachment, where a user attaches a skill to the chat by hand, inlines only the SKILL.md body into the user turn, without frontmatter or references. The body sits under a note that files need reading only if needed | IDE | 2026-09-16, 2026-09-23 | local agent transcripts |
| What a helper sees | A helper's first turn holds only its prompt, and the parent's attached skills never reach it | IDE | 2026-09-16 | local agent transcripts |
| What a helper sees | Deployed user-level skills reach a sandboxed session, which read the user-level agent_spinner `SKILL.md` | print mode | 2026-10-04 | a probe run |
| What a helper sees | Helpers can read sibling helpers' transcripts, and nothing isolates them | IDE | 2026-09-16, 2026-09-22 | local agent transcripts |
| What a helper sees | The parent and a background helper share one working tree and one git index | IDE | 2026-09-16 | local agent transcripts |
| What a helper sees | Grep and Glob silently re-scope a path outside the workspace to the workspace | IDE | 2026-09-26 | local agent transcripts |
| What a helper sees | The agent shell tool spawns non-login `zsh -i` shells | IDE | 2026-09-18 | a process listing |
| Continuation | A built-in goal skill calls a `CreateGoal` tool whose goal persists across turns with no turn budget. A built-in loop skill reruns a prompt on an interval. Both skill files sit in the IDE's built-in skills directory under its user configuration root, and no run has exercised either | IDE | 2026-09-22; listed 2026-09-27 | local agent transcripts; a directory listing |
| Continuation | `CreateGoal` and `UpdateGoal` are callable. A goal was created and later marked complete, and a resumed turn recalled it. No probe tested whether an armed goal keeps work going past the end of a turn | print mode | 2026-10-04 | a probe run |

Codex, all observed through `codex exec`:

| Subsection | Fact | Observed | Source kind |
| --- | --- | --- | --- |
| Spawn surface | `codex exec` exposes the native sub-agent tools `collaboration.spawn_agent`, `wait_agent`, `send_message`, `list_agents`, `interrupt_agent`, and `followup_task` | 2026-10-04 | a probe run |
| Spawn surface | `--disable multi_agent` did not stop spawning | 2026-10-04 | a probe run |
| Registered roles and levers | Spawnable roles come from the user's `~/.codex/agents/*.toml` and, in a trusted project, from `.codex/agents/*.toml`, beside the built-ins `default`, `explorer`, and `worker` | 2026-10-04 | a probe run |
| Registered roles and levers | A role with `sandbox_mode = "read-only"` still wrote a file and ran a shell command. It did so under a parent run with `--dangerously-bypass-approvals-and-sandbox`, and again under `-s workspace-write -c approval_policy="never"`. A read-only role on Codex therefore rests on its body contract alone | 2026-10-04 | a probe run |
| Continuation | `codex exec` exposes `create_goal`, `get_goal`, and `update_goal` | 2026-10-04 | a probe run |

Codex has no recorded fact for `### Delivery and concurrency` or `### What a helper sees`, so both say so. Its `### Delivery and concurrency` names each of its figures as unrecorded.

Agent shells and scratch locations:

- A non-login `zsh -i` started from a bare environment resolves neither `markdownlint` nor `shellcheck`. It resolves `jq`, `python3` (3.9.6), and `bash` (3.2.57) to the operating system's builds, while a login `zsh -l` resolves the package-manager builds. A command run on 2026-09-27 showed this. The reference cites the SKILL.md's non-login rule, quoted in Context, for the reason, and records only the observation.
- zsh drops the backslash from `$'…\|…'` alternation (2026-09-05), and `${PIPESTATUS[0]}` expands to nothing under zsh (2026-09-15). Both come from local agent transcripts.
- Stock macOS ships neither `timeout` nor `gtimeout`, as a command showed on 2026-09-27 and again on 2026-10-04. Its BSD `xargs -P` runs parallel jobs. Neither the operating system's `python3` nor the package-manager build carries the `jsonschema` module. Commands showed both facts on 2026-09-27 and again on 2026-10-04.
- Files that sessions wrote under the system temporary directory were gone days later, once across a reboot and once between reboots, by directory listing on 2026-09-27. The operating system's daily temp cleaner, the launch daemon `com.apple.tmp_cleaner`, has an unverified retention rule. A helper's return file therefore belongs under the working root.

### The harness_portability body

In `plugins/ai_dev/skills/harness_portability/SKILL.md`, add one sentence to `<where_snapshots_live>` that names `references/delegation-surfaces.md` as the home of the per-host delegation facts.

Add one `<rule>` to `<policy>`, directly after the rule beginning "Confirm where a named agent actually registers", that sets the spawn route. A delegating skill, one that hands work to helper agents, runs its helpers only as sub-agents of the host it runs in. Sometimes the host offers no sub-agent surface, or a spawn fails. The skill then degrades by its own rules, to inline passes or to its stop-and-ask boundary, and launches no agent CLI process in a helper's place. Inline passes run the same work in the orchestrator's own context. The rule points at `references/delegation-surfaces.md` for its reason and restates no harness fact in the body, per `<where_snapshots_live>` and `<verify_before_encoding>`. Every other block stays as it is.

**Out of scope:**

- Building the eval runner's resume, inline-body, role-staging, and withheld-tool modes, which [the runner-modes task](tests_agent-spinner-runner-modes.md) owns.
- A print-mode CLI subsection, since the CLI flags and stream shapes go to the wiki.
- Running any probe, or recording a host beyond Claude Code, Cursor, and Codex, since the reference holds facts already observed and dated.
- Worker command templates for headless workers, since helpers run only as sub-agents.
- Any change to agent_spinner's own files, whose static greps keep per-harness facts out of its directory.
- Writing delegation facts to the wiki, which takes the research observations and the probe facts of 2026-10-04 directly.

## Acceptance

- `references/delegation-surfaces.md` exists under harness_portability. Its first line is `<!-- markdownlint-disable MD024 -->`. It holds the opening paragraph Approach describes, `## Claude Code`, `## Cursor`, `## Codex`, and `## Agent shells and scratch locations`. Each host section opens with its builds and holds exactly the five subsections Approach names, in that order. A subsection with no recorded fact, such as Codex's `### What a helper sees`, says so.
- Every fact under **Facts to record** appears in the reference with its date, its build, and its source kind. A 2026-10-04 probe-run entry carries the build Context records for the probe run on its host; every other entry and every shell fact reads `unrecorded`. Each table row sits under the subsection it names, and each shell fact under `## Agent shells and scratch locations`. Every Cursor entry names its mode.
- Cursor's `### Registered roles and levers` records `readonly: true` twice, each with its mode and date. One is the IDE observation that left the shell callable. The other is the print-mode observation that refused both the file write and the shell.
- Each host's `### Delivery and concurrency` states the delivery property, whether a notice carries the result, and the context window. It also states the fixed load per helper, the context-fill figure, the largest observed batch, and where a helper's own tool calls are recorded. Each appears as a recorded figure or as a statement that no record shows it. Claude Code's largest-observed-batch slot states that no single-message batch was recorded and names the 12-helper Workflow pool cap and the seven in-flight background agents as the figures that exist, not as the batch.
- A read of the reference finds no session count, per-session latency, writer count, or single-output size.
- `git diff` of harness_portability's SKILL.md shows one added sentence inside `<where_snapshots_live>` naming `references/delegation-surfaces.md`, one added `<rule>` inside `<policy>`, the required skill `version:` bump, and no other change. The rule names sub-agents of the host as the only helper route. For an absent surface or a failed spawn, it names degradation by the skill's own rules, with no agent CLI process launched in a helper's place. The rule points at `references/delegation-surfaces.md` for its reason and restates no harness fact in the body.
- Before commit, a manual read of every changed shipped file and this task's own diff finds no session, company, or project name, and no denylist is committed.
