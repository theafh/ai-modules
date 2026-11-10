---
name: agent_spinner
description: >
  Run helper agents from an orchestrating agent under one quality contract,
  whatever the host offers. Establishes the capability tier, declares a phase
  plan, picks an orchestration shape and width, contains each helper to one
  path, checks work refute-by-default, and merges cited findings into one
  verdict-first report. Every guarantee holds at the inline floor. Use when
  deciding how to run helper agents, sub-agents, or subagents: sizing a fan-out
  over files, spawning parallel helpers, splitting a review into lenses,
  running a judge or verifier pass, cross-checking agents' work, containing
  concurrent writers, aggregating helper reports, or recovering from a helper
  that failed, hung, or returned nothing. Use it when a multi-agent run needs a
  plan. Route a task-backlog request to task_* and a wiki request to wiki_fix,
  unless the user names agent_spinner; those families keep their own contracts.
  Per-harness facts stay with harness_portability.
version: 1.0.9
author: Andreas F. Hoffmann
license: MIT
---

# agent_spinner

<agent_spinner_skill>

<role>
agent_spinner is the orchestration doctrine an agent follows when it runs helper agents, whatever delegation the host offers. `scripts/` holds the ledger program, and the run's files live under `.agent_spinner/` in the working root. The skill owns no artifact class and writes no domain state, and every guarantee holds at the inline floor.
</role>

<start_here>
Build every path to `scripts/` and `references/` from the directory of the loaded SKILL.md, and invoke the ledger by that absolute path. On a missing-file error, re-resolve the path once before treating the ledger as unavailable. The command is `python3 -B <skill dir>/scripts/run_ledger.py <verb>`. Then, in order:

1. Run the ledger's `status`. Where it reports an open run, run `attach` and continue that run from its status.
2. Match the ask's shape, then its recipe, per `<selector>`, and read a matched recipe in full. A job a governing skill owns follows `<invocation_boundary>`, and an ask answered inline stops here.
3. Open the run per P1, which governs the probe, the orient rows, the inventory validation, the pre-dispatch gates, the pilot, the written plan, and its announcement.
</start_here>

<invocation_boundary>
A request naming the task backlog or the wiki without naming this skill goes to that family (`task_*`, `wiki_fix`); a per-harness question goes to `harness_portability`. A run a named skill governs keeps that contract's loop bounds, failure policy, verification standard, aggregation rule, and stop-and-ask boundary.

When the user names this skill on a family-owned job, the family's writer stays the only writer. Run the looks at your level: one read-only finder per ledger unit before the writer, and `<paired_refute_check>`'s post-write check on every changed file. Where that contract stops and asks for a host with no spawn surface, honour it and run no look inline. Every repair a look raises returns to the family writer as a scope the user explicitly approves; only the user's explicit gate answer is that approval, not the request, a goal objective, your own authority, a plan confirmation or mode switch. Write no family-owned artifact yourself, encode no multi-helper shape into a brief, and relay its report per that contract.
</invocation_boundary>

<capability_probe>
Establish callability, never infer it. A role definition on disk is evidence that the file deployed, not evidence that it can be called: definition-present-and-uncallable is a real state, so a registration check reporting a definition as available settles deployment alone. Establish callability through the host's own spawnable-role surface, and where the host advertises none, record the delegation surface as absent however many definitions are present.

Probe four capabilities: a delegation surface, a host-enforced read-only lever, a depth or effort control, and whether two helpers run at once. Resolve a capability that resists establishment to absent, and open the run by naming which capabilities you established and which you assumed away.
</capability_probe>

<degradation>
Order the tiers as one ladder and state the tier reached in the run's opening sentence.

1. **Inline floor**: a sequence of separately prompted passes performed inline in one context, each opening on its own brief and closing on its own return contract.
2. **Spawned roles**: each pass runs in its own context.
3. **Enforced read-only**: the host, rather than the prompt alone, holds a reading pass to reads.
4. **Depth pin**: the adversarial pass runs at a fixed depth.
5. **Concurrent fan-out**: independent helpers run at once.

Write every guarantee to hold at the floor, so no step depends on a fresh context, an isolated tool set, or a process boundary. Coverage is therefore counted in independent looks rather than in simultaneity, and the run claims no wall-clock benefit from fan-out.

The inline floor is the floor for a run the orchestrator owns outright. Where a governing skill states its own stop-and-ask boundary for a host with no spawn surface, honour that boundary, offer that skill's manual routes, and perform no helper role inline, as `<invocation_boundary>` already establishes.
</degradation>

<selector>
Match weight first.

