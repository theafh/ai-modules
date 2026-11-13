<!-- markdownlint-disable MD024 -->

# Delegation surfaces across harnesses

This file records each host's sub-agent delegation facts, together with the agent-shell facts a delegating skill needs. A sub-agent is a helper agent that the host itself spawns from inside a session, and the agent shell is the shell in which a host's agent runs its commands. Every entry carries its observation date, the build it was observed on, and its source kind, so a reader can weigh the evidence behind it. Treat every entry as perishable and re-verify it against the current build before a change depends on it, per this skill's `<verify_before_encoding>` rule.

## Claude Code

Builds read 2026-10-04: the `claude` CLI on PATH is 2.1.226, and the Claude desktop application keeps newer builds of its own, 2.1.286 the newest. The probe-run entries below name the CLI build they ran on.

### Spawn surface

- The spawn tool appears as `Task` in the session's init tool list and as `Agent` in the stream's `tool_use` records. The `Workflow` tool also spawns agents, so a session meant to run without spawning needs both tools withheld. — Observed 2026-10-04; build `claude` 2.1.226; source: a probe run.
- A custom agent spawned through the Agent tool reached spawn depth 2. — Observed 2026-09-05; build unrecorded; source: analyst observation alone.

### Registered roles and levers

- A role file staged in the project's `.claude/agents/` directory appears in the init `agents` list and spawns by name, as `subagent_type: <name>`. — Observed 2026-10-04; build `claude` 2.1.226; source: a probe run.
- Deployed user-level roles reach a sandboxed session: the init `agents` list includes the user's deployed `auto_*` roles. — Observed 2026-10-04; build `claude` 2.1.226; source: a probe run.
- A role whose frontmatter `tools:` lists `Read, Grep, Glob` ran with exactly those tools. Its write and shell attempts found no tool, so the allowlist holds. — Observed 2026-10-04; build `claude` 2.1.226; source: a probe run.
- Tools denied to the parent session are denied inside its spawned helpers too. The refusal reads "disabled for this session, in subagents as well as here". — Observed 2026-10-04; build `claude` 2.1.226; source: a probe run.
- Workflow helpers run at spawn depth 1 and inherit the main loop's model and effort. — Observed 2026-09-05 and 2026-09-06; build unrecorded; source: local agent transcripts.
- General-purpose helpers keep every tool. The Explore type keeps the shell and describes itself as a search role that does not review. — Observed 2026-09-05; build unrecorded; source: local agent transcripts.

### Delivery and concurrency

