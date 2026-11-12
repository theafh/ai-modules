# J4. Drift repair across many artifacts

<artifact_repair>

<trigger>
It runs under per-artifact fan-out and applies only after the selector matched that shape.

The ask finds which of many specification artifacts drifted from the repository, fixes them, and checks the fixes. Such artifacts are tasks, specs, or procedure pages, and one has drifted when what it says no longer matches the code. These signals mark the ask: items with anchors into the code, status stamps that separate gates own, and completed items beside live ones. Where a shipped family owns the backlog, its contract governs, and every stamp consequence goes to that family's gate by name. That family's contract states what the gate does.
</trigger>

<ledger_steps>
Open the run with `init` over the drift table's drifted rows, with each row's stamps as the owning family reports them. The scout writes the drift table, its verdict on every artifact. Register the ladder the roles use with `--severity` at `init` whenever it differs from the default, and render that ladder into every brief's invariant preamble.

An item fails its check when that check raised a blocking or should-fix finding, whatever verdict word the checker used. A nit-only item goes to the report. `rows --phase write --role writer --from-records <repair-record-id>` runs once per failing item, keyed on that item's lowest-id blocking or should-fix finding record, so each failing item gets one repair row, and `rows --phase check --role recheck --from-records <repair-record-id>` creates that item's re-check row from the same record (C5). The repair brief passes `--kind repair --target <path>` and the re-check brief passes `--kind recheck --target <path>`, the failing path. Issue the re-check brief before that path's repair row dispatches, so the row records the pre-repair file as its input version, and dispatch the re-check row once the repair row is accepted. `rows --phase write --role writer --from-records <critic-finding-pattern>` creates one write row per critic finding that needs a repair or a new artifact, and `diff --add-checks` adds its check row. The link-graph validator, which checks the links between artifacts, runs before `close`. The roster shows a routing or fork row for every changed path recorded as stamped, sending the change to the owning gate or to the user (C9).
</ledger_steps>

<phases>
1. **Write**: a writer repairs each drifted artifact and reads no earlier helper return. Its brief has four parts: what is stale, the tree state to verify, the fix, and what to verify without assuming it is stale.
2. **Check**: a checker reads each repair's diff against its brief, with the writer's return, and goes out as soon as its writer returns.
3. **Critique**: three critics each test the scout's work under one lens (C6), reading the drift table and the net diff and no helper return. One refutes every item the scout called current, one reads recent commits for landed work no item accounts for, and one scans outward from the touched code.
</phases>

<width>
Write gets one writer per drifted row, and Check gets one checker per repair. The repair round gets one remediator per item on the repair list (C5). Critique gets three to five critics. Each critic repair and each new artifact gets one write-and-check pair. Each trade-off proposal, such as a merge or a split, gets one advocate per side.

A run whose context estimate crosses half the host's window spans sessions at wave ends (P1).
</width>

<roles_and_returns>
Every finding carries `claim`, `severity`, `quote`, and `anchor`, and each examined entry carries its `receipt`, matched against the input version its row recorded (P3). `accept` rejects a return that omits any of them.

The writer returns its label and path, what it applied and skipped, brief corrections, judgement calls, the contract clauses its changes touched, a statement that it left the stamp alone, and incidents. A brief correction is a place where the writer found its brief wrong.

