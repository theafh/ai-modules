---
description: "Move four hand-run checks into agent_spinner's run ledger: stamp routing, checklist coverage, decision packets, and a helper-log read audit, with Claude Code and Cursor log formats."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-10-03T15:54:08
updated: 2026-10-16T22:53:04
status: open
reported-by: Andreas Hoffmann
---

# Ledger phase 2 for agent_spinner: the markers check, the checklist lint, rendered decision packets, and the helper-log audit with Claude Code and Cursor log formats

## Goal

agent_spinner's run ledger, `scripts/run_ledger.py`, keeps the records of a helper run on disk. Its first version, which the run-ledger task ships, leaves four checks to the orchestrator, who runs them by hand. After this task the ledger runs all four itself, and each one has its own script tests:

- `close`, the verb that ends a run, refuses while a changed path that carries a stamp or marker has no routing to its owning gate. A stamp or marker is state that another skill family owns, such as a task's status or a wiki audit baseline. Its owning gate is the named step in that family that may change it.
- `brief`, the verb that renders a helper's instructions, refuses a checker brief whose checklist falls short of the artifact's acceptance items.
- `show`, the verb that prints the ledger's records, renders a decision packet from those records. A decision packet is the fixed form in which the orchestrator puts a fork, an open choice, to the user.
- `accept`, the verb that takes in a helper's return, audits the helper's log at a path the caller supplies. A full read then counts only with tool evidence, meaning a full-read tool call recorded in the log. A blind pass is a pass kept from seeing certain text, and it counts as blind only when its log shows no read outside its admitted inputs.

harness_portability's delegation reference gains a log-format description for Claude Code and one for Cursor. A description tells the ledger where that host's log records a helper's tool calls. Each one is proven on a real helper log, so an orchestrator on either host can run the audit. agent_spinner's references, and every passage that describes these checks, name the new behaviour. The ledger still holds no per-harness fact.

## Context

- **Current state.** [The run-ledger task](ai-dev_agent-spinner-run-ledger.md) ships `scripts/run_ledger.py` and its script tests in `tests/agent_spinner/script_tests/ledger_run.sh`. These parts of that program matter here:
  - `init`, the verb that opens a run, records which targets carry a stamp or marker, together with the owning family's gate. Each helper assignment is a row in the roster, the ledger's table of helpers, and the roster has a stamp owner column.
  - `close` exits 0 only when every condition on its list holds. No condition asks whether a changed stamped path was routed.
  - `dispose`, the verb that records what became of each record, records applied, refuted, surfaced with a packet id, and deferred dispositions.
  - A fork record carries its issue in one sentence, the verbatim passage with its anchor, two to four options each with a cost, and the helper's preferred end state.
  - In a helper's return, each `examined` entry claims a reading of `full`, `searched`, or `unreachable`, with one receipt line copied verbatim from the file. `accept` checks that line against the input version the row recorded.
  - `brief` takes a withheld text on standard input and keeps only its hash on the blind row, the row of a blind pass.
  - No verb reads a helper's log. Every full-read claim therefore stays claimed by receipt, backed only by its receipt line. Every blind pass stays blind by prompt, blind only because its prompt says so.
- **The rules these features enforce.** [The checking-doctrine task](ai-dev_agent-spinner-checking-doctrine.md) writes them into `references/checks.md` as numbered checks that the orchestrator runs by hand. Three of those checks matter here:
  - C2 counts checklist lines against acceptance items. It labels a blind pass blind by prompt unless the helper's logs show no read outside its admitted inputs.
  - C8 counts a path as read only where tool evidence shows a full read.
  - C9 has the ledger check only its own rows, so that every changed path recorded as stamped has a routing or fork row. Each family's file formats stay with that family.
