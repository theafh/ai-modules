---
name: agent_spinner
description: >
  Run helper agents from an orchestrating agent under one quality contract,
  whatever delegation the host offers. Establishes the capability tier, declares
  a phase plan, picks an orchestration shape and its width, contains each helper
  to one path, checks work refute-by-default, classifies helper non-results,
  keeps the dispatch roster on disk, and merges cited findings into one
  verdict-first report. Every guarantee holds at the inline floor, so a host
  exposing no spawn surface runs the same passes in one context and says so. Use
  when deciding how to run helper agents, sub-agents, or subagents for a job:
  sizing a fan-out over many files, spawning parallel helpers, splitting a
  review into lenses, running a judge or verifier pass, cross-checking one
  agent's work with another, sizing how many helpers to spend, containing
  concurrent writers, aggregating helper reports, or recovering from a helper
  that failed, hung, or returned nothing. Use it too when a multi-agent or
  parallel-agent run needs a plan before the first helper starts. Route a
  request naming the task backlog to the task_* family and a request naming the
  wiki to wiki_fix, which are worked instances of this shape that keep their
  own contracts. Per-harness facts stay with harness_portability.
version: 1.0.3
author: Andreas F. Hoffmann
license: MIT
---

# agent_spinner

<agent_spinner_skill>

<role>
agent_spinner is the orchestration doctrine an agent reads before it runs helper agents. It owns one question: given a job and whatever delegation the host offers, how do helpers spin off, stay contained, cross-check each other, fail, report, and get aggregated into one answer. It owns no artifact class and writes no domain state, so it stays advisory over any run that a domain skill already governs. Every guarantee below is written to hold at the inline floor, where the same passes run in one context, so the quality contract reads the same whether the host fans helpers out or not.
</role>

<when_to_activate>
Activate when the orchestration decision belongs to the orchestrator:

- "Fan this out across the files" / "run several agents on this" / "spawn parallel helpers for these items."
- "Split the review into lenses" / "have a second agent check the first one's work" / "add a verifier pass."
- "How many helpers should this take?" / "how do I keep two writers off the same file?"
- "One of the helpers came back empty" / "a helper hung" / "merge what the helpers reported."

Route a request naming the task backlog to the `task_*` family and a request naming the wiki to `wiki_fix`. Route every concrete per-harness question, meaning which delegation surface a target exposes and how a role registers on it, to `harness_portability`, which owns those facts under its own re-verification rule.
</when_to_activate>

<invocation_boundary>
A run already governed by a named skill keeps that skill's orchestration contract. Where that skill states its own loop bounds, helper-failure policy, verification standard, aggregation rule, or stop-and-ask boundary, this skill adds nothing to that run and overrides nothing in it. Read `agent_spinner` for a request about running helpers in general, or for a job no shipped family owns. The shipped families stay worked instances of this shape at different sizes: cite them for illustration, and leave authority over their runs with them.
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
Match orchestration weight to the ask before picking a mechanism.

- A read-only diagnostic, or a single judgement question, is answered inline from the orchestrator's own reads before any helper is spent, and the same reply names the checks that fuller shape would have run, per `<coverage_tradeoff>`.
- An enumerated imperative over many artifacts gets per-artifact fan-out.
- One corpus needing several angles gets a lens panel.
- A produced artifact needing an adversarial read gets a paired refute-by-default check.
- A closed comparison among candidates gets a judge panel.
- A finished body needing a what-is-missing read gets a completeness critic.
- A tree of writes gets a single-writer terminal validator after the writers.

Name the outcome of this match in the run's opening: say which listed shape the ask matched, or say it matched none. An ask matching none gets the smallest shape that covers it, named as the smallest covering choice, so a residual ask is answered visibly rather than folded into whichever row looks closest.
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
Derive breadth from the enumerated list. The helper count equals the length of a list the orchestrator wrote out before dispatch, never a round number and never a merge of items taken to save calls. Per-artifact fan-out takes one helper per file path. A lens panel takes three to five named lenses over the identical corpus, each told that siblings cover the other angles so depth beats breadth. Reserve replication of one identical prompt for a single indivisible factual or arithmetic claim. Test each entry as you write it: an entry whose own work is a list you have not enumerated is not one item, so return it per `<delegation_depth>` instead of counting it into the width.
</width>

<phase_plan>
Declare the run before the first helper. Plan two to four named phases, each a single verb plus one clause saying what one helper does and over what unit; a phase needing more than one clause is two phases. State the sequence, the item count, the per-helper wall-clock bound, and the items deliberately excluded with a reason each. Announce each phase boundary as it is crossed. Give the bound a number at every tier, the inline floor included, where it bounds one pass: a pass that loops or stalls is what the bound stops the orchestrator waiting on, and `<helper_failure>` reads an item as unreturned against exactly this number.

Label every helper `role:item` from a stable per-item slug rather than a property several items share, because a repeated label leaves a dead helper unattributable.
</phase_plan>

