# Run protocol

This reference is the procedure behind `agent_spinner`'s run-state blocks. It
covers the capability tier table, the run directory, the ledger floor, the six
parts P1 to P6, and the ledger's command reference. The ledger program sits at
`<skill dir>/scripts/run_ledger.py`. Invoke it by that absolute path, built from
the skill directory, as `python3 -B <skill dir>/scripts/run_ledger.py <verb>`.

The checks this reference points at are C1 to C10 in `references/checks.md`.
Quote them by number; that file owns their text.

## Capability tier table

Key each row by the rung the run reached and by the delivery property the probe
recorded. **Batch delivery** means a batch of spawns returns together inside
the turn. **Notice delivery** means a spawn returns at once and completion
arrives later as a notice, with or without its result. `harness_portability`
records which host shows which property. Batch and notice delivery both spawn
through the host's own sub-agent surface, the only route a helper runs on.

| Rung and delivery | What the orchestrator does | Ledger calls |
| --- | --- | --- |
| Inline floor | Run each pass from its brief file to its return file before the next brief. Label every check recall-limited, because the one context has already seen what it checks. | `brief`, then `accept`; cross sessions at wave ends with `attach`. |
| Batch delivery | Send one wave per batch. For each helper row, write the brief and dispatch it with a one-line pointer prompt, then accept its return. Follow with `diff --add-checks` and the checker wave. The batch is the barrier, so the next step waits for the whole batch, and the gates close the wave. | `brief`, `dispatch`, `accept` or `accept --stdin`, then `diff --add-checks`. |
| Notice delivery | Dispatch in the background with `--helper-id`, and wait inside the turn in bounded `accept --wait` polls. A late notice re-runs `accept`, which changes nothing on an accepted row. Where the notice carries no result, send read-only helpers as a foreground batch. | `dispatch --helper-id`, `accept --wait`, `accept` again on a late notice. |

There is no headless-worker row. Helpers run only as sub-agents of the host the
orchestrator runs in. `references/degradation-examples.md` works one job at the
inline floor, batch delivery, and notice delivery rows.

## Run directory

The ledger keeps one open run per working root under `.agent_spinner/`. `init`
refuses while a run is open and names `attach`. The directory holds `run.json`,
`roster.tsv`, `ledger.jsonl`, the baseline copies and hashes, `briefs/`,
`returns/`, `snapshots/`, `diffs/`, `gates/`, `controls/`, `access/`, `kinds/`,
`items/`, and `history/`. Its own `.gitignore` hides it from git.

Every brief keeps its helper out of the directory, apart from the helper's own
brief, start marker, and return, and the inputs its brief names, snapshot
copies included. No brief lets a helper run the ledger. Query the directory only
through `status`, `show <label>`, and `search`, whose Python pattern search
carries its own positive control. Host search tools may skip the directory.

The gate-scope check works like this. At `init` the ledger plants a known
positive, a file carrying a known defect, and runs each named gate at the
baseline. It records whether the gate reported the planted file. For a gate
that sees the directory, `gate` drops findings under its path and says so on
the gate line. A gate the filter cannot handle is named as a narrowing, a check
the run drops or shrinks. `init` refuses to register an auto-fix gate while run
state exists. Every recipe's orient step, where the orchestrator reads the
governing documents, runs this check before dispatch.

## Ledger floor

The ledger needs Python 3.9 or newer and checks its version at start. Where the
host cannot run python3, or asks approval for each command, keep the same files
by hand and perform the same checks against the roster. If the ledger itself
errors, record the error as a run event, continue by hand, and name each check
left unenforced.

## P1, open the run

**Trigger.** Every new run, before its first item brief. An open run re-enters
through P4 instead.

Two reasons the body leaves out. A label comes from a stable per-item slug,
because a repeated label leaves a dead helper unattributable. A nested entry
returns as a finding, because a helper handed it edits a generated surface or
fans out on its own.

1. Probe the four capabilities by observation through `init --probe`, which
   renders the fixed probe brief and opens no run. Spawn that brief through the
   host's own sub-agent surface, once through the cheapest route it offers and
   once through each registered role the host lists.