- **Delivery property.** A background Workflow run returns a task id at once while the main loop keeps running tools. Its completion notice arrives later, so this is notice delivery, for the Workflow tool only; how a background spawn outside it delivers is unrecorded. — Observed 2026-09-05 to 2026-09-23; build unrecorded; source: local agent transcripts.
- **Notice carries the result.** Yes for the Workflow tool: the completion notice carries the result inline, truncated in some sessions, and the full result sits in a task output file. No record shows whether a notice outside the Workflow tool carries the result. — Observed 2026-09-05 to 2026-09-23; build unrecorded; source: local agent transcripts.
- **Context window.** No record shows the context window for this host.
- **Fixed load per helper.** Helpers start with about 55,000 tokens of context. — Observed 2026-09-15 and 2026-09-23; build unrecorded; source: analyst observation alone.
- **Context-fill figure.** No record shows a context-fill figure for this host.
- **Largest observed batch.** No single-message batch was recorded. Two figures exist and neither is the batch: the Workflow pool ran at most 12 helpers at once, a pool concurrency cap, and seven background agents were in flight at once, with their dispatch unrecorded. — Observed 2026-09-05 and 2026-09-22; build unrecorded; source: local agent transcripts.
- **Helper tool-call record.** A spawned helper writes its own transcript, `subagents/agent-<id>.jsonl` inside the parent session's transcript directory. Its records carry `isSidechain` set to true and the helper's `agentId`, and their `message.content` lists each tool call as a `tool_use` block with `id`, `name`, and `input`. — Observed 2026-10-04; build unrecorded; source: local agent transcripts.
- **Helper log format.** The description `agent_spinner`'s ledger reads for this host, proven against the log it names:

  ```json
  {
    "match": {"isSidechain": true},
    "calls": "message.content[]",
    "name": "name",
    "args": "input",
    "kinds": {
      "read": ["Read"],
      "write": ["Write", "Edit", "MultiEdit", "NotebookEdit"],
      "shell": ["Bash"],
      "spawn": ["Agent", "Task", "Workflow"]
    },
    "path_args": ["file_path", "path", "notebook_path"],
    "partial_args": ["limit", "offset"],
    "command_args": ["command"],
    "time": "timestamp"
  }
  ```

  It reads the helper's own transcript, `subagents/agent-<id>.jsonl` inside the parent session's transcript directory. The `message.content[]` list also carries blocks that are not `tool_use`; those hold no tool name, so the ledger skips them and keeps only the `tool_use` calls. Real-log audit: not run. The host read on 2026-11-13 was OpenCode, which spawns no Claude Code helper, so no helper transcript could be read. Result: a narrowing. The `match` value comes from the `### Spawn surface` and `### Delivery and concurrency` facts observed 2026-10-04 on build `claude` 2.1.226. The tool names and argument keys are inferred from the host's documented tool vocabulary — the `Read`, `Write`, `Edit`, `MultiEdit`, `NotebookEdit`, and `Bash` tools with the `file_path`, `path`, and `notebook_path` argument keys — which those facts do not name, so they remain unverified against a fresh log. — Observed 2026-11-13; build not read; source: no helper transcript on this host.
- The Workflow pool ran at most 12 helpers at once, consistent with first-in-first-out queuing. A checker queued behind writers therefore starts only once the writers ahead of it have left the queue. — Observed 2026-09-05; build unrecorded; source: local agent transcripts.
- The Workflow tool's description carries a default size guideline of keeping workflows under 10 agents, which the user's prompt may override. — Observed 2026-09-23; build unrecorded; source: local agent transcripts.
- Outside the Workflow tool, seven background agents were in flight at once. Whether one message dispatched them is unrecorded. — Observed 2026-09-22; build unrecorded; source: local agent transcripts.
- A schema-bound helper, one whose return must match a schema, retries inside its own turn. Its first schema-valid call ends it, even when that call is only a probe. After five failures the slot resolves falsy and the run completes. — Observed 2026-09-15; build unrecorded; source: local agent transcripts.
- Judging success by a state of `done` plus a filter that drops null results counts a schema-valid placeholder as a success. — Observed 2026-09-15 and 2026-09-23; build unrecorded; source: local agent transcripts.
- The workflow journal's result entries carry no label and arrive in completion order, and labels need not be unique. — Observed 2026-09-15; build unrecorded; source: local agent transcripts.
- The workflow output file holds progress entries with truncated previews, and a plain read of it truncates. Each entry's token figure is the helper's final request context size, which differs from the fresh tokens it spent. — Observed 2026-09-05; build unrecorded; source: local agent transcripts.
- A quiet-file interval, a stretch in which a watched file does not change, is not a completion signal. — Observed 2026-09-15; build unrecorded; source: analyst observation alone.
- A notice that completes during a blocking poll waits until the poll returns. A user message sent during an unbounded foreground wait never reached the model. — Observed 2026-09-15; build unrecorded; source: local agent transcripts.
- The shell tool blocks foreground and chained sleeps and points to a monitor or a background run instead. It moves any command running past 600 seconds into the background. A blocking task-output wait given 600 seconds returned at that value; whether the tool caps the wait is unverified. — Observed 2026-09-15 and 2026-09-16; build unrecorded; source: analyst observation alone.
- A stop kills helpers in flight without results, and their edits persist. After a pause request, freed slots kept starting queued helpers, and whether the tool offers a pause is unverified. — Observed 2026-09-05 and 2026-09-23; build unrecorded; source: local agent transcripts.

