---
description: Ship headless_launcher as the fallback for a failed native spawn, whose stdlib script runs one worker of the host's own agent CLI per manifest row under a watchdog and stop file.
scope: plugins/ai_dev/skills
created: 2026-10-03T13:54:08Z
updated: 2026-10-04T12:00:34Z
status: deferred
reported-by: Andreas Hoffmann
---

# Ship the headless_launcher fallback skill, its worker templates, and agent_spinner's citation of it

## Goal

When an orchestrator's spawn through the host's own sub-agent surface fails, it can fall back to a new skill, `headless_launcher`. The skill runs helper work as separate headless processes of that host's own agent CLI. The fallback exists only on a host whose launch probes passed. The skill also serves a user who asks for headless workers outright. Helpers keep spawning through the host's own sub-agent surface by default. The orchestrator writes a manifest that states why it launches and holds one row per worker. Each row names a command template copied from harness_portability, the values that fill it, a working directory, a bound, and a return-file path. The skill's bundled script turns each template into an argument list with no shell and runs each worker in its own session under a Python watchdog. It checks the stop file before each launch, launches pending checks ahead of queued writes, and writes each worker's captured standard output as that worker's return file.

The worker command templates live in a new harness_portability reference, `references/headless-workers.md`, so the skill itself holds no per-harness fact. agent_spinner cites the skill by name as the fallback route for a failed spawn, in every place its references mark headless workers unavailable. Two agent_spinner evals prove the order: a working sub-agent surface launches no headless worker, and a withheld one falls back to the launcher.

## Context

- **Deferred on 2026-10-04.** The owner dropped the headless launcher. Helpers run only as sub-agents of the harness the orchestrator runs in, because the modern harnesses this repository works with all offer sub-agents. A second launch route adds machinery and can engage where a sub-agent would have worked, and Anthropic charges more for `claude -p` runs than for helpers spawned inside a session. A skill whose spawn fails degrades by its own rules instead, as the spawn rule in the delegation-surfaces task states.
- **Decisions this task implements.** On 2026-10-03 the owner approved a headless-worker launcher as a separate skill, cited by name from agent_spinner, with its worker command templates in a harness_portability reference, filed to start only after the launch probes pass. On 2026-10-04 the owner made the launcher a fallback. Helpers spawn through the sub-agent surface of the harness the orchestrator runs in, and a headless process of that harness's own CLI runs only when spawning runs into issues: `claude -p` in Claude Code, `agent -p` in Cursor, and `codex exec` in Codex. The owner named cost as one reason, since Anthropic charges more for `claude -p` runs than for helpers spawned inside a session. The canonical statement is the spawn-route rule the delegation-surfaces task adds to harness_portability's `<policy>`. For this separate skill only, the 2026-10-03 decision reverses two Out of scope items of [the archived agent_spinner task](ai-dev_agent-spinner-skill.md). They are "A literal spawn-call syntax for any harness" and the workflow-runner and scheduler part of "A bundled runtime script, workflow runner, or scheduler, which the standing repo rules keep out of the toolchain". Inside agent_spinner both exclusions stay in force, and the archived task stays unedited as the decision record.
- **Start condition.** [The delegation-surfaces task](ai-dev_harness-portability-delegation-surfaces.md) records four launch probes under `## Probe log` in harness_portability's `references/delegation-surfaces.md`: "CLI launch from the agent shell", "Read-only worker output capture", "Workspace confinement", and "Withheld delegation". Start this task once "CLI launch from the agent shell" and "Read-only worker output capture" both read established for at least one host. Template only the hosts where they do at implementation time.
- **Verified worker shapes to draw on.** `build_print_cmd` and `worker_env` in `tests/lib/vendor.py` hold the worker command shapes the eval runners use on Claude Code and Cursor, proven by eval runs on the installed CLIs. Those shapes grant writes, so each read-only template takes its mode from the probe log's "Read-only lever enforcement" result instead. The launcher ships inside the plugin and imports nothing from `tests/`.
- **Why the watchdog is Python.** Stock macOS ships neither `timeout` nor `gtimeout`, observed by command on 2026-09-27 and again on 2026-10-04.
- **The agent_spinner text this task changes.** The tier table in agent_spinner's `references/run-protocol.md` gives headless workers the row text "Not available in this version.", and each recipe's tier notes close with "Headless workers are not available in this version." This task lands after every other live task that `grep -liE 'not available in this version|Lines every recipe carries' tasks/*.md` lists, because those tasks write that text into the tier table or carry it into a recipe file through the shared recipe lines. The greps in `tests/agent_spinner/script_tests/run.sh` reject product names, tool identifiers, harness paths, and sandbox-mode values anywhere in agent_spinner's directory, so the citation names the skill and nothing else.
- **Naming.** Under the standing repo rules on naming skills by invocation mode, a skill that is the only entry point for its capability keeps an ordinary family-first name. No shipped skill uses the token `headless`, so `headless_launcher` collides with no family.
- **Test rules.** TESTING.md's vendor rule governs the new evals, and its Test Integrity classes name each new check. The harness layout follows "## Adding a harness for a new skill" in `tests/CLAUDE.md`. New graders follow TESTING.md's `## Test Design Principles` and the grader rules [the grader-authoring task](tests_grader-authoring-discipline.md) adds there. Shell stays within the bash 3.2 floor that harness_portability states in its rule beginning "Target bash 3.2 as the interpreter floor".
- **Route evals.** [The runner-modes task](tests_agent-spinner-runner-modes.md) gives agent_spinner's eval runner the `disallowed_tools`, `needs_real_absence`, and `tool_record` fields that the two route evals under agent_spinner's citation use, so this task lands after it.