2. Count the read-only lever, a host setting that blocks a helper's writes, as
   enforced only when the probe's write attempt inside the run directory left
   no file. Count model and depth as observed only where the host exposes the
   helper's settings, and otherwise state rigour as behaviour.
3. Establish concurrency from the first real wave, through the filesystem times
   of each file-writing helper's `returns/<label>.start` marker and its return
   file. Cap the wave size at the largest batch `harness_portability` records
   for the host until the run's waves show more.
4. Record the delivery property, whether a notice carries its result, whether
   the session offers a goal tool, and whether the host gives a later turn.
   Record each capability as established, assumed absent, or unverified.
5. Next, write orient rows for the governing documents and the requirement
   sources, each read in full. The governing documents are `CHARTER.md` in
   full, the procedure pages, and the owning skill of each touched artifact
   class.
6. Scout and validate the inventory: no blank or repeated entries, category
   counts that sum, and every exclusion counted with a reason.
7. Then run `init` over the validated inventory, orient rows included. It opens
   the run and records the baseline and each gate's gate-scope result. Every
   git call passes `--no-optional-locks`, status reads pass
   `--porcelain -z --untracked-files=all`, and diff reads pass
   `--no-ext-diff --no-textconv --no-color`.
8. Split the user's hypothesis into its readings.
9. Read the request for each pre-dispatch gate's answer, proceed on a stated
   answer, and quote it in the announcement. A pre-dispatch gate is a question
   for the user that the run settles before it sends helpers. On a host with no
   later turn, an unanswered gate stops the run before dispatch, with its
   decision packet and `close --stopped`. A run on such a host uses the inline
   floor or batch delivery only.
10. Pilot two or three items to price the per-item cost.
11. Put every unanswered gate to the user: forks, widening, and the
    verification scope with its estimate beside any size guideline the host or
    user states (checks.md C7).
12. Write the plan before any item brief. It holds two to four helper phases,
    each one verb plus one clause naming the earlier returns it reads.
    Scouting, calibration, deterministic gates, scripted merges, validation,
    and reporting are listed as orchestrator steps. The plan holds a model and
    an effort per role, recorded with `dispatch --model M --effort E`. Where the
    host exposes a model choice, a checker may run on a model other than its
    producer's, and the report names that benefit as unmeasured. It holds the
    wave size, the bound, and the exclusions. It also holds a context
    estimate against the host window `harness_portability` records, with a
    session boundary at the first wave end past half the window. Where the
    reference records no batch or window for the host, or omits the host, use a
    fallback figure: the figure the request states, otherwise the smallest
    figure the reference records for any host. Name that figure as unverified
    in the announcement.
13. Announce all of it.

**Checks.** The probe rows and `probe.json` show all four capabilities, each
established, assumed absent, or unverified. `run.json` records the delivery
property and the goal-tool answer. The roster holds an orient row per governing
document before any item row. `run.json` carries a baseline commit, the gate
records carry their gate-scope result, and the announcement names the tier, the
plan, and the fallback figure where one was used.

## P2, render every brief from files

The run directory keeps the inputs every brief is built from: `request.txt`
verbatim, `intent.md` with its hash, and a preamble with tiered settled facts
and an unverified-premises block (checks.md C10). Each settled fact carries its
evidence tier, and the unverified-premises block lists the claims nobody has
verified yet. The directory also keeps one access file per phase, one rules file
a producer and its checker share, kind notes for classes of item that need
different treatment, and item briefs.

`brief` renders each brief from those blocks and appends the closing block.
That block carries the role's return template, the return channel P3 assigns,
the END line, the no-delegation clause, the capabilities as facts, the bound,
and a brief token as the last line. The brief token is a short code the return
must repeat. A file-writing helper's closing block adds the start-marker
instruction and an END-line-only final message.

Relay upstream material, meaning earlier returns, by path with a read-in-full
instruction, or paste it below a stated cap listing the trimmed identifiers. A
relay refuses until its upstream row is accepted. The spawn prompt is one line
pointing at the brief file. Lint every brief for byte-identical shared blocks
within a phase, and for no path or command both forbidden and permitted. Keep
text a blind pass must not see out of the workspace until that pass returns,
with only its hash on the roster.