- **Interfaces this task follows.** [The ledger-doctrine task](ai-dev_agent-spinner-ledger-doctrine.md) writes three parts of `references/run-protocol.md` from the shipped ledger: the command reference, P3, and P6. P3 covers return files and how `accept` checks them, and P6 covers findings, decision packets, and the report. The same task writes the closing report in `references/report-shapes.md` from the tally block, the block of counts that `close` prints. [The judgement-containment task](ai-dev_agent-spinner-judgement-containment.md) adds the decision packet to `references/report-shapes.md`. A packet holds the id `dispose` records when it surfaces the fork, the issue in one sentence, and each passage the fork touches, verbatim with its anchor. It also holds two to four options each with its cost, the objections recorded against each option, and a recommendation with its reason. For a fork a helper labelled, it holds that helper's preferred end state. [The delegation-surfaces task](ai-dev_harness-portability-delegation-surfaces.md) creates harness_portability's `references/delegation-surfaces.md`. Its `## Claude Code` and `## Cursor` sections each hold exactly five subsections. Each host's `### Delivery and concurrency` states where a helper's own tool calls are recorded. On both hosts that is the helper's own transcript on disk, and that transcript is the log each description reads.
- **Landing order.** This task lands after the run-ledger, checking-doctrine, ledger-doctrine, judgement-containment, and delegation-surfaces tasks. It also lands after [the review-repair recipe task](ai-dev_agent-spinner-review-repair-recipes.md), [the rewrite-implement recipe task](ai-dev_agent-spinner-rewrite-implement-recipes.md), and [the decision-research recipe task](ai-dev_agent-spinner-decision-research-recipes.md). Those three add recipe files, each a guide to one kind of job. Wherever a recipe or `references/variants.md` labels a pass blind, it may repeat C2's wording about a log "at a path the caller supplies". The rewrite under Approach must find every such passage.
- **How hosts record a helper's tool calls.** Local transcripts read on 2026-10-04 show that each host writes a spawned helper's work to the helper's own transcript on disk, one JSON record per line.
  - On Claude Code that file is `subagents/agent-<id>.jsonl` inside the parent session's transcript directory. Each record carries `isSidechain` set to true and the helper's `agentId`. A tool call is a `tool_use` block with `id`, `name`, and `input` inside the record's `message.content` list. Claude's spawn tool is named `Agent` in those records, and the `Workflow` tool also spawns agents.
  - On Cursor, a helper spawned in print mode, the non-interactive command-line mode, has its transcript beside the parent's as a top-level transcript. An IDE helper's transcript sits under `agent-transcripts/<parent>/subagents/<id>.jsonl`. Its records hold `role` and `message`, and a tool call is a `tool_use` block with `name` and `input` inside `message.content`. One record can hold several calls, and the transcript records no tool results.
- **Decisions in force.** On 2026-10-03 the owner approved bundling the run ledger inside agent_spinner, as one standard-library script that keeps a run's records and launches no helper. This task extends that script within the same decision. The workflow-runner and scheduler exclusions of [the archived spinner task](archive/ai-dev_agent-spinner-skill.md) stay in force.
- **Constraints the program already carries.** The run-ledger task's section headed "Portability and failure", including its bullet "Text the static greps scan", binds every new line. The program holds no per-harness fact, takes host specifics as values from the caller, and reads git without writing to it. Its acceptance requires `--help` to list exactly the frozen verb set, the fixed list of verbs the ledger ships. This task therefore adds flags and one close condition, and no verb.

## Approach

### The four additions

- **Markers check.** This check makes sure a changed file that carries a stamp or marker reaches its owner. Its interface is one more `close` condition, a `status` listing, and a routed disposition in `dispose`. `close` exits 3 while a changed path that `init` recorded as stamped or marked has neither a routed disposition naming its owning gate nor a fork record naming the path. It lists each such path, and `status` lists them while the run is open. `dispose` records a changed path as routed to a named gate, and it refuses a gate other than the owner `init` recorded for that path. The check reads only the ledger's own records and never a family's files.
- **Checklist lint.** This check makes sure a checker's checklist covers every acceptance item of the artifact it checks. Its interface is `brief <label> --acceptance PATH` on a checker row, with `PATH#Heading` for a section. `brief` reads the acceptance items as the list items of the file, or of the section the heading names, and compares them with the item brief's numbered checklist. It refuses a brief with fewer checklist lines than acceptance items. It also refuses a brief where some item's text, whitespace collapsed, appears in no checklist line, and it names each unmatched item. It records the acceptance source's version on the row.
- **Rendered packets.** The ledger builds each decision packet from its own records. The interface is `show --packet ID`, and `dispose ... surfaced --packet ID --recommend TEXT`. `show --packet` prints the decision packet for the fork surfaced under that id, in the shape `references/report-shapes.md` defines. The fork record supplies the id, the issue in one sentence, each passage byte for byte with its anchor, and the options with their costs. For a fork a helper labelled, it also supplies the helper's preferred end state. Every record whose `fork` field names that fork renders as an objection under the option it names. The recommendation and reason recorded with the surfaced disposition close the packet. `show --packet` refuses an id with no surfaced fork, and `status` lists the open packet ids.
- **Helper-log audit.** The ledger reads a helper's own log to see what the helper actually did. The interface is `accept <label> --audit-log PATH --log-format FILE`. `accept` reads the row's calls from the helper's log through the caller's log-format description. For that row it records each path the log shows read in full, as tool evidence. It also records each read outside the row's admitted inputs, each shell command that invokes the ledger, and each spawn call. A row's admitted inputs are its brief, its start marker and return paths, and the input versions its brief recorded. On a row already accepted, `accept` adds the audit records and leaves the row's state unchanged. At the inline floor, where the orchestrator runs every pass itself in one context, the orchestrator passes its own session log for its own passes.

