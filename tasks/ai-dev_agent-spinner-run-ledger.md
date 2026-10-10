---
description: Bundle scripts/run_ledger.py in agent_spinner, a standard-library program that keeps a helper run's records and launches no helper, with its tests, check fixes, lint prune, and docs.
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-10-03T15:54:08
updated: 2026-10-09T17:12:48
status: open
reported-by: Andreas Hoffmann
---

# Bundle the run ledger in agent_spinner

## Goal

Today an orchestrator running agent_spinner holds a run's records in its own context. After this task, it keeps those records on disk through one bundled program, `scripts/run_ledger.py`, the run ledger. The ledger refuses to close a run while any unit, returned record, fork, or landed write is unaccounted for. A unit is one enumerated item of work, and a returned record is a finding or other entry in a helper's answer. A fork is an open choice between options, and a landed write is a file change in the tree. Each omission that used to fail silently therefore becomes a non-zero exit. The ledger records the spawns the orchestrator makes and launches no helper itself.

The program ships proven by its own script tests. The skill's static contract, one eval grader, the repository's lint scope, the harness docs, and the wiki concept page all change to describe a skill that now bundles one program.

## Context

The owner approved bundling the ledger on 2026-10-03. For this one script, that decision reverses two items of [the archived agent_spinner task](archive/ai-dev_agent-spinner-skill.md): the Goal sentence "Ship it prose-only", and the Out of scope item "A bundled runtime script, workflow runner, or scheduler, which the standing repo rules keep out of the toolchain". The workflow-runner and scheduler exclusions stay in force inside agent_spinner. The archived task stays unedited as the decision record. Its stated reason no longer holds, because the standing repo rules and `CHARTER.md` now accept Python 3 as a standing dependency. They also place a skill's helper script inside the skill, under `scripts/`.

The owner approved three further rules the same day, and this task implements them in code:

- The run directory, where the ledger keeps a run's files, is `.agent_spinner/` in the working root. Its own `.gitignore`, holding `*`, hides it from git. A gate is a check command, such as a linter. A gate-scope check runs through planted known positives, files with a known defect, and shows whether a gate also reads the run directory. An auto-fix gate is refused while run state exists, and the directory is queried only through the ledger. This repository's Makefile `EXCLUDE` gains a prune for it.
- The snapshots that reading passes read are file copies under the run directory. The run writes no ref, tree, commit, or object into the user's repository.
- Each repaired item gets one re-check at no lower depth than its first check, with no second repair round. Depth is the model and effort level a helper runs at. `dispatch`, the verb that marks a helper as sent, enforces the counting half of that rule.

The case for a mechanism comes from observed orchestration runs. Scripted runs that encoded six properties avoided the failures that prose-only runs had:

- Width, the number of helpers, equals the length of an enumerated list.
- Returns are checked before they count.
- Joins go by identity, so each return is matched to its row by the identifier it echoes.
- Counts are computed from records.
- The verdict waits for every checker.
- Every landed write is reviewed against a recorded baseline.

Scripted runs that left one property out failed the same way. Three failures hit both kinds of run, and each gets a refusal with its own script test. The first is a schema-valid hollow return, which passes the format check but holds placeholder content. The second is a join by index or by a shared label. The third is an integrator write nobody reviewed, a change made while merging results.

The run directory sits in the working root for three reasons. Helpers can write there under the host's write scope. It survives reboots and temp cleaning. Searches outside the workspace can be silently re-scoped. Search tools that honour ignore files skip a directory whose own `.gitignore` holds `*`, which is why queries go through the ledger. Gates that list files themselves still see the directory, which is why the gate-scope check exists.

Current state, verified on 2026-10-03:

- `plugins/ai_dev/skills/agent_spinner/` holds `SKILL.md` at version 1.0.1 and `references/`, and no `scripts/`.
- `bash tests/agent_spinner/script_tests/run.sh` runs the skill's static contract, a set of file and grep checks, and passes. Its version check, labelled "frontmatter version is semver", already asserts only the semver shape and names itself a grader fix under TESTING.md's Test Integrity rule. The check labelled "the skill bundles no runtime scripts" asserts that `scripts/` is absent. The greps behind the checks listed next recurse through the whole skill directory and ignore case, so they will scan the ledger too: "no per-harness frontmatter keys or tool identifiers", "no harness agent directory paths", "no sandbox mode values", "every target product name cites harness_portability", and "no instruction to write a global rules or agent-config file".
- In `tests/agent_spinner/evals/grade.sh`, the eval grader, `PHASE_PLAN='phase|pass 1|phases:'` passes on any mention of a phase. The inline_floor and phase_plan_announcement evals both expect a plan of two to four named phases, which `<phase_plan>` in `SKILL.md` requires today.
- The Makefile builds `MD_FILES`, `JSON_FILES`, and `SH_FILES` with `find .` under `EXCLUDE`, which prunes no `.agent_spinner`. `fix-md` runs `markdownlint --fix` over `MD_FILES`. The comment above `EXCLUDE` says its prunes mirror `tests/.gitignore`, and the standing repo rules change the two lists together so lint scope matches git scope. `lint-sh` already enforces the bash 3.2 construct floor, which allows only shell constructs bash 3.2 supports, over every shell file in scope.
- `WORKER_PROMPT` in `tests/agent_spinner/evals/run.py`, the eval runner, asks the worker to keep `announcement.txt`, `roster.tsv`, `briefs/<label>.txt`, and `report.md` under `.agent_spinner/`. The ledger keeps those paths, so the runner's prompt and state paths stay unchanged.
- [tests_agent-spinner-runner-modes](tests_agent-spinner-runner-modes.md) edits the same agent_spinner row in `tests/CLAUDE.md` and the same agent_spinner bullet in `tests/README.md`. This task rewrites the clause calling the skill prose-only, and that task rewrites the clause about denying the spawn tool.

## Approach

Write `plugins/ai_dev/skills/agent_spinner/scripts/run_ledger.py` as one file that imports only the standard library and needs Python 3.9 or newer. The program works through verbs, its subcommands, such as `init` and `close`. Every verb works on `.agent_spinner/` under its current directory, which is the working root. The program holds no per-harness fact. Anything specific to a host, such as a host log path or a wave cap, the most helpers sent at once, arrives as a value from the caller. The program writes only under the run directory. The files are the contract: their layout and formats define the ledger's behaviour, so an orchestrator on a host that cannot run python3 can keep the same files by hand.

Several words recur below. A row is one helper's assignment, and the roster holds one line per row. Each row has a stable `role:item` label, built from the unit's stable slug, a short unique name. A brief is the instruction file one helper reads, and its last line is the brief token, a short code the helper's return must repeat. A return is the helper's answer, and it ends with its END line, `END <label>`. The baseline records the repository's state when the run opens, so later steps can measure what changed. The probe is a first test spawn that shows what the host can do, and the rung is the capability tier the run reaches. A narrowing is a check the run drops or shrinks. A user gate is a question that waits on the user's answer. A wave is a batch of helpers sent together.

### Run directory

The ledger keeps this layout:

```text
.agent_spinner/            the current run; its own .gitignore holds "*"
  run.json                 run id, probed rung and capabilities, phases, bound, wave size,
                           block hashes, baseline commit
  request.txt              the request, verbatim
  intent.md                frozen intent; its hash is stamped into every brief
  preamble.md              invariant preamble; facts.tsv holds settled facts with tier and source
  access/<phase>.md        access block per phase; kinds/<kind>.md holds kind notes
  items/<label>.md         item briefs
  roster.tsv               one line per helper row
  exclusions.tsv           excluded item and reason
  briefs/<label>.txt       rendered briefs, the fixed probe brief included
  returns/<label>.start    start marker a file-writing helper creates first
  returns/<label>.md       helper return
  ledger.jsonl             findings, forks, flags, incidents, own-authority calls,
                           narrowings, gates, checks
  baseline/                HEAD, status and stash-list records, hashes, copies of files
                           modified at start
  snapshots/               file copies for reading passes, base-commit copies included
  diffs/ gates/ outbound/  per-file diffs, gate logs, outbound drafts
  controls/                the known positives init plants for the gate-scope check
  STOP                     while present, nothing new is dispatched
  announcement.txt         the opening announcement
  report.md                the closing report
  history/<run-id>/        closed runs
```