**Checks.** Every item row has a brief file before its dispatch. Shared blocks
hash identically within a phase. No brief lists a path or command under both
permits and forbids. Each brief ends with the return template, the END line, the
bound, and the token. A blind row's `input_versions` carries only the withheld
hash.

## P3, return files and the acceptance gate

A return holds optional prose, one fenced JSON block that echoes the label first
and repeats the brief token, and the line `END <label>`. A helper whose brief
grants writes writes `returns/<label>.md` as its last act. A helper whose lever
or brief withholds writes ends with the block and END line as its final message.
The orchestrator pipes that message verbatim into `accept --stdin <label>`, and
the report names every relayed return. The template puts the verdict first and
lists its fields as the shipped ledger requires them.

`accept` applies every rejection rule below. A rejected return gets one
identical-prompt re-invocation; a second rejection marks the row failed. A
helper that reports it cannot do its item returns status `inability`, which is
a completed result with no retry.

- Missing `END <label>` line.
- A block count other than exactly one.
- An unreadable JSON block, or one that is not an object.
- An echoed label that disagrees with the row.
- A missing or mismatched brief token.
- Any required key missing.
- A status outside `done` and `inability`.
- A verdict outside `pass` and `fail`.
- An examined entry that is not an object, a placeholder path, a `how` outside
  `full`, `searched`, and `unreachable`, or a placeholder receipt.
- An examined path with no recorded input version, or a receipt missing from
  that recorded version.
- An examined list that does not cover an obligation.
- A checklist entry that is not an object, a verdict outside `pass` and `fail`,
  a placeholder span, or a passing line with no span.
- A finding that is not an object, a placeholder claim, severity, quote, or
  anchor, or a severity outside the ladder.
- A fork that is not an object, a placeholder issue, fewer than two or more than
  four options, or a placeholder preferred end state.
- A blind row returning the withheld text it must not see.

Also use `accept --classify` for a free-text return, manifests for large
outputs, joins by identifier only, recall tagging from recorded relays, and
`accept --observed-model M --observed-effort E`.

**Checks.** Every accepted row has a source of `file`, `relayed`, or `log`. A
rejection is recorded as an `accept_reject` record and leaves the row at
`violation` or `failed`. A relayed row's source is `relayed` and the report
names it. `show <label>` prints the accepted records in full.

## P4, completion, waves, stop, and resume

Completion is an accepted return, and anything else is a hint to run `status`.
Before waiting on a predicate, such as a file appearing, confirm it can become
true. Poll with `accept --wait`, at most 90 seconds per call. Work in waves, the
batches of helpers sent together: writers first, then checkers and gates, with
pending checks ahead of queued writes. A phase sized by earlier returns gets its
rows from `rows` before dispatch. The verdict, each stamp hand-off (checks.md
C9), and the report wait for every checker row they rest on.

Create the stop file the moment a stop or pause request arrives. On a host with
no later turn, a stop file planted before a wave pauses the run the same way.
After a stop, abort, or resume, settle in-flight rows from the net diff before
re-dispatch. Re-entry from a completion notice, a user message, or a fresh
session runs `status`, then `attach`. A turn ends with the closing report or the
interim report. A reply claiming nothing is left while rows or gates are open is
a reporting error.

Where the session offers a goal tool, the continuation step arms one goal per
run, with the run directory in its objective and `close` exiting 0 as its
completion condition. Where the session offers none, re-entry through `status`
and `attach` carries the run.

**Checks.** `status` lists each open row with its deadline and each open gate.
`STOP` exists before the first post-stop dispatch, and `dispatch` refuses while
it exists. A resumed turn appends an `attach` record. A late notice accepted
again leaves the row's state unchanged.

## P5, keep shared state still

No pass runs a whole-tree version-control state command: stash, reset, clean,
commit, bulk staging, a branch switch, or a checkout or restore of other paths.
Every reading pass reads a snapshot, a file copy under `snapshots/` made by
`snapshot`, and a blind pass reads `snapshot --base`. The run writes no ref,
tree, commit, or object into the user's repository.

A reading brief names its files and reads each in full or searches it by
explicit path. It never searches a directory under the run directory. It
forbids scripts, network access, credentials, other helpers' transcripts, the
ledger, and any write beyond its return channel. The orchestrator holds its own
writes while a reader is out. Every pass is guarded by the baseline git reads,
and a change outside the write set stops the run.

