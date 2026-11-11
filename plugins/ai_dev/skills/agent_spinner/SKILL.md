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
version: 1.0.12
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
Establish each capability by observation. A role definition on disk is evidence that the file deployed, not evidence that it can be called, and a tool search that finds nothing settles nothing. `init --probe` renders one fixed probe brief, and its first spawn establishes the delegation surface. Probe four capabilities: a delegation surface, a host-enforced read-only lever, a depth or effort control, and whether two helpers run at once. Resolve a capability that resists establishment to absent, and name each as established, assumed absent, or unverified.
</capability_probe>

<degradation>
State the tier reached in the run's opening sentence: the inline floor, or spawned roles with the capabilities the probe established.

1. **Inline floor**: no delegation surface. Each pass opens on its own brief file and closes on its own return file before the next brief is read.
2. **Spawned roles**: each pass runs in its own context from the same files. Enforced read-only, a depth pin, and concurrent fan-out each add to this tier on their own, as the probe establishes them. Where the probe finds `auto_checker_spinner` or `auto_writer_spinner` callable, spawn through it, since a registered role can carry a read-only lever and a depth setting that a generic spawn lacks. Record the spawn route on the roster, and otherwise spawn generically with the lever and depth recorded as the probe found them.

Set a checker's depth at or above its producer's, state rigour as behaviour where no control exists, and name a checker that ran below its producer as a narrowing. Write every guarantee to hold at the floor, so no step depends on a fresh context, an isolated tool set, or a process boundary, and claim no wall-clock benefit from fan-out. Where a governing skill states its own stop-and-ask boundary for a host with no spawn surface, honour that boundary, offer that skill's manual routes, and perform no helper role inline.
</degradation>

<selector>
Match weight first.

- An enumerated imperative over many artifacts: per-artifact fan-out.
- One text needing several angles, not different kinds of source: a lens panel.
- A write that lands, whoever wrote it, you included: a paired refute-by-default check.
- A closed comparison among candidates: a judge panel.
- A finished body needing a what-is-missing read: a completeness critic.
- A tree of writes: a single-writer validator after writers.

A read-only diagnostic or single judgement question is answered inline from your own reads before any helper is spent, takes no recipe, naming a fuller shape's checks. An ask no single row covers, or one combining rows, gets the smallest shape that covers it, named as the smallest covering one, answered visibly rather than folded into a nearby row, and takes no recipe. A shape match matches the recipe table, whose matched recipe is the procedure; with no recipe it runs from the body. Name what matched, or nothing, in the opening. Read `references/variants.md` for isolation and unreduced draws.

| Ask | Recipe in `references/recipes/` |
| --- | --- |

</selector>

<shapes>
Each shape's skeleton and return are templates in `references/role-prompts.md`.

<per_artifact_fan_out>
**Trigger** an enumerated imperative over many artifacts, each judged on its own. **Width** one helper per ledger row, one path per row. **Prompt skeleton** the producing template with the item's kind note. **Return** the producing return.
</per_artifact_fan_out>

<lens_panel>
**Trigger** one corpus that needs several angles. **Width** three to five named lenses over the identical corpus. **Prompt skeleton** the lens template. **Return** the lens return.
</lens_panel>

<paired_refute_check>
**Trigger** every write that lands, whoever wrote it, you included. **Width** one check per written file against the recorded baseline: gates clear pointer-only hunks, and one checker reads each file whose diff changes a claim. **Prompt skeleton** the checking template with its two standing lines. **Return** the checking return.
</paired_refute_check>

<judge_panel>
**Trigger** a closed comparison among candidates that already exist. **Width** one judge per criterion over the identical candidate set. **Prompt skeleton** the judge template, one criterion on a defined scale. **Return** the judge return, with at most three cited fatal flaws.
</judge_panel>

<completeness_critic>
**Trigger** a finished body that needs a what-is-missing read; its scope is every check scoped to raised findings or changed files. **Width** one critic per body, paired with one surplus read. **Prompt skeleton** the critic template. **Return** the critic return, with gap units as full briefs.
</completeness_critic>