### What the audit records change

The audit's records change four things in a run:

- The tally block that `close` renders splits coverage four ways: read in full by tool evidence, claimed by receipt only, only searched, and unexamined.
- A blind row is labelled blind only when its audit found no read outside its admitted inputs and no ledger or spawn call. Every other blind row stays labelled blind by prompt, and so does every blind row with no audit.
- A ledger invocation or a spawn call in any row's log becomes a containment incident record on that row, since no helper may run the ledger or spawn helpers. The existing condition that every record has a disposition then keeps `close` refusing until the incident is disposed of.
- An unreadable log, or a description that fails to parse or matches no call, makes `accept` refuse with a non-zero exit naming what to fix. That row's coverage stays claimed by receipt, and the report names this as a narrowing, a check the run drops or shrinks.

### The log-format description

Each host writes its logs in its own format, and the ledger reads every host through the same code. The caller therefore supplies one small JSON file per host, the log-format description, which tells the ledger where to find the calls. The log holds one JSON record per line, and the description has these keys:

- `match` lists optional key paths with the values a record must carry to hold calls, and the ledger tests them on the record itself.
- `calls` is a key path from the record to its candidate call objects, where `[]` marks a list to iterate.
- `name` and `args` are key paths inside a call to the tool name and to its arguments.
- `kinds` maps `read`, `write`, `shell`, and `spawn` to lists of tool names.
- `path_args` lists the argument keys that hold a path, `partial_args` the keys whose presence marks a partial read, and `command_args` the keys that hold a shell command.

A call object whose tool name does not resolve is skipped. A read call naming a path with no partial-read argument counts as a full read. Every path is normalized relative to the repository root, as the program already does for its other joins. The log is the helper's own transcript, so every matching record in it counts as the row's.

In harness_portability's `references/delegation-surfaces.md`, add a **Helper log format.** entry to the `### Delivery and concurrency` subsection under `## Claude Code` and under `## Cursor`. Place it beside the fact that says where a helper's own tool calls are recorded. Each entry holds that host's description as a fenced JSON block, names the log it reads, and records the date, build, and result of its real-log audit. Each host section keeps its five subsections. Each description reads the helper's own transcript. Both descriptions list calls from `message.content[]`, keep only `tool_use` blocks, and take `name` and `input` as the name and argument paths. Claude Code's description also matches records carrying `isSidechain` set to true, and Cursor's reads records that may each hold several calls. Take each description's tool names, argument keys, and match values from the real log audited for that host. For a kind that log does not exercise, take them from the facts in Context.

The real-log audit is this task's proof that each description works. For each host, run a session in which a parent spawns one helper that reads one file in full and another in part, while the parent reads a third file itself. On both hosts the audit reads the helper's own transcript, so the parent's read stays off the helper's row.

### Docs