- An enumerated imperative over many artifacts: per-artifact fan-out.
- One text needing several angles, not different kinds of source: a lens panel.
- A produced artifact needing an adversarial read: a paired refute-by-default check.
- A closed comparison among candidates: a judge panel.
- A finished body needing a what-is-missing read: a completeness critic.
- A tree of writes: a single-writer validator after writers.

A read-only diagnostic or single judgement question is answered inline from your own reads before any helper is spent, takes no recipe, naming a fuller shape's checks. An ask no single row covers, or one combining rows, gets the smallest shape that covers it, named as the smallest covering one, answered visibly rather than folded into a nearby row, and takes no recipe. A shape match matches the recipe table, whose matched recipe is the procedure; with no recipe it runs from the body. Name what matched, or nothing, in the opening. Read `references/variants.md` for isolation and unreduced draws.

| Ask | Recipe in `references/recipes/` |
| --- | --- |

</selector>

<shapes>
The library. Each shape states its trigger condition, its width rule, its prompt skeleton, and its return contract.

<per_artifact_fan_out>
**Trigger** an enumerated imperative over many artifacts, each judged on its own. **Width** one helper per file path on the list written out before dispatch. **Prompt skeleton** the invariant preamble, the one target path, that artifact's situation and target state, the negative list, the no-further-delegation clause, and the return contract. **Return** this artifact's outcome keyed by its stable identifier, the findings raised against it, and an explicit statement of what the helper examined and cleared.
</per_artifact_fan_out>

<lens_panel>
**Trigger** one corpus that needs several angles rather than several artifacts. **Width** three to five named lenses over the identical corpus. **Prompt skeleton** the preamble, this lens's name and the question it asks, the corpus pointer, the note that siblings cover the other angles so depth beats breadth, and the return contract. **Return** findings under this lens only, each carrying its verdict, confidence, verbatim quote, anchor, and severity, plus what this lens examined and cleared.
</lens_panel>

<paired_refute_check>
**Trigger** a produced artifact whose correctness the run is about to rest on. **Width** exactly one checker per produced artifact. **Prompt skeleton** the preamble, the producer's report verbatim, the artifact pointer, the stated opening position that the work is incomplete or wrong, the closed numbered checklist that concedes it, and the read-only operations to use. **Return** a verdict per checklist item with its citing span, the findings, and the narrowed wording where a claim was overstated rather than wrong.
</paired_refute_check>

<judge_panel>
**Trigger** a closed comparison among candidates that already exist. **Width** one judge per named criterion, with the candidate set held identical across judges. **Prompt skeleton** the preamble, the full candidate set, this judge's single criterion and its scale, and the instruction to score every candidate on that criterion alone. **Return** a score and a one-clause rationale per candidate under this criterion, with the quote that earned each score.
</judge_panel>

<completeness_critic>
**Trigger** a finished body that needs a what-is-missing read rather than a what-is-wrong read. **Width** one critic per body, given the body and the brief it answers. **Prompt skeleton** the preamble, the brief, the finished body, and the instruction to name what the brief requires that the body leaves out. **Return** the missing items with the brief's own words for each, the items confirmed present with their anchors, and an empty list where nothing is missing.
</completeness_critic>

<single_writer_validator>
**Trigger** a tree of writes that share a link graph or an index. **Width** exactly one, running alone after every writer has returned. **Prompt skeleton** the preamble, the roster of what was written, the invariants the tree holds, and the instruction to read the tree as it now stands. **Return** the invariants that hold, the ones broken with the path and anchor that break them, and the repairs proposed rather than applied.
</single_writer_validator>
</shapes>

<width>
Derive breadth from the ledger: one row per enumerated unit (a file, source, page, or issue-and-stance pair) written before dispatch, and one helper per row, never a round number and never a merge of rows taken to save calls. Rows for a later phase come from accepted records: `rows` creates one per finding, repair, or gap unit, so a finding-sized phase keeps its width equal to its rows. Replicate one identical prompt only for a single indivisible factual or arithmetic claim, stating the count first. A declared shape binds, and a mid-run switch is a ledger event naming the checks it drops, reported as a narrowing and put to the user when it removes a check.
</width>

<phase_plan>
Declare the run before the first helper. Plan two to four named phases, each a single verb plus one clause saying what one helper does and over what unit; a phase needing more than one clause is two phases. State the sequence, the item count, the per-helper wall-clock bound, and the items deliberately excluded with a reason each. Announce each phase boundary as it is crossed. Give the bound a number at every tier, the inline floor included, where it bounds one pass: a pass that loops or stalls is what the bound stops the orchestrator waiting on, and `<helper_failure>` reads an item as unreturned against exactly this number.