### What a helper sees

- Helpers receive the triggering request verbatim. — Observed 2026-09-15 and 2026-09-23; build unrecorded; source: analyst observation alone.
- The skill listing helpers receive comes from deployed copies, which can lag the working tree. — Observed 2026-09-05; build unrecorded; source: analyst observation alone.
- Deployed user-level skills reach a sandboxed session: the init `skills` list includes the user's deployed skills. — Observed 2026-10-04; build `claude` 2.1.226; source: a probe run.
- The shell snapshot, the captured shell setup the shell tool runs in, defines `grep` as a function running ugrep with `--ignore-files --hidden -I`. It omits the `./` prefix on results. It finds nothing inside a directory whose own `.gitignore` holds `*`, where the operating system's own `grep -rl` finds the file. — Observed 2026-09-06 and 2026-09-27; build unrecorded; source: local agent transcripts and a command run.

### Continuation

- Two continuation aids exist. One is a fallback wake-up, which an orchestrator set as a stall guard while a background run worked. The other is a loop skill that reruns a prompt on an interval or at a self-chosen pace. No run has exercised the loop skill. — Observed 2026-09-05, with the skill listing read 2026-09-27; build unrecorded; source: local agent transcripts and a skill listing.
- Print mode offers no goal tool. The session lists `ScheduleWakeup`, `CronCreate`, `CronDelete`, `CronList`, and `Monitor`, and no probe exercised them. — Observed 2026-10-04; build `claude` 2.1.226; source: a probe run.
- Resume replays the longest unchanged prefix of agent calls, so a byte-identical call placed after a changed one runs fresh. The cache is not keyed on content alone. — Observed 2026-09-24; build unrecorded; source: local agent transcripts.
- A resume reruns killed helpers against the current disk state. — Observed 2026-09-05; build unrecorded; source: local agent transcripts.

## Cursor

Builds read 2026-10-04: the Cursor IDE is 3.23.12, and its `agent` CLI, also installed as `cursor-agent`, is 2026.10.01, current with the IDE.

### Spawn surface

- *IDE mode.* The spawn tool, `Task`, accepts `description`, `subagent_type`, `prompt`, `model`, `run_in_background`, `resume`, and `readonly`. Custom agents are callable by name. — Observed 2026-09-16 and 2026-09-22; build unrecorded; source: local agent transcripts.
- *Print mode.* The orchestrator issued `Task` calls with `subagent_type: explore` and `model: inherit`, five in one message, so print mode exposes the spawn tool. — Observed 2026-10-03; build unrecorded; source: eval runs on the installed CLI.
- *Print mode.* A `Task` record holds `description`, `prompt`, `subagentType`, `model`, `agentId`, and `mode`. Its `subagentType` reads `custom.name` for a named role and `unspecified` otherwise. — Observed 2026-10-04; build `agent` 2026.10.01; source: a probe run.
- *Print mode.* The session's tools are `Shell`, `Grep`, `Glob`, `Read`, `Write`, `StrReplace`, `Delete`, `EditNotebook`, `TodoWrite`, `Task`, `AwaitShell`, `AskQuestion`, `SwitchMode`, `WebSearch`, `WebFetch`, `ReadLints`, `CreateGoal`, `UpdateGoal`, `GenerateImage`, and dynamic or MCP tools. — Observed 2026-10-04; build `agent` 2026.10.01; source: a probe run.
- *IDE mode.* A dynamic tool search that finds no spawn tool gives a false negative for delegation. — Observed 2026-09-26; build unrecorded; source: local agent transcripts.
- *IDE mode.* Nested spawning, a helper spawning a helper of its own, worked on 2026-07-02, with the parent resuming the child. No helper transcript since August 2026 holds a spawn call. — Observed as stated; build unrecorded; source: local agent transcripts.