## Approach

### The skill

Create `plugins/ai_dev/skills/headless_launcher/` with `SKILL.md` and `scripts/launch_workers.py`, following the standing repo rules for a new skill, for pseudo-XML structure, for positive wording, and for a description written for both audiences. The body carries these blocks:

- `<role>`: the skill is the fallback route for helper work. It launches headless workers of the caller's own host CLI as separate processes, one per manifest row, for a caller that has already planned the run and whose spawn through the host's sub-agent surface failed, or whose user asked for headless workers. Choosing the helpers, checking their work, and aggregating their returns stay with the calling orchestrator.
- `<when_to_activate>`: a user's request to run helper work as headless CLI workers, or to fan out non-interactive CLI runs over a set of brief files, and an orchestrating skill whose host sub-agent surface is absent from the session or whose spawn failed. A caller whose sub-agent surface works spawns its helpers there and leaves this skill unloaded.
- `<prerequisites>`: read the worker template of the host the caller runs in, or of the host the user names, in the harness_portability skill's `references/headless-workers.md`, naming that skill rather than an installed path. A host with no established template has no headless route, so report that and stop.
- `<path_resolution>`: build the script's path from the loaded SKILL.md's directory and run `python3 -B <skill dir>/scripts/launch_workers.py`. On a missing-file error, re-resolve the path once before treating the script as unavailable.
- `<manifest>`: the schema below, with one worked example.
- `<launch_rules>`: one worker per row, whatever unit the row stands for. A reading worker's working directory is its snapshot copy, with its confinement stated as the reference records it. A checker runs at or above its producer's depth. Pending checks launch ahead of queued writes. The stop file is a real pause, checked before each launch. Commands are argument lists, never shell strings.
- `<results>`: read the launch log, hand each return file to the caller's acceptance step, and report the manifest's reason and every timed-out, failed, refused, and unlaunched row by label.
- `<output_contract>`: the report names each row's final state and the launch log's path.

The skill's directory names no target product, harness CLI flag, harness path, or orchestrating skill. Every per-harness fact lives in the harness_portability reference.

### The manifest and the script

The manifest is one JSON file:

```json
{
  "reason": {"kind": "spawn-failure", "detail": "<the failed spawn, in one line>"},
  "templates": {
    "reader": {"argv": ["<cli>", "<flag>", "{workdir}", "{prompt}"], "env_unset": ["<NAME>"]}
  },
  "rows": [
    {"label": "check:docs-setup", "kind": "check", "producer": "write:docs-setup",
     "template": "reader", "values": {"workdir": "<snapshot dir>", "prompt": "<one line>"},
     "cwd": "<snapshot dir>", "output": "<return file>", "bound_seconds": 600, "depth": 2}
  ]
}
```

`reason.kind` is `spawn-failure` or `user-request`, and `reason.detail` names the failed spawn or quotes the request in one line. A row's `kind` is `write` or `check`, `depth` is a non-negative integer rank the caller assigns, and a check row names its `producer`. The script runs as `launch_workers.py --manifest PATH --log PATH --stop-file PATH [--jobs N]`:

- **Interpreter.** One file, standard library only, Python 3.9 or newer. It checks its interpreter at start and exits with an actionable error below that floor, and it uses no syntax newer than 3.9, so that check runs first.
- **Validation.** Before any launch it refuses, with exit 2 and every problem named, a missing `reason`, an unknown `reason.kind`, an empty `reason.detail`, a duplicate label, an unknown template, a placeholder with no value, a value no placeholder uses, an `argv` that is not a list of strings, a non-positive bound, and an executable that resolves neither through PATH nor as an existing executable file. It also refuses a check row with no existing producer, and one whose `depth` sits below its producer's.
- **Filling.** Each `{name}` inside an `argv` element takes its row's value. Nothing is split or re-parsed, and every launch passes the list with no shell.
- **Scheduling.** At most `--jobs` workers run at once, one by default. A check row becomes ready once its producer exited 0 and its return file exists. Among ready rows, checks launch before writes, then manifest order applies. A check whose producer failed is refused and logged.
- **Stop file.** Before each launch the script checks the stop file. While it exists nothing new launches, running workers finish under their bounds, and the script exits 3 listing the unlaunched rows. A later run skips each row whose return file exists, so a paused run resumes where it stopped.
- **Each worker.** It starts in its own session, reads standard input from the null device, inherits the environment minus its template's `env_unset` names, and runs in its row's `cwd`.
- **Watchdog.** At a row's bound the script sends SIGTERM to the worker's process group, then SIGKILL after a short grace period, and records the row as timed out.
- **Return file.** On exit 0 the captured standard output is written atomically to the row's `output`, byte for byte. Standard error, and the standard output of a worker that failed or timed out, go beside the launch log and never to the return path.
- **Launch log.** JSON lines at `--log`, one record per event, with the manifest's reason in the first record. Each record holds the label, the state (launched, exited, timed out, refused, skipped, or stopped), the resolved executable path, the process id, UTC times, the exit status, and byte counts.
- **Exit status.** 0 when every row exited 0, 2 for a refused manifest, 3 when the stop file left rows unlaunched, and 4 when any row failed, timed out, or was refused.
- **Footprint.** The script writes only the return files, the launch log, and the diagnostics beside the log.

### The worker templates

Create `plugins/ai_dev/skills/harness_portability/references/headless-workers.md`. Each host's templates launch that host's own agent CLI, because a fallback uses the CLI of the host the caller runs in. For each host whose two start-condition probes read established, give:

- a read-only template and a writing template, each an argv array with named placeholders and its `env_unset` list, such as the session markers a nested worker needs stripped, which `worker_env` strips;
- how to resolve the binary, including a location off PATH;
- the authentication precondition;
- the "Workspace confinement" and "Withheld delegation" results, so a reader knows whether a reading worker's working directory confines it, with each result recorded as unverified where the probe did not establish it;
- the date, the build, and the smoke result below.

State the documentation gap: each template rests on help text and observed runs alone. Add one sentence to the opening of `references/delegation-surfaces.md` that points to the new reference for worker templates.

For each templated host, run one live smoke launch through the script: one read-only worker on a scratch working directory, whose brief asks for a final message ending in a fixed END line. Record its date, build, and result beside that host's template.

### agent_spinner's citation