The checker returns a verdict (`pass` or `fail`, the ledger's only verdict values) and issues with a severity (blocking, should-fix, or nit). The finding list decides the item's fate, so a `fail` verdict carrying only nits leaves the item out of the repair list. It also reports the anchors checked and those that miss, whether intent was preserved, the stamp consequence, and the fate of each input finding: resolved, refuted with its re-derivation, or silently dropped.

The critic returns its lens, findings with evidence, and items confirmed clean with citations.

The remediator returns applied, refuted with its span, or routed per finding, plus the minimum edit it made.

A role barred from file writes returns in its final message, which you relay verbatim to `accept --stdin`, never through a shell (P3).
</roles_and_returns>

<adversarial_checks>
A trade-off question gets a symmetric stance, which argues each side at full strength: one challenger per side, the user's objective in the user's own words, and a status-quo cost beside every proposal (C2). The repair checker opens from the position that the repair is incomplete or wrong. It runs a closed checklist of seven to nine lines, which check these points:

- The diff matches the writer's report, with unrequested and missing changes listed.
- Every quoted anchor is re-derived.
- No new defect of the repository's banned classes appears.
- Intent is unchanged.
- Stamps are unchanged, and the stamp consequence is stated.
- The named staleness is gone.
- Every input finding is accounted for.
</adversarial_checks>

<orchestrator_gates>
These orchestrator steps run in this order, and the announcement lists them as checks. Its first step runs the gate-scope check from run-protocol.md's run-directory section before dispatch. A report step builds the report from the ledger after a clean `close` (P6).

1. **Scout**, before Write: read every artifact and test its anchors, run the gate-scope check, and write a drift table. The table names the method behind each verdict and lists the items judged current, marking those judged on anchors alone.
2. **Lifecycle triage**, before Write: route each completed item to its audit or close-out, or to a new follow-up item, and leave its contract as delivered. Route every write to a stamped target to its owning gate by name, or to the user as a fork, whatever the write changes (C9).
3. **Sibling-surface enumerator**, at the barrier before any contract repair: one helper lists every surface that carries the same contract, such as a sibling file or block that states the same rule.
4. **Critic rows and new artifacts**, after Critique: every critic repair and every new artifact (a filing, merge, split half, or repoint) gets its own write-and-check pair. A filing is a newly filed item, and a repoint moves links to a new target. A new artifact starts at its initial lifecycle state, with its inbound-reference map, the list of links that point at it, built from the repository root.
5. **Repair round**, after the critic rows and new artifacts.
6. **Terminal validation**, last: one terminal writer runs the linter last and the link-graph validator from the root, and status fields go to the owning family's gate by name (C9).
7. **Report**: the report step that the shared lines describe.

The one repair round (C5) re-enters the write phase and the checking phase that reads the repaired diff, as `<phases>` names them, for the failing rows.
</orchestrator_gates>

<failure_handling>
Return templates put the verdict first and allow at most one long free-text field. The limit exists because a return with two overlapping fields can oscillate between them until its retries run out. A failed slot, meaning one helper's row, is attributed by its label and re-invoked once. The synthesis, the pass that merges the returns, receives the full item list with states, so it names any missing slugs, the stable per-item ids.

At a turn end with rows out, send the interim report. Any later turn runs `status`, then `attach` when a run is open, and accepts every pending return before it continues (P4).
</failure_handling>

<stop_and_ask>
Surface completed items, stamp consequences, every labelled fork, every deletion of committed content, and every trade-off answer. Quote the governing skill's writer rule in the plan. State any departure from it in the same sentence as the work, together with the user's permission.

Ask about scope and the estimate before dispatch, with the estimate beside any size guideline the host or user states, and ask before any widening past the enumerated list. An answer the request states is the user's answer. On a host with no later turn, an unanswered gate ends the run with its decision packet (P1). Create the stop file with `stop` the moment a pause request arrives, before any question (P4).
</stop_and_ask>

<report>
Keep brief corrections, checker findings, and critic findings apart. Give verdict counts from records, and each stamp consequence with the gate or user it went to. Compare the forks returned with the forks relayed, and list each filing with its check row. Close with open items by id and yield, the helpers dispatched set against the decisions or edits they produced.

Report each repaired item as re-checked once, recall-limited, and unverified end to end, or as failed after repair (C5).
</report>

<cost_profile>
Keep these whatever else is cut: coverage by construction, a review of every landed write, and baseline-differential gates. Offer each cut only as a narrowing the user chooses, with the checks it drops. Estimate the cost as rows per phase, times the per-row cost the pilot measured, plus the checking share.

The cuts are critics beyond three and single-artifact panel lenses beyond three. Each cut drops extra looks at the same work.
</cost_profile>

<tier_notes>
Inline floor: write and check run back to back, and the critics share the scout's context, so their confirmations are recall-limited. Batch delivery: the run goes in waves, with the returned batch as the barrier before the critics. Notice delivery: checks wait on accepted writer returns, the orchestrator follows the run by reading the roster through `status`, and the final wave is polled inside the turn with `accept --wait` (P4).
</tier_notes>

<post_run_checks>
First-pass writers equal the drifted rows, each writer's diff touches only its path, and every repair has a check row. The repair list equals the failing items plus the class-sweep instances, the instances a sweep for a confirmed class of defect found. Every changed path recorded as stamped has a routing or fork row, and every new artifact has a check row. Forks returned equal forks relayed plus forks listed as the orchestrator's own decisions.

Each repaired item has exactly one re-check row, at no lower depth than its first check.
</post_run_checks>

<single_artifact_variant>
For one artifact repaired over several rounds when no family loop governs it, a panel of three to five lenses over the identical artifact replaces a single first readiness draw, meaning one run of a readiness check. The panel includes an interaction lens that derives touch points, the names and files the change touches, and searches the code for them. The issue-by-stance list goes to the roster from the panel's accepted finding records, one record per issue: `rows --phase review --from-records <panel-finding-pattern> --role proof` and `rows --phase review --from-records <panel-finding-pattern> --role trim` each create one row per issue per stance, labelled from the record id, and each row's brief carries the issue text's slug and its stance. Each issue gets one reviewer per stance: the `proof` row adds proof and the `trim` row trims. The sibling-surface enumerator runs before any proposal. The verifier reads the gate verdict and every reviewer return by file, with no preference stated, and it quotes the issue sentence each decision rests on (C3). Anchored replacements keyed by approved-edit id are applied, and then the post-apply delta audit checks the applied change against the approved edits (C1). Every deletion of behaviour-bearing content waits for the user. One re-gate, a fresh run of the readiness gate, runs in isolation with the transcript store off limits. One refute pass, with external-evidence clears, tests the final clean result (C2). A further round waits for the user.
</single_artifact_variant>

</artifact_repair>