### Registered roles and levers

- *Print mode.* A role file staged in the project's `.cursor/agents/` directory spawns by name. — Observed 2026-10-04; build `agent` 2026.10.01; source: a probe run.
- *Print mode.* The built-in subagent types are `generalPurpose`, `explore`, `shell`, `cursor-guide`, `ci-investigator`, `bugbot`, `security-review`, and `best-of-n-runner`. — Observed 2026-10-04; build `agent` 2026.10.01; source: a probe run.
- *Print mode.* Deployed user-level roles from the user's agents directory did not appear among the subagent types of a sandboxed session. — Observed 2026-10-04; build `agent` 2026.10.01; source: a probe run.
- *IDE mode.* `readonly: true` maps a helper to chat mode, removes its edit tools, and leaves the shell callable. — Observed 2026-09-17 and 2026-09-26; build unrecorded; source: local agent transcripts.
- *Print mode.* A role whose frontmatter says `readonly: true` ran in ask mode. Both its file write and its shell command were refused, and no file was created. — Observed 2026-10-04; build `agent` 2026.10.01; source: a probe run.
- *Print mode.* A `Task` call asked to set `readonly` recorded no read-only field (`mode: TASK_MODE_UNSPECIFIED`). That helper wrote its file and ran its shell command, so a per-call read-only setting was not observed. — Observed 2026-10-04; build `agent` 2026.10.01; source: a probe run.
- *IDE mode.* A tools allowlist in agent frontmatter is not enforced. — Observed 2026-09-26; build unrecorded; source: local agent transcripts.
- *IDE mode.* A requested per-call model of `fast` was recorded as `default`, so a per-call model's effect is unverified. — Observed 2026-09-16; build unrecorded; source: local agent transcripts.
- *IDE mode.* Effort keys in agent definitions had no observable effect, and helpers ran on `default` with max mode off. Per-definition model pins took effect in July 2026. — Observed 2026-09-16; build unrecorded; source: local agent transcripts.

### Delivery and concurrency