**Checks.** `run.json` records the baseline commit and `diff` reports any
`<HEAD>` or `<stash>` change. Every reading row's brief names its files and
forbids the ledger and other helpers' transcripts. `snapshot` copies exist for
each reading row's inputs.

## P6, the findings ledger, decision packets, and the report

P6 holds the reading rule `<aggregation>` states, one disposition per record, a
decision packet per fork, and the report built from the tally block. Coverage
comes from tool evidence (checks.md C8), and verification and confirmations are
split by provenance (checks.md C10). The report lint flags an assertion word,
such as verified or complete, that carries no ledger citation. A report on a run
with no clean `close` says so in its opening sentence.

**Checks.** Every finding, incident, and alternative record has a disposition
record. Every fork is surfaced or decided. `report.md` carries the current tally
block verbatim. The opening sentence states whether `close` exited 0.

## Command reference

Every entry below is the shipped ledger's own behaviour. Where a description and
the program differ, the program governs.

### `init`

Open a run over an enumerated list. `init --probe` prepares probe briefs and
opens no run; it needs `--cheapest ROUTE` or one or more `--role ROUTE`.

- `--unit role:item` (repeatable): one roster row, labelled `role:item`.
- `--unit-path LABEL=PATH`: the row's target path.
- `--exclude LABEL:REASON`: a counted exclusion.
- `--gate NAME=COMMAND`: a gate run at the baseline for its gate-scope result.
- `--auto-fix-gate NAME`: refused; the ledger registers no auto-fix gate while
  run state exists.
- `--owned-target PATH:FAMILY:GATE`: a path whose field a named gate owns.
- `--counter NAME=PATTERN`: a counter whose positive control must match.
- `--bound SECONDS`: the per-helper bound, default 900.
- `--wave N`: the wave size, default 2.
- `--phase NAME`: the first phase, default `work`.
- `--request PATH`, `--intent PATH`: the verbatim request and the intent.
- `--severity NAME` (repeatable): the severity ladder.
- `--role ROUTE` (repeatable), `--cheapest ROUTE`: probe routes.
- `--probe`: prepare probe briefs only.

### `attach`

Re-enter an open run. It prints the run id, the state, whether HEAD moved, the
tree guard, and each pending return, and appends an `attach` record.

### `brief`

Write one helper's instructions and record its brief hash and token.

- `label` (positional): the roster row.
- `--phase NAME`: the phase this brief belongs to.
- `--body TEXT`, `--body-file PATH`: the per-item brief.
- `--shared-file PATH`: the shared block, default the run preamble.
- `--relay LABEL` (repeatable): an accepted upstream return to relay.
- `--withheld`: read withheld text from standard input and record only its hash.
- `--obligation PATH` (repeatable): a path the return's examined list must cover.
- `--permit-path PATH`, `--forbid-path PATH`, `--permit-command CMD`,
  `--forbid-command CMD` (each repeatable): the permission block.
- `--checker`: mark the brief as a checking pass and warn on steering words.
- `--kind KIND`: the row's kind.
- `--depth N`: the row's depth.
- `--target PATH`: the row's target path.
- `--stamp-owner NAME`: the record id this row's stamp belongs to.

### `dispatch`

Record that a helper was sent.

- `label` (positional): the roster row.
- `--helper-id ID`: the host's identifier for the helper.
- `--model M`, `--effort E`: the requested model and effort.
- `--route ROUTE`: the spawn route.

### `accept`

Take in a helper's return.

- `label` (positional): the roster row.
- `--stdin [LABEL]`: read the verbatim final message or a piped host log from
  standard input; records the return as relayed.
- `--source relayed|log`: the source tag for a stdin return.
- `--log PATH`: read a host log file instead of stdin.
- `--observed-model M`, `--observed-effort E`: record the observed values.
- `--wait`: poll up to 90 seconds for dispatched rows to return.
- `--classify TEXT`: accept a free-text return with a classification.
- `--probe`: accept a probe return and record its capabilities.

### `rows`

Add rows for a later phase.

- `--phase NAME`: required.
- `--from-records PATTERN`: one row per matching finding, incident,
  own-authority, or confirmation record.