Label every helper `role:item` from a stable per-item slug rather than a property several items share, because a repeated label leaves a dead helper unattributable.
</phase_plan>

<run_economy>
Close every run with its yield: helpers dispatched against the decisions or edits they produced, the estimate beside the actual count, and per checking stage what it surfaced that the gates had not. Say plainly when a run or a stage cost more than it returned.
</run_economy>

<coverage_tradeoff>
Name every narrowing out loud, printed from the ledger. Every planned read, check, and step a governing skill mandates is a row before dispatch, and a row left unrun is dropped by a named narrowing through `dispose`, with its reason. Count a path as read only where tool evidence shows a full read. When the run answers inline, verifies a subset, or drops a phase, state in the same reply which checks go unrun and what would surface them. Proceed on the user's word where the narrowing removes a check the fuller shape would make. A repository's `CHARTER.md` coverage invariant is the authority this rule applies to the skill's own economy rules.
</coverage_tradeoff>

<containment>
One path per helper, one writer per tree. Each write helper's prompt names its single target path and carries an explicit negative list of the neighbouring artifact classes it leaves untouched. No helper receives two paths, and no two helpers share one. The `single_writer_validator` shape runs alone after the writers.

Where the target repository carries a `CHARTER.md`, validate each edit against its boundaries before writing. On a conflict, write nothing, leave the file byte-for-byte unchanged, and report the conflict.
</containment>

<delegation_depth>
One level per run. State in every helper prompt that the helper performs its own item and delegates no part of it, and that work it cannot complete comes back as an out-of-scope finding. An item that genuinely needs its own fan-out returns as a finding and gets sized in the next run, where the user also gets a decision point.

Recognise a nested item while writing the list, not after dispatching it. An item whose own work is itself a list the orchestrator has not enumerated is nested: one artifact generated from many sources, one entry standing in for a manifest, or one page whose correct state is decided per section by somebody else. Return it with the size it implies rather than counting it as one more item, because a helper handed it either edits the generated surface the sources will overwrite or fans out on its own.
</delegation_depth>

<prompt_assembly>
Assemble each helper prompt from three parts. An **invariant preamble** holds the hard rules, the shared vocabulary, the severity ladder, and the facts already settled that nobody re-derives. A **hand-written per-item brief** names that item's situation and target state. A **kind note**, drawn from a small table, handles items whose class needs different treatment. The preamble goes unchanged into checking passes as well as producing ones.

Write every role contract as text the pass reads inside its own turn: open with the pass's first concrete action, state each prohibition as something the pass does, and restate a load-bearing prohibition at the point of use. A role body can arrive inside the user turn with no authority over the surrounding conversation, so a contract that relies on standing precedence reaches only some hosts while an action-shaped one reaches all of them.
</prompt_assembly>

<checking>
Refute by default, cite to clear. The checker receives the producer's report verbatim, opens from the stated position that the work is incomplete or wrong, and concedes only after running a closed numbered checklist. Name the cost that sets that default in the same sentence, so the helper weighs it rather than obeys it.

The checker changes nothing and is told which read-only operations to use. Where a host's read-only mode gates commands behind approval rather than denying them, the checking pass stays clear of shell use entirely.

Each finding carries a verdict from a small closed set, a confidence, a verbatim quote, a path with a heading or symbol anchor, and a severity from a defined ladder. A clean verdict cites the span that settled it, so a first-pass all-clear with no citation routes back for re-checking rather than passing. The checker may narrow an overstated claim instead of killing it, and the narrowed wording propagates. A helper acting on findings re-derives each one first and reports a disproved finding as refuted. Every reviewing pass reports what it examined and cleared, and an empty finding list is a valid and expected outcome.
</checking>

<confirmation_provenance>
Record how a finding survived. A finding the checking pass was shown and did not refute is **recall-confirmed** and says so in the report. A finding a pass surfaced without having been shown it is **independently surfaced**. Recognising a stated issue is easier and steadier than generating it, so a recall-confirmed finding carries less weight, and a decision resting only on recall-confirmed findings says so.
</confirmation_provenance>

<helper_failure>
Classify a non-result before acting on it, and record the class on its ledger row.

- A **deliberate self-reported inability** is a completed result: record its reason, spend no retry, and route it to the user.
- A **spawn glitch** (a near-instant return with no tool use and only host boilerplate), a **spawn failure or mid-run death**, and a **contract violation**, meaning a return `accept` rejects, each earn one identical-prompt re-invocation.
- A helper the user aborted, or one past its bound that may have written, has its paths settled from the diff before anything is re-dispatched over them.

A helper that may write files writes its return file, and its final message is its END line. A helper whose read-only lever or brief withholds file writes ends with its return block and END line as its final message, and never writes through a shell. Relay that message verbatim to `accept --stdin`, which records the return as relayed.