- **Delivery property (IDE mode).** Foreground `Task` calls in one message run concurrently and return together inside the turn, so they act as a barrier and the parent goes on only when all have returned: batch delivery. A background `Task` call returns at once, and its completion re-invokes the parent only after the parent's turn ends: notice delivery. — Observed 2026-09-16 and 2026-09-17; build unrecorded; source: local agent transcripts.
- **Notice carries the result (IDE mode).** No for a background spawn: its completion carries no result and can arrive in bursts. Foreground calls return inside the turn, so their results come back with the turn. — Observed 2026-09-16 and 2026-09-22; build unrecorded; source: local agent transcripts.
- **Context window (IDE mode).** The context window is 256,000 tokens. — Observed 2026-09-17 and 2026-09-26; build unrecorded; source: local agent transcripts.
- **Fixed load per helper (IDE mode).** Each helper starts with a fixed load of about 24,000 to 25,000 tokens. — Observed 2026-09-17 and 2026-09-26; build unrecorded; source: local agent transcripts.
- **Context-fill figure (IDE mode).** One parent context reached 55 percent of its 256,000-token window after five rounds of returns, about 24,000 tokens of it fixed host overhead. — Observed 2026-09-17 and 2026-09-26; build unrecorded; source: local agent transcripts.
- **Largest observed batch (IDE mode).** The largest observed batches were seven background calls in one message and five foreground calls in one response. — Observed 2026-09-16 and 2026-09-17; build unrecorded; source: local agent transcripts.
- **Helper tool-call record (print mode).** A helper's result reaches the parent as its final text inside the `Task` result, under `conversationSteps`. The helper's own tool calls appear only in the helper's own transcript. — Observed 2026-10-04; build `agent` 2026.10.01; source: a probe run.
- *Print mode.* Print-mode helper transcripts sit beside the parent's as top-level transcripts. — Observed 2026-10-03; build unrecorded; source: eval runs on the installed CLI.
- *Print mode.* Each print-mode helper transcript record holds `role` and `message`, whose `content` lists tool calls as `tool_use` blocks with `name` and `input`, several to a record. — Observed 2026-10-04; build `agent` 2026.10.01; source: a probe run.
- **Helper log format.** The description `agent_spinner`'s ledger reads for this host, proven against the log it names:

  ```json
  {
    "match": {"role": "assistant"},
    "calls": "message.content[]",
    "name": "name",
    "args": "input",
    "kinds": {
      "read": ["Read"],
      "write": ["Write", "StrReplace", "Delete", "EditNotebook"],
      "shell": ["Shell"],
      "spawn": ["Task"]
    },
    "path_args": ["path"],
    "partial_args": ["limit", "offset"],
    "command_args": ["command"],
    "time": "timestamp"
  }
  ```

  It reads the helper's own transcript, `.cursor/projects/<workspace>/agent-transcripts/<chat-id>/<chat-id>.jsonl` in print mode and `agent-transcripts/<parent>/subagents/<id>.jsonl` in IDE mode. One record may hold several calls, and the ledger reads each of them from `message.content[]`. The list also carries blocks that are not `tool_use`; those hold no tool name, so the ledger skips them and keeps only the `tool_use` calls. Real-log audit: not run. The host read on 2026-11-13 was OpenCode, which spawns no Cursor helper, so no helper transcript could be read. Result: a narrowing. The `match` value comes from the `### Spawn surface` and `### Delivery and concurrency` facts observed 2026-10-04 on build `agent` 2026.10.01. The tool names and argument keys are inferred from the host's documented tool vocabulary — the `Read`, `Write`, `StrReplace`, `Delete`, `EditNotebook`, `Shell`, and `Task` tools with the `path` argument key — which those facts do not all name, so they remain unverified against a fresh log. — Observed 2026-11-13; build not read; source: no helper transcript on this host.
- *IDE mode.* IDE helper transcripts are live JSONL files under `agent-transcripts/<parent>/subagents/<id>.jsonl`. They end in a `turn_ended` record and hold no tool results. — Observed 2026-09-22 and 2026-09-23; build unrecorded; source: local agent transcripts.
- *IDE mode.* The editor's state store keeps tool results and change tallies that the transcripts omit, and the transcripts record no token counts. — Observed 2026-09-16 to 2026-09-26; build unrecorded; source: local agent transcripts.
- *IDE mode.* Helper progress updates never reach the parent. — Observed 2026-09-22; build unrecorded; source: local agent transcripts.
- *IDE mode.* The build defines `subagentStart` and `subagentStop` hook events carrying status, duration, summary, and modified files. — Observed 2026-09-22; build unrecorded; source: the installed build, read in a local session.

### What a helper sees

- *IDE mode.* Manual attachment, where a user attaches a skill to the chat by hand, inlines only the SKILL.md body into the user turn, without frontmatter or references. The body sits under a note that files need reading only if needed. — Observed 2026-09-16 and 2026-09-23; build unrecorded; source: local agent transcripts.
- *IDE mode.* A helper's first turn holds only its prompt, and the parent's attached skills never reach it. — Observed 2026-09-16; build unrecorded; source: local agent transcripts.
- *Print mode.* Deployed user-level skills reach a sandboxed session, which read the user-level agent_spinner `SKILL.md`. — Observed 2026-10-04; build `agent` 2026.10.01; source: a probe run.
- *IDE mode.* Helpers can read sibling helpers' transcripts, and nothing isolates them. — Observed 2026-09-16 and 2026-09-22; build unrecorded; source: local agent transcripts.
- *IDE mode.* The parent and a background helper share one working tree and one git index. — Observed 2026-09-16; build unrecorded; source: local agent transcripts.
- *IDE mode.* Grep and Glob silently re-scope a path outside the workspace to the workspace. — Observed 2026-09-26; build unrecorded; source: local agent transcripts.
- *IDE mode.* The agent shell tool spawns non-login `zsh -i` shells. — Observed 2026-09-18; build unrecorded; source: a process listing.