- `--from-repair-list`: one row per repair-list entry.
- `--from-gaps LABEL`: one row per gap record from that row.
- `--role ROLE`: the new rows' role, default `check`.

### `dispose`

Record what became of each record.

- `--id PATTERN`: the record ids to dispose.
- `--disposition applied|refuted|surfaced|deferred`: the disposition.
- `--tag TAG`, `--span SPAN`, `--packet PACKET`, `--pointer POINTER`: its detail.
- `--narrowing TEXT`, `--drops TEXT`: a named narrowing and the checks it drops.
- `--open-gate ID`, `--question TEXT`: open a user gate.
- `--gate ID`, `--answered TEXT`: answer a user gate.
- `--fork ID`, `--own-decision TEXT`: record an own-authority decision.
- `--flag LABEL`, `--reason TEXT`: flag a row.

### `diff`

Measure what changed against the baseline.

- `--add-checks`: add a `check:<slug>` row per changed path.
- `--approved-edits PATH`: map changed blocks to approved edits.
- `--count`: print each counter's known-positive count.
- `--counter NAME=PATTERN` (repeatable): register a counter.

### `gate`

Run a check command.

- `name` (positional): the gate's name.
- `--expect exit0|nonempty|count`: what makes the gate pass.
- `--on-baseline`: record the result as the baseline.

### `snapshot`

Make read copies.

- `label` (positional): the snapshot label.
- `paths...` (positional): the files to copy.
- `--base`: copy each path at the baseline commit instead of the working tree.

### `status`

Show where the run stands: run id, open or closed, the tally, each open row
with its deadline, each open gate, the repair list, the resume hashes, and the
start-to-return intervals.

### `show`

Print one row's records in full. Takes `label` (positional).

### `search`

Run a pattern search over the run directory. Takes `pattern` (positional). It
plants its own positive control and fails when the control does not match.

### `stop`

Create `STOP` so nothing new is dispatched.

### `close`

End the run. It prints the tally block and refuses with a non-zero exit while
any close condition holds:

1. A row is not terminal.
2. A finding, incident, or alternative record has no disposition.
3. A changed path has no accepted check, gate, or taken-on-word disposition.
4. A change is unattributed.
5. The tree guard sees an undisposed path, HEAD moved, or the stash changed.
6. A fork is neither surfaced nor decided, or a user gate is unanswered.
7. `report.md` does not carry the current tally block.
8. An accepted, inability, or failed row has no recorded source.
9. A checker sits below its producer with no flag naming it.

`close --stopped` also prints the modified, untouched, and unknown rows.

### Roster columns

`label`, `phase`, `role`, `item`, `path`, `kind`, `state`, `attempts`,
`brief_hash`, `input_versions`, `helper_id`, `spawn_route`, `model_req`,
`effort_req`, `model_obs`, `effort_obs`, `dispatched_at`, `start_marker_time`,
`returned_at`, `source`, `stamp_owner`.

The states are `pending`, `dispatched`, `violation`, `accepted`, `inability`,
`failed`, `unreturned`, `unknown`, and `dropped`.

### Return contract

A return is optional prose, exactly one fenced JSON block, and the line
`END <label>`. The block is an object with these keys: `label`, `brief`,
`status` (`done` or `inability`), `verdict` (`pass` or `fail`), `examined`,
`checklist`, `findings`, `forks`, `beyond_brief`, `incidents`, `own_authority`,
`alternatives`, `brief_corrections`, `dropped_suspicions`, `notes`.

- `examined` is a list of objects with `path`, `how` (`full`, `searched`, or
  `unreachable`), and `receipt`.
- `checklist` is a list of objects with `verdict` (`pass` or `fail`) and `span`.
- `findings` is a list of objects with `claim`, `severity` (on the ladder),
  `quote`, and `anchor`.
- `forks` is a list of objects with `issue`, two to four `options`, and
  `preferred`.

Channels are `file` (a helper that may write leaves `returns/<label>.md`),
`relayed` (a withheld helper's final message piped to `accept --stdin`), and
`log` (a host log read through `accept --log` or a piped log). A file-writing
helper writes a `returns/<label>.start` marker as its first act; the ledger
records its time.