Completion is an accepted return. A notice, a quiet interval, or a tree predicate is only a hint to run `status`. Wait inside the turn in bounded `accept --wait` polls until every row of the wave is terminal or past its bound. While a foreground batch blocks you, record each bound and mark a row that returned late as over its bound. A row past its bound is unreturned, earns the same single re-invocation, and then stays unreturned, distinct from a helper that found nothing. When a re-invocation fails again, mark the item failed and report it, and take a degraded path such as an inline redo only after the user chooses it. Guard every step against a dead or rejected upstream.
</helper_failure>

<remediation>
One round, never loop until pass. Only the items that failed verification enter repair, they enter once, and the report marks the repaired output as unverified rather than implying end-to-end coverage. Repeating a stochastic check until it passes selects its most lenient draw rather than verifying. Guard a follow-up fan-out on the count of items that need it, so a pass over an empty list dispatches nothing and says so.
</remediation>

<run_state>
Keep the run in `.agent_spinner/` through the ledger, and query it only through the verbs `references/run-protocol.md` documents. `init` records the baseline: the commit, in-scope hashes with untracked files, and each named gate's output. Change rows only through the ledger. Derive the check set, the changed and untouched lists, and attribution from the net diff against the baseline, never from a helper's changed flag. State tool results as baseline-to-final deltas. Any turn that finds an open run, whether a completion notice, a user message, or a fresh session, runs `status`, accepts every pending return, and continues the run until a user gate opens or `close` exits 0. End a turn with the closing report after a clean `close`, or with the interim report while helpers are out or a gate is open. Where the session offers a goal tool, arm one goal per run, with the run directory in its objective and `close` exiting 0 as its completion condition. Where it offers none, re-entry through `status` and `attach` carries the run. After a stop, pause, abort, or resume, mark in-flight rows unknown, and settle them by reading the files and the diff before re-dispatching. Report the modified, untouched, and unknown rows, and reuse a return only when its brief hash matches. On a stop or pause request, run `stop` at once. Its STOP file halts new dispatch and lets running helpers finish. Before the report, run `close`, which prints the tally block the report carries verbatim and exits non-zero while any row, record, fork, or written path is open. The ledger cannot force you to call `close`; its close conditions bind when you run `close`, so a report on a run with no clean `close` says so in its opening sentence. Where the host cannot run python3, or asks approval for each command, keep the same files by hand, perform the same checks against the roster, and report each check as unenforced.
</run_state>

<aggregation>
Merge cited findings, never count agreement. The ledger imports every return in full. Read through `show`, in full, every record that needs judgement: forks, decide-class findings, alternatives, incidents, and own-authority calls. A beyond-brief find travels as a flag, not a record type: `dispose --flag LABEL --reason TEXT` records it and `show` reads it; a flag has no `id`, so its `reason` is its whole record and needs no separate disposition. When two returns disagree, check each side; if they conflict, surface it as a user gate with `dispose --open-gate ID --question TEXT`, never a finding. Dispose of the rest by id pattern; never read a return through slices or keyword searches. Give each record one disposition: applied, refuted with its reason, surfaced, or deferred with a durable pointer. Two helpers raising the same item is shared priors: union and check. Join by the echoed identifier; stop when one is missing. Every number the report states comes from the ledger. Cap any payload pasted downstream at a stated size, tell that pass its material may be cut and load-bearing detail gets re-read from the source, and list every trimmed identifier.
</aggregation>

<reporting>
Put the verdict first, and keep three things apart. The opening sentence gives the answer, the tier, helpers dispatched against returned, and whether `close` exited 0. The body separates what the run established, what a helper found beyond its brief, and what a helper or you decided on your own authority for the user to review, with `none` under an empty part, and names the artifact each finding concerns. A sentence in a report, reply, or log entry that asserts verification, independence, completion, or coverage cites its ledger row or check output and says whether it was measured, re-derived, or taken on a helper's word. Read repository state from version control at report time. Check the verdict's single claim against the artifact, and report a resisted re-derivation as the helpers' finding. Re-read an earlier deliverable before conceding a gap, and fix a conceded false premise in every open draft. Helper return shapes stay internal.
</reporting>

<judgement>
Route the real forks to the user. Removing most of a body, deleting a load-bearing section, picking one side of a real fork, resolving a contradiction, or touching an artifact already marked complete are surfaced rather than settled, at every tier, and no helper writes a field a named gate owns. A run whose ask was which work to do changes nothing, states the no-edit rule in every helper prompt, and closes by asking for the go-ahead.
</judgement>

</agent_spinner_skill>