### Continuation

- *IDE mode.* A built-in goal skill calls a `CreateGoal` tool whose goal persists across turns with no turn budget. A built-in loop skill reruns a prompt on an interval. Both skill files sit in the IDE's built-in skills directory under its user configuration root, and no run has exercised either. — Observed 2026-09-22, with the listing read 2026-09-27; build unrecorded; source: local agent transcripts and a directory listing.
- *Print mode.* `CreateGoal` and `UpdateGoal` are callable. A goal was created and later marked complete, and a resumed turn recalled it. No probe tested whether an armed goal keeps work going past the end of a turn. — Observed 2026-10-04; build `agent` 2026.10.01; source: a probe run.

## Codex

Builds read 2026-10-04: `codex-cli` is 0.160.0, and every fact below was observed through `codex exec`.

### Spawn surface

- `codex exec` exposes the native sub-agent tools `collaboration.spawn_agent`, `wait_agent`, `send_message`, `list_agents`, `interrupt_agent`, and `followup_task`. — Observed 2026-10-04; build `codex-cli` 0.160.0; source: a probe run.
- `--disable multi_agent` did not stop spawning. — Observed 2026-10-04; build `codex-cli` 0.160.0; source: a probe run.

### Registered roles and levers

- Spawnable roles come from the user's `~/.codex/agents/*.toml` and, in a trusted project, from `.codex/agents/*.toml`, beside the built-ins `default`, `explorer`, and `worker`. — Observed 2026-10-04; build `codex-cli` 0.160.0; source: a probe run.
- A role with `sandbox_mode = "read-only"` still wrote a file and ran a shell command. It did so under a parent run with `--dangerously-bypass-approvals-and-sandbox`, and again under `-s workspace-write -c approval_policy="never"`. A read-only role on Codex therefore rests on its body contract alone. — Observed 2026-10-04; build `codex-cli` 0.160.0; source: a probe run.

### Delivery and concurrency

- **Delivery property.** Unrecorded.
- **Notice carries the result.** Unrecorded.
- **Context window.** Unrecorded.
- **Fixed load per helper.** Unrecorded.
- **Context-fill figure.** Unrecorded.
- **Largest observed batch.** Unrecorded.
- **Helper tool-call record.** Unrecorded.

### What a helper sees

No record shows what a helper sees on Codex.

### Continuation

- `codex exec` exposes `create_goal`, `get_goal`, and `update_goal`. — Observed 2026-10-04; build `codex-cli` 0.160.0; source: a probe run.

## Agent shells and scratch locations

- A non-login `zsh -i` started from a bare environment resolves neither `markdownlint` nor `shellcheck`. It resolves `jq`, `python3` (3.9.6), and `bash` (3.2.57) to the operating system's builds, while a login `zsh -l` resolves the package-manager builds. The skill's non-login PATH rule gives the reason; this file records only the observation. — Observed 2026-09-27; build unrecorded; source: a command run.
- zsh drops the backslash from `$'…\|…'` alternation, and `${PIPESTATUS[0]}` expands to nothing under zsh. — Observed 2026-09-05 and 2026-09-15; build unrecorded; source: local agent transcripts.
- Stock macOS ships neither `timeout` nor `gtimeout`, and its BSD `xargs -P` runs parallel jobs. Neither the operating system's `python3` nor the package-manager build carries the `jsonschema` module. — Observed 2026-09-27 and 2026-10-04; build unrecorded; source: a command run.
- Files that sessions wrote under the system temporary directory were gone days later, once across a reboot and once between reboots. The operating system's daily temp cleaner, the launch daemon `com.apple.tmp_cleaner`, has an unverified retention rule. A helper's return file therefore belongs under the working root. — Observed 2026-09-27; build unrecorded; source: a directory listing.