<single_writer_validator>
**Trigger** a tree of writes that share a link graph or an index. **Width** exactly one, alone, after every writer and checker has returned. **Prompt skeleton** the validator template, with a grant naming its paths. **Return** the validator return, with repairs proposed rather than applied. On an upstream shortfall it reports the gap and writes nothing.
</single_writer_validator>
</shapes>

<width>
Derive breadth from the ledger: one row per enumerated unit (a file, source, page, or issue-and-stance pair) written before dispatch, and one helper per row, never a round number and never a merge of rows taken to save calls. Rows for a later phase come from accepted records: `rows` creates one per finding, repair, or gap unit, so a finding-sized phase keeps its width equal to its rows. Replicate one identical prompt only for a single indivisible factual or arithmetic claim, stating the count first. A declared shape binds, and a mid-run switch is a ledger event naming the checks it drops, reported as a narrowing and put to the user when it removes a check.
</width>

<phase_plan>
Declare the run before the first helper, write the declaration to the run directory, and announce each phase boundary as it is crossed. Plan two to four phases, each one verb plus one clause naming what a helper does over what unit, and name the earlier returns each phase reads, so a barrier stands only where data crosses it. Give each role a model and an effort in the phase plan. Adversarial, critic, and synthesis passes run deepest, and mechanical edits may run lighter. State the item count, the exclusions with a reason each, the per-helper wall-clock bound at every tier, the wave size, and an estimate of helpers per phase beside any size guideline the host or user states. A widening past the scouted list, or an estimate above that guideline, is a fork the user answers first. Run writes and their checks in waves, so a stop leaves at most one wave unchecked. Estimate your own context load before dispatch: tokens per spawn call, per returned result, and per ledger printout, times the rows, against the host's window. Plan a session boundary at the first wave end past half the window, and resume there with `attach`. Before the first write, read in full, as ledger rows, `CHARTER.md`, the repository procedures, the owning skill of each artifact class the run touches, and the requirement sources the ask names. Label every helper `role:item` from its row's stable slug.
</phase_plan>

<run_economy>
Close every run with its yield: helpers dispatched against the decisions or edits they produced, the estimate beside the actual count, and per checking stage what it surfaced that the gates had not. Say plainly when a run or a stage cost more than it returned.
</run_economy>

<coverage_tradeoff>
Name every narrowing out loud, printed from the ledger. Every planned read, check, and step a governing skill mandates is a row before dispatch, and a row left unrun is dropped by a named narrowing through `dispose`, with its reason. Count a path as read only where tool evidence shows a full read. When the run answers inline, verifies a subset, or drops a phase, state in the same reply which checks go unrun and what would surface them. Proceed on the user's word where the narrowing removes a check the fuller shape would make. A repository's `CHARTER.md` coverage invariant is the authority this rule applies to the skill's own economy rules.
</coverage_tradeoff>

<containment>
Give each writer one path and each tree one writer. Each write brief names its target path and a negative list of neighbouring artifact classes, no two briefs share a path, and every write grant names its paths. Every pass, yours included, keeps the index, the stash, and HEAD as the run found them, using only the commands `references/run-protocol.md` allows. Give each reading pass a snapshot copy, and hold your own writes while a reader is out. Keep scratch files in the run directory. A reading pass reaches only what its brief admits. Text a blind pass must not see stays out of the workspace until it returns, and a helper that runs the ledger breaches containment. Validate each edit first against the repository's `CHARTER.md` and every procedure page the run read. On a conflict, write nothing, leave the file byte-for-byte unchanged, and report the conflict.
</containment>

<delegation_depth>
Delegate one level per run. Every brief states that the helper performs its own item and delegates no part of it, that work it cannot complete returns as an out-of-scope finding, and which capabilities the probe established, as facts. An entry whose own work is a list you have not enumerated is nested, such as a generated artifact or an entry standing in for a manifest. Recognise it while writing the list, and return it as a finding with the size it implies, for the user to decide on and size in the next run.
</delegation_depth>