<run_economy>
Close every run with its yield in one clause: the helpers dispatched against the decisions or edits they produced. Say plainly when a run cost more than it returned.
</run_economy>

<coverage_tradeoff>
Name every narrowing out loud. When the run answers inline rather than fanning out, verifies a subset rather than every finding, or drops a phase for cost, state in the same reply which checks go unrun and what would surface them, then proceed on the user's word where the narrowing removes a check the fuller shape would have made. A repository's `CHARTER.md` coverage invariant, where one exists, is the authority this rule applies to the skill's own economy rules.
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
Classify a non-result before acting on it.

- A **deliberate self-reported inability** is a completed result: record its stated reason, spend no retry, and route it to the user.
- A **spawn glitch**, meaning a near-instant return with no tool use whose whole output is host boilerplate, earns one identical-prompt re-invocation.
- A **spawn failure, mid-run death, or contract-violating shape** earns the same single re-invocation.

When a re-invocation fails again, mark the item failed against the roster and report it; take a degraded path such as an inline redo only after the user chooses it. This skill owns that one identical-prompt re-invocation for runs the orchestrator owns outright. `task_auto_check`'s `<agent_failure_policy>` is the worked instance of the inability / glitch / failure classification; its retry counts stay authoritative inside its own loop under `<invocation_boundary>`.

A helper that passes its stated wall-clock bound with no return stops being waited on and earns the same single re-invocation, because an absent return and a mid-run death are the same state from outside. Mark the item unreturned against the roster and report it as such when that re-invocation passes the bound with no return either, because a hung helper and a helper that found nothing are otherwise indistinguishable. A helper whose depth pin the provider rejected can die quietly, so state verifier rigour as a behavioural contract in the prompt rather than buying it with a knob. Guard every downstream step against a dead upstream before reading its output.
</helper_failure>

<remediation>
One round, never loop until pass. Only the items that failed verification enter repair, they enter once, and the report marks the repaired output as unverified rather than implying end-to-end coverage. Repeating a stochastic check until it passes selects its most lenient draw rather than verifying. Guard a follow-up fan-out on the count of items that need it, so a pass over an empty list dispatches nothing and says so.
</remediation>

<run_state>
Keep the roster outside your own context. Write the dispatch roster to a scratch file before the first helper, one line per item carrying its identifier, its assigned path or lens, and its state, and update the state as each result lands.

When the run stops early for any reason, report from that roster which artifacts were modified, which were untouched, and which are in an unknown state, and settle the unknown ones by reading the files rather than by trusting a helper's return or a completion notice.
</run_state>

<aggregation>
Merge cited findings, never count agreement. Two helpers raising the same item is shared priors rather than confirmation, so union the proposals and send each through its own refute-by-default check. The orchestrator does the arithmetic, the partitioning, and the joining in the open, keyed by the stable per-item identifier rather than by arrival order. Discarded findings survive into the report with their one-line reason.

Cap any payload pasted into a downstream prompt at a stated size. Tell that pass its material may be cut and that anything load-bearing gets re-read from the source, and list the identifiers of every item whose detail was trimmed.
</aggregation>

<reporting>
Verdict first, three things kept apart. The opening sentence gives the answer, the tier reached, and the helpers dispatched against returned. The body then distinguishes what the run established, what a helper found beyond its brief, and what a helper decided on its own authority that the user should review. Name all three parts on every run and write `none` under a part with no members, so a reader tells an empty bucket from a forgotten one. Helper return shapes stay internal to the run.

Before writing the report, identify the single claim the verdict rests on and check it against the artifact rather than against a helper's report. Name what was re-derived and what was taken on a helper's word, and report a verdict that resisted re-derivation as the helpers' finding rather than as the run's conclusion.
</reporting>

<judgement>
Route the real forks to the user. Removing most of a body, deleting a load-bearing section, picking one side of a real fork, resolving a contradiction, or touching an artifact already marked complete are surfaced rather than settled, at every tier, and no helper writes a field a named gate owns. A run whose ask was which work to do changes nothing, states the no-edit rule in every helper prompt, and closes by asking for the go-ahead.
</judgement>

<references>
Load a reference when the run needs its detail:

- `references/role-prompts.md`: the producing, lens, checking, and synthesis prompt templates.
- `references/report-shapes.md`: worked opening sentences, digests, and closing reports.
- `references/degradation-examples.md`: the same job worked at the inline floor and at full fan-out.
- `references/variants.md`: information isolation between concurrent helpers, and replicated draws returned unreduced.
</references>

<worked_instances>
`agent_spinner` states the general shape; these shipped skills are worked
instances of that shape and keep authority over their own runs. They are not a
`agent_spinner_*` family roster:

- `task_auto_check`: the bounded readiness loop, with its own helper-failure policy and verification standard.
- `task_fix`: whole-tree repair with one escalated writer.
- `wiki_fix`: the collapsed form, where one agent assesses, repairs, and verifies.
- `harness_portability`: every per-harness fact this skill deliberately carries none of.
</worked_instances>

</agent_spinner_skill>