Rewrite in place every passage `grep -rniE 'not available in this version' plugins/ai_dev/skills/agent_spinner` finds, so it names `headless_launcher` as the fallback route for a host with an established template in harness_portability's `references/headless-workers.md`. The route applies only when the host's own sub-agent surface is absent from the session or a spawn fails, and the run's report names the failure that triggered it. The tier table's row keeps the ledger calls the spawned-role rows use: `brief` and `dispatch` per row before the launch, `accept` on each return file after it, and `stop` for the stop file the launcher checks.

Add one check to the block of `tests/agent_spinner/script_tests/run.sh` headed "the advisory direction stays one-way": the launcher's skill directory does not cite agent_spinner.

Add two route evals to `tests/agent_spinner/evals/evals.json`, each with a fixture, a check in `tests/agent_spinner/evals/grade.sh`, and a signal row in `tests/agent_spinner/evals/README.md`. Both stage three brief files and a stub worker executable that the prompt names as the host's established worker template, and both set `tool_record`. The prompt asks for one helper per brief and names no route.

- `native_spawn_before_headless` withholds nothing. Asserted: `tool_calls.jsonl` shows one spawn-tool call per brief, and no manifest, launch log, or stub invocation marker exists.
- `headless_fallback_after_spawn_failure` sets `disallowed_tools` to the spawn class and sets `needs_real_absence`. Asserted: a manifest whose `reason.kind` is `spawn-failure` and whose detail names the missing spawn tool, three `exited` records with status 0 in the launch log, three return files, and a report that names the fallback and its trigger.

Keep every eval count the harness docs state equal to `jq '.evals | length' tests/agent_spinner/evals/evals.json`.

### Tests

Build `tests/headless_launcher/` on the layout the tests docs give:

- `script_tests/run.sh` holds the static checks. The frontmatter name and the H1 match the directory, `version:` has semver shape, and `scripts/` holds exactly `launch_workers.py`. The script imports only the standard library and passes no `shell=True`. The skill directory names neither `agent_spinner` nor any target product from harness_portability's `<target_harnesses>`. Every registration file the standing repo rules name for a changed skill list carries the skill.
- `script_tests/launcher_run.sh` runs the scenarios under Acceptance with stub workers, staging each under `script_tests/scratch/`. It finds every python3 the machine offers, runs each scenario under the oldest and the newest, and prints both versions.
- `run_all.sh` drives both runners with an aggregated exit code.
- `evals/` holds `evals.json`, a fixture per eval, a vendor-aware `run.py` built on `tests/lib/vendor.py`, and `grade.sh`. `README.md`, `RUNBOOK.md`, and `evals/README.md` with a signal row per eval complete the harness.
- `tests/README.md` lists the harness under "## Current harnesses", and the "## What's here" table in `tests/CLAUDE.md` gains its row. `tests/CLAUDE.md` and `tests/AGENTS.md` state its parallel-worker setting in lockstep.

Two evals, each asserting filesystem facts before any response marker:

- `launch_one_worker_per_brief`. Fixture: three brief files and a stub worker executable in the sandbox, with a prompt that names the stub as the host's worker template and asks for one headless worker per brief. Asserted: a manifest file whose `reason.kind` is `user-request` holds three rows whose template `argv` is a JSON array, three return files are byte-identical to the stub's output for their briefs, the launch log holds three `exited` records with status 0, and the report names the three labels.
- `stop_file_halts_launch`. Fixture: two briefs, the stub, and a stop file already present at the path the prompt names. Asserted: no return file and no stub invocation marker exist, the launch log records the stop, and the report names both rows as unlaunched.

### Registration and the wiki

Register the skill in every file the standing repo rules list for a changed skill list. Through the wiki skill family, record each templated host's verified worker template on that host's entity page, with its date, build, source kind, and documentation gap.

**Out of scope:**

- Choosing a run's helpers, checking their returns, and aggregating them, which stay with the calling orchestrator.
- A trigger-eval set for the new skill, which needs the skill deployed, a step the standing repo rules leave to the user.
- Templates for a host whose start-condition probes are not established.
- A fallback to another host's CLI that the user did not name, since each host falls back to its own CLI.