A closed run stays readable at these flat paths until the next `init` moves it under `history/<run-id>/`, so the eval harness still finds a closed run's roster, briefs, and report.

### The frozen verb set

The verb set is frozen: the ledger has exactly these verbs.

- `init` opens a run. It creates the run directory and its `.gitignore`, then opens a run over the enumerated list the caller names. It loads each unit as a row with a stable slug, records each exclusion with its reason, and records the baseline. It records which targets carry a stamp or marker, state that another skill family owns, together with the owning family's gate. It plants one known-positive file per file type the named gates read, each holding one lint defect and one counted marker. It runs each gate at the baseline and records whether that gate reported its planted file. It prints the counts the announcement needs. It refuses a blank, duplicate, or case-colliding slug, and a gate the caller marks as auto-fixing. It refuses a new run while one is open, naming `attach` in that refusal.
- `init --probe` prepares the probe. It creates the run directory and renders the fixed probe brief once per spawn route the caller names: the cheapest route and each registered role the host lists. It opens no run, so the later `init` opens it. Accepting a probe row records each capability as established, assumed absent, or unverified. The read-only lever, a host setting that stops a helper from writing, counts as enforced only when the probe's write attempt inside the run directory left no file. Model and depth count as observed only where the host exposes the helper's settings to the run.
- `attach` re-enters an open run. It re-reads `run.json`, checks HEAD and the tree guard against the baseline, prints the status and the pending returns, and records the re-entry time. The tree guard is the comparison of the repository's git state with the baseline. A completion notice, a user message, and a fresh session all re-enter through `attach`.
- `brief` writes one helper's instructions. It renders one brief from the run's fixed blocks in a fixed order and appends a closing block. The closing block holds the role's return template, the return channel, the END line, the no-delegation clause, the capabilities stated as facts, the bound, and the brief token as the last line. The return channel says how the helper delivers its return, the no-delegation clause tells the helper to delegate no part of its item, and the bound is the time the helper may take. A writer's closing block adds the start-marker instruction and the rule that its final message is only its END line. `brief` relays upstream material, meaning earlier returns, by path, or pasted under a stated cap with the trimmed ids listed. It refuses a relay whose upstream row is unaccepted. It records the version of every input the brief names, relayed returns included, and the row's obligations, such as the paths its `examined` list must cover. It refuses shared blocks that differ within a phase, and a brief that both forbids and permits one path or command. It warns on steering words in a checker brief, words that push the checker toward a verdict. One provisional flag takes a withheld text on standard input and records only its hash in the blind row's input versions. A blind row is the row of a pass that must not see that text.
- `dispatch` records that a helper was sent. It marks a row dispatched with its UTC time and spawn route. `--helper-id` records the host's id for the spawn where the host gives one, and `--model M --effort E` records the requested values. It refuses while `STOP` exists, while W written rows are unchecked, W being the wave size, and while a user gate is open for a writer. It refuses a third attempt, a second repair of the same path, and a second re-check of the same repaired item.
- `accept` takes in a helper's return. It validates a return file against the return contract, imports its records with stable ids, and records the source as `file`. `--stdin <label>` takes the verbatim final message, or a host log file the caller pipes instead, stores it at `returns/<label>.md`, and records the source as `relayed` or `log`. `accept` checks each receipt line, a line the helper copied verbatim to show it read a file, against the input version the row recorded, never against the live file. It checks a withheld text's later version against the blind row's hash. It tags each confirmation recall-confirmed when the checker's brief relayed that record, and independently surfaced otherwise. `--observed-model M --observed-effort E` records what the host exposed to the run, or `unobserved`. `--wait` polls the return files for at most 90 seconds per call until every row of the wave is terminal or past its bound, and it marks a row past its bound unreturned. `--classify` records the orchestrator's call on a free-text return.
- `rows` adds rows for a later phase. `--phase P --from-records PATTERN`, `--from-repair-list`, or `--from-gaps LABEL` creates one row per source record. It derives each slug from the record id, refuses a duplicate, and records the source phase.
- `dispose` records what became of each record. It records final dispositions singly or by id pattern, and each disposition is one of four. Applied is tagged re-derived or taken on a helper's word. Refuted carries its span, surfaced carries a packet id, and deferred carries a durable pointer. `dispose` also records narrowings with the checks they drop, attributions, and user gates.
- `diff` measures what changed. It measures the net change against the baseline and HEAD, attributes each change to a writer row, the orchestrator, or an outside source, and writes each per-file diff under `diffs/`. `--add-checks` adds a check row for every changed path, whoever wrote it. `diff` flags date-only changes, mostly-deleted files, and append-only violations, maps hunks to approved-edit ids, and runs the tree guard. `--count` runs counters with built-in known positives.
- `gate` runs a check command. `gate NAME -- ARGV` runs a command without a shell and records its exit status, its output, and its executable's resolved path. `--expect exit0` records a silent pass as silent, `nonempty` fails on empty output, and `count` needs a counter whose positive control passed. For a gate that reported its planted file, `gate` drops findings under the run directory and says so on the gate line. It names a gate the filter cannot handle as a narrowing. `--on-baseline` records the baseline run, and later runs report the difference. An executable that does not resolve makes the gate unavailable, recorded as a narrowing.
- `snapshot` makes read copies. It copies the files a reading row needs, from the baseline or the working tree, into `snapshots/`. `--base` copies the base commit's files through `git show`, so nothing enters the repository.
- `status` shows where the run stands. It prints the live tally, each open row with its bound deadline, each open gate, the repair list, and a resume listing by brief hash.
- `show <label>` prints one row's records in full.
- `search` runs a pattern search over the run directory in Python, with its own positive control.
- `stop` creates `STOP`, so nothing new is dispatched.
- `close` ends the run. It renders the tally block, which holds the run's counts, and checks that `report.md` carries that block byte for byte. The block splits confirmations into recall-confirmed and independently surfaced. It prints advisory claim lines, flags "independent" on a row tagged recall-confirmed, and flags every checker whose recorded depth sits below its producer's. While any close condition fails, it exits 3 and lists the open items. `--stopped` lists modified, untouched, and unknown paths. When `close` closes the run, it removes the snapshot copies and keeps their hashes on the roster.