- In `references/run-protocol.md`, add each new flag and the markers condition to the command reference, and have P6 render each decision packet with `show --packet`. Add `--audit-log` to P3's flags, together with the step that writes the host's description to a file under the run directory and passes that file as `--log-format`. That step takes the description from harness_portability's delegation reference.
- Rewrite in place every passage that `grep -rn 'at a path the caller supplies' plugins/ai_dev/skills/agent_spinner` finds, so it names `accept --audit-log`. That covers C2 and C8 in `references/checks.md`, and every recipe or `references/variants.md` passage that repeats the wording. In `references/checks.md`, also rewrite the C2 passage on checklist lines and acceptance items so it names `brief --acceptance`. Rewrite the **Checks** line under `## C9.` so it names the markers condition of `close`. Each rewrite replaces the wording that describes the check as run by hand, so one statement of each rule remains.
- In `references/report-shapes.md`, show the tally's four-way coverage split in the closing-report example.
- Each new flag answers its verb's `--help`. `SKILL.md` stays unchanged.

### Script tests

Add scenarios to `ledger_run.sh`. Stage them under `script_tests/scratch/`, and run them under the oldest and newest python3, as that harness already does. The audit scenarios use synthetic logs in two synthetic formats, each with its own description, so the tests prove the code reads every format through descriptions alone. One format holds one call per record. The other holds several calls in a list inside the record, with its `match` on the record. Synthetic tool names keep the test files free of any host's real tool vocabulary.

**Out of scope:**

- A parser for any one host's log inside the ledger, since the program holds no per-harness fact and each host's description lives in harness_portability.
- A family's own stamp, capture-hash, or log formats, which stay with the task and wiki families.
- A log-format description for any host other than Claude Code and Cursor.

## Acceptance

- `python3 -B` on the ledger's absolute path with `--help` still lists exactly the frozen verb set. The `--help` of `close`, `dispose`, `brief`, `show`, `accept`, and `status` names each new flag or listing.
- `bash tests/agent_spinner/run_all.sh` exits 0 under the stock bash 3.2, and `ledger_run.sh` passes every scenario below under the oldest and newest python3 it finds.
- Markers: a changed stamped path with no routing keeps `close` at exit 3 with the path named, and `status` lists it. A routed disposition naming the recorded owner clears it, and so does a fork record naming the path. A routed disposition naming another gate is refused. An unstamped changed path and an unchanged stamped path each need neither.
- Checklist lint: a checker brief whose checklist carries every acceptance item verbatim renders. A brief missing one item is refused with that item named, and a brief with fewer lines than items is refused. A heading-scoped source reads only its section, and the row records the source's version.
- Packets: a helper-labelled fork with two options and one objection record renders every field `references/report-shapes.md` lists for a decision packet. The passage is byte-identical to the fork record's, and the helper's preferred end state is present. An unknown id is refused, and `status` lists the open packet ids.
- Audit: in each of the two synthetic formats, a full read records tool evidence and a ranged read does not. A blind row whose log stays inside its admitted inputs is labelled blind. A blind row that read one outside path stays blind by prompt, and so does a blind row with no audit. A ledger invocation and a spawn call each record an incident that keeps `close` refusing until it is disposed of. A malformed description and an unreadable log are each refused, and an audit on an accepted row leaves its state unchanged.
- The tally block in a closed run splits coverage into read in full by tool evidence, claimed by receipt only, only searched, and unexamined, with counts that match the rows' records.
- In harness_portability's `references/delegation-surfaces.md`, the `### Delivery and concurrency` subsection under `## Claude Code` and under `## Cursor` each carries a **Helper log format.** entry. Each entry holds a description the ledger parses, names the log it reads, and records the date, build, and result of its real-log audit. Each host section still holds exactly five subsections.
- Each entry's recorded real-log audit shows the helper's full read counted as tool evidence and its partial read left without it. Each audit also shows the file only the parent read absent from the helper's row.
- The command reference in `references/run-protocol.md` names every new flag and the markers condition. P3 names `--audit-log` with the step that writes the host's description to a file under the run directory, and P6 names `show --packet`.
- Every passage that `grep -rn 'at a path the caller supplies' plugins/ai_dev/skills/agent_spinner` finds names `accept --audit-log`. In `references/checks.md`, the C2 passage on checklist lines names `brief --acceptance`, and the **Checks** line under `## C9.` names the markers condition of `close`.
- `bash tests/agent_spinner/script_tests/run.sh` passes, its greps included, with the extended ledger in the tree.
- Before the commit, a manual read of every changed shipped file and of this task's diff finds no session, company, or project name, and no denylist is committed.