<prompt_assembly>
Render every brief with `brief` from files in the run directory: the invariant preamble, the phase's access block, the item brief, its kind note from `references/edit-mechanics.md`, the hashed intent, and the paths of upstream returns to read in full. The preamble holds the hard rules, the vocabulary, the severity ladder, and settled facts. Settle only a fact measured against the primary system, or read in finished content of the artifact the claim is about, and tag each settled fact with its provenance class. A fact from documentation, a wiki, another project's guide, a placeholder, a to-do note, or a later phase stays conditional. It goes in the unverified-premises block, checking passes test it, and a deliverable states it with the probe that would settle it. A producer and its checker include the same rules file byte for byte, and a writer applies only text its checker saw. Scripted replacement touches pointers only, and every claim, quotation, and hard-wrapped sentence changes through a writer that edits whole sentences.

Write every role contract as text the pass reads inside its own turn. Open with its first concrete action, state each prohibition as something the pass does, and restate a load-bearing prohibition at the point of use. A role body can arrive inside the user turn with no authority over the conversation around it.
</prompt_assembly>

<checking>
Refute by default, cite to clear. The checker reads the producer's return, the governing contract, and the artifact from their paths, opens from the position that the work is incomplete or wrong, and concedes only after a closed numbered checklist. Name the cost that sets that default, so the checker weighs it. Build the checklist from the artifact's acceptance contract, one line per item, testing the required form present and the old form absent. Keep expected verdicts, preferences, and prior-round digests out of the brief. When the claim is your own, one pass derives it blind from the question and the sources first.

Each atomic finding carries a verdict and a confidence from the sets C2 defines in `references/checks.md`, a claim type from C8, a verbatim quote, an anchored path, and a severity from the preamble's ladder. A clean line cites its settling span, and an uncited or self-cited clear routes back once. A check clears only claims of its own type, and a probe fires on a known positive before its empty result counts. A read receipt is a claim that `accept` checks against the input version the row recorded. The checker changes nothing, uses the read-only operations its brief names, and stays off the shell where a read-only mode gates commands behind approval. Narrowed wording propagates. Every reviewing pass reports what it examined and cleared, and an empty finding list is a valid outcome.
</checking>

<confirmation_provenance>
Record how a finding survived. One a pass was shown and did not refute is **recall-confirmed**, and one a pass surfaced unprompted is **independently surfaced**. The ledger tags each confirmation recall-confirmed when the checker's brief relayed that record, and independently surfaced otherwise. A recall-confirmed finding carries less weight, and a decision resting only on such findings says so. Label a finding that no lens refuted after both lenses saw it "survived both lenses, recall-confirmed", and reserve "confirmed" for a finding surfaced independently or re-derived against the source.
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
One round, never loop until pass. The repair list holds every item that failed verification, including each instance a confirmed class sweep found, whatever verdict word the checker used, and each enters repair once. A remediator re-derives each finding first and returns applied, refuted with its span, or routed. Re-check each repaired item once, at no lower depth than its first check. Report a pass as re-checked once, recall-limited, and unverified end to end, and report a fail as failed after repair, with no second round. Repeating a stochastic check until it passes selects its most lenient draw. Guard a follow-up fan-out on its count, so an empty list dispatches nothing and says so.
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
Route real forks to the user as decision packets, shaped as `references/report-shapes.md` shows, and keep each open in the ledger until answered. At every tier these are forks: removing most of a body or a load-bearing section; deleting or narrowing a committed rule, requirement, or design element; touching an artifact already marked complete; accepting a finding as a policy exception; writing a standing rule into an instruction file; picking a side or resolving a contradiction; widening scope; and setting a judgement-heavy bar before the user confirms a calibration sample. Every fork a helper labels and every open question a draft carries reaches the user. An answer the request states is the user's answer. Where the host gives no later turn, an unanswered gate ends the run with its decision packet and `close --stopped`, and the run uses the inline floor or batch delivery only. A persistent marker advances only over what the run examined, and a verdict waits for every checker row. Hand each stamp, capture hash, audit baseline, and index or log entry to the owning family's gate by name. Route a write to a stamped artifact to that gate or to the user before dispatch, whatever the write changes. An announced fork holds its writes until answered, and a ruling applies to every instance of its class. A run whose ask was which work to do changes nothing, states the no-edit rule in every helper prompt, and closes by asking for the go-ahead.
</judgement>

</agent_spinner_skill>