Each verb answers `--help` with the meaning its entry above gives, so the command reference can be written from the program. One working root holds one open run.

### Roster, return contract, and close conditions

`roster.tsv` holds one line per helper row with these columns in this order: label (the stable `role:item` label the return echoes), phase, role, item (the unit's stable slug), path, kind, state, attempts, brief hash, input versions, helper id, spawn route, model_req, effort_req, model_obs, effort_obs, dispatched at, start-marker time, returned at, source, and stamp owner. State takes pending, dispatched, violation, accepted, inability, failed, unreturned, unknown, or dropped. Input versions hold the baseline copy for a writer's target, the snapshot for a reader, and each relayed return. For a blind pass they also hold the hash of each withheld text. Spawn route names a registered role or a generic spawn, with the lever and depth as the probe found them. Times are UTC, and the start-marker and return times come from the filesystem. A checker's producer is the row whose return its brief relayed.

A return may open with prose for people. It holds exactly one fenced JSON block and ends with the line `END <label>`. The block echoes the label first and repeats the brief token:

```json
{"label": "check:docs-setup", "brief": "3f9a1c07", "status": "done", "verdict": "fail",
 "examined": [{"path": "docs/setup.md", "how": "full", "receipt": "Run `tool.sh setup --jobs 4`."}],
 "checklist": [{"n": 1, "verdict": "fail", "span": "docs/setup.md#Install"}],
 "findings": [{"claim": "The page documents a flag the command lacks.", "severity": "major",
   "quote": "--jobs 4", "anchor": "docs/setup.md#Install"}],
 "forks": [], "beyond_brief": [], "incidents": [], "own_authority": [],
 "alternatives": [], "brief_corrections": [], "dropped_suspicions": [], "notes": ""}
```

`status` is `done` or `inability`, and `verdict` and each checklist `verdict` take `pass` or `fail`. An inability is a helper's own report that it cannot do its item. Each `examined` entry claims a reading of `full`, `searched`, or `unreachable` with one verbatim receipt line. A finding carries a claim, a severity from the ladder the run records at `init`, a quote, and an anchor. A fork carries its issue in one sentence, the verbatim passage with its anchor, two to four options each with a cost, and the helper's preferred end state verbatim. The other lists hold objects with a `text` field, plus an `anchor` where an entry points into the tree, and `alternatives` may be explicitly empty. Extra keys pass through with the return.

A helper sends its return in one of two ways, depending on whether it may write files. A helper whose brief grants file writes writes `returns/<label>.md` as its last act, and its final message is only `END <label>`. A helper whose read-only lever removes file writes, or whose brief forbids them, ends with the return block and its END line as its final message. It never writes its return through a shell. The orchestrator pipes that message verbatim into `accept --stdin <label>`, or pipes a host log file that holds it. A file-writing helper's first act creates `returns/<label>.start`. Two rows ran at once when their marker-to-return intervals overlap, and a read-only wave leaves its concurrency unobserved.

`accept` rejects a return, from a file and from standard input alike, in each of these cases:

- The END line is missing.
- The block count is not exactly one.
- The echoed label disagrees with the file name or the `--stdin` label.
- The token disagrees with the roster.
- A required key is missing.
- A value falls outside its allowed set.
- A value is a placeholder.
- A receipt line is missing from the input version its row recorded.
- A passing checklist line cites no span.
- A list falls short of the obligations recorded for its row.

A placeholder is an empty or whitespace-only required text, an ellipsis, a lone angle-bracketed slot such as `<path>`, or a to-do marker such as TODO or TBD. The first rejection sets the row to violation and prints the errors for one re-ask, and the second sets it to failed. An inability status completes the row with no retry. A free-text return waits for `--classify`, because recognizing host boilerplate is a per-harness judgement. A return far smaller than its siblings raises a warning. Joins read identifiers only, and they stop when one is missing.

`close` exits 0 only when all of these hold:

1. Every row is terminal: accepted, inability, failed, unreturned, or dropped by a named narrowing, rows that `rows` created at runtime included.
2. Every record has a disposition.
3. Every changed path, drafts under `outbound/` included, has an accepted check from another row, a covering gate, or an unverified disposition.
4. Every change is attributed.
5. The tree guard is clean, or each change it found has a disposition.
6. Every fork is surfaced or listed as the orchestrator's own decision, and every user gate is answered.
7. `report.md` carries the current tally block.
8. Every accepted, inability, or failed row records its source as `file`, `relayed`, or `log`.
9. Every checker sits at or above its producer's recorded depth, or carries a flag.

### Portability and failure

- **Git reads only.** The ledger only reads git. Every git call passes `--no-optional-locks`, because a plain `git status` refreshes and writes the index. Status reads pass `--porcelain -z --untracked-files=all`, and diff reads pass `--no-ext-diff --no-textconv --no-color`. No call writes a ref, the index, a tree, a commit, an object, or the working tree, and `stash list` is the only form of `stash` the ledger runs.
- **Paths and text.** Every path is normalized to its realpath relative to the repository root before any join. Slugs are case-folded, text is read as UTF-8 with replacement, and a NUL byte marks a binary file. The walk over the tree follows no symlink inside it and skips submodules. Where the target is not a repository, a hashed walk stands in, recorded as a narrowing.
- **Fail closed and measure.** The ledger refuses rather than guesses. A missing sentinel, an unreadable block, and a counter whose positive control failed each refuse with a non-zero exit and a message naming what to fix. An internal error exits non-zero naming the failed step, so the orchestrator can record it and continue by hand. The measured diff decides which files changed, whatever a writer reported.
- **Concurrency and time.** An advisory lock with atomic replace guards the ledger's own files. Timestamps are UTC, and bounds count from the dispatch time. Concurrency comes from filesystem times, never from a helper's claim.
- **Interpreter and invocation.** The ledger checks its interpreter at start and exits with an actionable error below 3.9. It uses no syntax newer than 3.9, so an older interpreter can still parse it and run that check first. It is one file, run as `python3 -B` on its absolute path with no wrapper, and `-B` writes no bytecode.
- **Text the static greps scan.** `run.sh` greps the whole skill directory, so the ledger's code, comments, and strings must pass every one of those greps. Because the greps ignore case, no identifier may end in `task(` or `bash(` in any case. No name may carry a product token, such as a database cursor named `cursor`. The code avoids the `$VAR$` placeholder shape, which `make deploy` can replace in deployed copies.

### Tests, grader, lint scope, and docs

- **Static contract.** In `tests/agent_spinner/script_tests/run.sh`, replace the check "the skill bundles no runtime scripts" with new checks. They check that `scripts/` holds exactly `run_ledger.py`, that it imports only standard-library modules, that it answers `--help` under the oldest python3 on the machine, and that its source holds no state-changing git subcommand. A comment beside them names the change superseded behaviour under the owner's decision to bundle the ledger. Both class names, superseded behaviour and grader fix, come from TESTING.md's Test Integrity rule. Rewrite the header comment that says the skill ships no bundled scripts.
- **Ledger tests.** Add `tests/agent_spinner/script_tests/ledger_run.sh`, written to the bash 3.2 floor `lint-sh` enforces, staging each scenario under `script_tests/scratch/`. It finds every python3 the machine offers, on `PATH` and the operating system's own. It runs each scenario under the oldest and the newest, and prints both versions. When only one exists, it runs once and says so. `run_all.sh` drives it beside `run.sh` with an aggregated exit code, the way `tests/task/run_all.sh` drives its two runners.
- **Grader.** In `grade.sh`, the inline_floor and phase_plan_announcement cases test the announcement against `PHASE_PLAN`. Replace `PHASE_PLAN` in those two cases with an assertion that the announcement states two to four named phases, written to TESTING.md's test design principles. A comment names it a grader fix, because the pattern asserted surface form rather than the property both evals state.
- **Lint scope.** Add `-name .agent_spinner -prune -o` to `EXCLUDE`. Rewrite the comment above it so it says this prune mirrors the run directory's own `.gitignore`. That file sets the git side wherever a run sits, so lint scope still matches git scope and `tests/.gitignore` stays unchanged.
- **Harness docs.** Rewrite in place each agent_spinner line that `grep -rniE 'prose-only|no bundled scripts|bundles no (runtime )?scripts|ships no bundled' tests/agent_spinner tests/README.md tests/CLAUDE.md` finds, so it names the bundled ledger and its tests. Leave other skills' lines as they are. Update the layout tree in `tests/agent_spinner/README.md`, and the static-contract section of `tests/agent_spinner/RUNBOOK.md`, which says `run_all.sh` drives one entrypoint. `tests/AGENTS.md` keeps no inventory row of its own, so it needs no change.
- **Wiki.** Through the wiki skill family, update `wiki/concepts/agent-delegated-automation.md` in two places. One is where its section headed "The general rule lives in a skill, the instances keep their own runs" lists what ships with the skill. The other is where its "Derived from" list names the skill and its `references/`. Both places name the run ledger and describe it as a standard-library program that keeps a run's records and launches no helper.

**Out of scope:**

- The command reference in `references/run-protocol.md`, the `SKILL.md` blocks that cite the ledger, and the ledger evals, the behavioural evals that prove the skill's use of the ledger, which [ai-dev_agent-spinner-ledger-doctrine](ai-dev_agent-spinner-ledger-doctrine.md) owns.
- The `<role>` sentence naming `scripts/` and the concept page's one-way routing paragraph, which [ai-dev_agent-spinner-routing](ai-dev_agent-spinner-routing.md) owns.
- The markers check over the ledger's own rows, the checklist-to-acceptance lint, decision packets rendered from the ledger, and the helper-log audit, which [ai-dev_agent-spinner-ledger-phase-2](ai-dev_agent-spinner-ledger-phase-2.md) owns.
- Launching any helper, which the orchestrator does through the host's own sub-agent surface.
- A `--run-dir` option, since one working root holds one open run and `init` names `attach` instead.

## Acceptance

- `python3 -B` on the ledger's absolute path with `--help` lists exactly the verbs of the frozen set, each with its own `--help`, and an unknown verb exits non-zero.
- `bash tests/agent_spinner/run_all.sh` exits 0 under the stock bash 3.2 and runs the static contract and `ledger_run.sh`. `ledger_run.sh` prints the oldest and newest python3 versions it used and passes every scenario below under both.
- Slugs: `init` refuses a blank, a duplicate, and a case-colliding slug, and a label two units share. While a run is open, it refuses with a message naming `attach`.
- `init --probe`: naming the cheapest route and two registered roles, it creates the run directory, renders three probe briefs under `briefs/`, and opens no run, so a following `init` opens one. Each capability an accepted probe row records reads established, assumed absent, or unverified. A probe row whose write attempt left its file inside the run directory records the read-only lever as not enforced. An otherwise identical row with no file left records it as enforced. A probe row accepted with `--observed-model` and `--observed-effort` records model and depth as observed, and one accepted without them records both as unobserved.
- `brief` lint: a shared block edited between two briefs of one phase makes the second `brief` refuse. A brief that both forbids and permits one path is refused, and so is one that both forbids and permits one command. Each refusal exits non-zero and writes no brief file. A checker brief holding a steering word renders with a warning.
- `dispatch`: after `stop` creates `STOP`, `dispatch` refuses, and it dispatches again once the file is removed. With W written rows unchecked, W being the wave size `run.json` records, it refuses another writer row and still dispatches a check row. With a user gate open for a writer row, it refuses that row. It refuses a third attempt on one row, a second repair of the same path, and a second re-check of the same repaired item. Each refusal exits non-zero and leaves the row undispatched.
- Rejection: each rejection rule has a scenario that `accept` rejects. The first rejection leaves the row in violation and the second in failed. An inability return completes its row with no retry. A schema-valid plan holding one placeholder task against five target paths is rejected.
- Joins: two returns arriving in reverse order are joined only by echoed label and brief token.
- `diff`: a return claiming no change for a file that differs from the baseline still gets a check row, and an orchestrator write is attributed to the orchestrator. A helper write outside its brief's target paths gets a check row that keeps `close` refusing while it is open. An untracked file, a date-only change, a stash change, a HEAD move, and new ignored residue are each caught.
- Approved edits: a regeneration carrying one extra hunk is reported with the hunk that maps to no approved-edit id.
- Counters: a counter whose pattern misses its own known positive, such as an alternation that a zsh quoting slip turned literal, fails closed instead of reporting zero.
- `gate --expect`: `exit0` records a silent pass as silent, `nonempty` fails on empty output, and `count` refuses a counter whose positive control failed. The baseline difference is reported, and each command's resolved executable path is recorded. An unresolved executable records the gate as unavailable and names the narrowing.
- `close`: each close condition refuses on its own staged gap with exit 3 and the open item named, including condition 1 over rows `rows` created at runtime and a row with no recorded source. The tally byte check fails on an altered report, a checker recorded below its producer's depth is flagged, and `close --stopped` lists modified, untouched, and unknown paths.
- Repository safety: every verb leaves the tree hash outside `.agent_spinner/`, the index file's bytes, and the output of `git for-each-ref` and `git count-objects -v` unchanged, and writes no bytecode.
- `accept --stdin` checks the label echo, the brief token, and the sentinel. It records a source of `relayed`, or `log` when a host log file is piped, and it applies the same rejections as a file return.
- `attach` reports the open run and its pending returns, and it reports a HEAD that moved since the baseline.
- `rows` from records, from the repair list, and from gaps makes one row per source record with its slug from the record id, refuses a duplicate, and records the source phase.
- `show` prints one row's records in full. `search` finds a marker planted in the run directory that an ignore-honouring search misses, with its positive control passing.
- Gate scope: `init` plants one known positive per file type, shown with a markdown gate and a shell gate. The path filter drops run-directory findings for a gate that reported its plant and says so. An auto-fix gate is refused while run state exists.
- Hostile git settings: under `-c status.showUntrackedFiles=no`, an external diff driver, a textconv driver, and forced color, with hidden untracked files and from a symlinked root, status and diff reads stay correct and every path is normalized relative to the repository root.
- Recorded versions: a receipt matching the row's recorded snapshot is accepted after the live file changed. A withheld text handed to `brief` leaves only its hash on the blind row, which `accept` later checks against that text's recorded version.
- Recall tags: a confirmation is tagged recall-confirmed when the checker's brief relayed the record, and independently surfaced otherwise. The tally block splits the two, and `close` flags "independent" on a recall-confirmed row.
- Start markers: overlapping and serial intervals are read correctly from the filesystem times of `returns/<label>.start` and the return file.
- Version floor: with the version it reads stubbed below 3.9, the ledger exits non-zero with an error naming the floor and the running version.
- `run.sh` holds no check asserting that `scripts/` is absent. Each replacement check passes on the tree and fails on a scratch copy holding one violation: an extra file in `scripts/`, a third-party import, syntax the oldest python3 rejects, or a state-changing git call.
- Every existing grep in `run.sh` passes with `scripts/run_ledger.py` in the tree.
- A comment beside each edited check names its class under TESTING.md's Test Integrity rule with its evidence: the scripts check as superseded behaviour, and the phase-count assertion as a grader fix.
- The phase-count assertion passes on staged announcements naming two and four phases and fails on ones naming a single phase and five phases. inline_floor and phase_plan_announcement pass under TESTING.md's vendor rule, where re-grading a captured run counts under TESTING.md's re-run economy.
- `EXCLUDE` carries the `.agent_spinner` prune, and the comment above it names the pairing. A markdown file with a lint defect, staged under a repository-root `.agent_spinner/` whose `.gitignore` holds `*`, appears neither in `make lint-md`'s file list nor in `git status`. `tests/.gitignore` is unchanged.
- The harness-docs grep finds no agent_spinner line calling the skill prose-only or scriptless, other skills' lines are unchanged, and the README layout tree and the RUNBOOK name `ledger_run.sh`.
- The concept page's skill section and its "Derived from" entry name `scripts/run_ledger.py`, written through the wiki skill family.
- Before commit, a manual read of every changed shipped file and of this task's own diff finds no session, company, or project name, and no denylist is committed.