## Acceptance

- `plugins/ai_dev/skills/headless_launcher/` holds `SKILL.md` and `scripts/launch_workers.py`, with its directory, frontmatter `name:`, and H1 aligned, and the body carries the blocks Approach names.
- SKILL.md's `<role>` and `<when_to_activate>` name the skill as the fallback for an absent or failed host sub-agent surface and as the route for a user's request for headless workers, and `<when_to_activate>` sends a caller whose sub-agent surface works back to that surface.
- `python3 plugins/ai_dev/skills/skill_doctor/scripts/discovery_safety.py --root . plugins/ai_dev/skills/headless_launcher` reports no blocking finding.
- `python3 -B` on the script's absolute path with `--help` documents `--manifest`, `--log`, `--stop-file`, and `--jobs`. With the version it reads stubbed below 3.9, it exits non-zero naming the floor and the running version.
- `bash tests/headless_launcher/run_all.sh` exits 0 under the stock bash 3.2, prints the oldest and newest python3 versions it used, and passes each of these scenarios under both:
  - each validation refusal Approach lists exits 2 before any launch and names its problem;
  - the launch log's first record holds the manifest's reason;
  - a stop file present before the run launches nothing and exits 3;
  - a stop file planted while a worker runs lets that worker finish, launches nothing new, and exits 3 listing the unlaunched rows, and a rerun after its removal skips the completed rows and launches the rest;
  - a worker past its bound is killed together with a child process it spawned, is logged as timed out, and leaves no return file, and the run exits 4;
  - under `--jobs 1`, a check whose producer has just exited launches before a queued write, as the launch log's order shows;
  - a worker that exits 0 leaves a return file byte-identical to its standard output, and one that exits non-zero leaves no return file and leaves diagnostics beside the log;
  - `env_unset` names are absent from a worker's environment, and a worker reading standard input gets end of file;
  - argv elements carrying spaces, quotes, and shell metacharacters reach the worker unchanged;
  - in a scratch git repository, `git status` after a run shows only the return files, the launch log, and the diagnostics.
- Each static check fails on a scratch copy carrying one violation: an extra file in `scripts/`, a third-party import, `shell=True`, a target product name, or `agent_spinner` in the skill directory.
- `launch_one_worker_per_brief` and `stop_file_halts_launch` exist in `evals.json` with fixtures and `grade.sh` checks, each fact asserted before any response marker, and both pass under TESTING.md's vendor rule.
- `references/headless-workers.md` exists in harness_portability with templates only for hosts whose start-condition probes read established, each carrying the items Approach lists and its documentation gap, and `references/delegation-surfaces.md` points to it.
- Each templated host's live smoke launch ran through the script, and the reference records its date, build, and result beside the template.
- `grep -rniE 'not available in this version' plugins/ai_dev/skills/agent_spinner` finds nothing, and each rewritten passage names `headless_launcher` as the fallback for an absent or failed host sub-agent surface. The tier table's headless row names `brief`, `dispatch`, `accept`, and `stop`.
- `native_spawn_before_headless` and `headless_fallback_after_spawn_failure` exist in agent_spinner's `evals.json` with fixtures, `grade.sh` checks, and signal rows, both pass under TESTING.md's vendor rule, and every eval count the harness docs state matches `jq '.evals | length' tests/agent_spinner/evals/evals.json`.
- `bash tests/agent_spinner/script_tests/run.sh` passes with the new one-way check, which fails on a scratch copy of the launcher's skill directory that names agent_spinner.
- Every registration file the standing repo rules list carries the skill, `tests/README.md` and the table in `tests/CLAUDE.md` list the harness, and `tests/CLAUDE.md` and `tests/AGENTS.md` state the same parallel-worker setting for it.
- Each templated host's wiki entity page records its worker template's facts with date, build, source kind, and documentation gap, written through the wiki skill family.
- Before commit, a manual read of every changed shipped file, every changed wiki page, and this task's own diff finds no session, company, or project name, and no denylist is committed.
