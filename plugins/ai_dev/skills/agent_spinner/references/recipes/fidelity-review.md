# J1. Source-fidelity review and fix

<fidelity_review>

<trigger>
It runs under per-artifact fan-out and applies only after the selector matched that shape.

The ask checks derived documents against the sources they cite. It looks for dropped details, misreadings, overcompression, invented forks, wrong connections, and missed integration. The run fixes what the sources settle and puts the rest to the user. These signals mark the ask: pages with a source-lineage field that names their sources, source captures with recorded content hashes, an index and a log, and live originals behind the captures. A source capture is a stored copy of a source, and its live original is the source it was copied from.
</trigger>

<ledger_steps>
Open the run with `init` over the lineage inventory, meaning the pages listed from their source-lineage fields, with its exclusions. Pass the pages and captures the owning family reports as marked, meaning they carry a marker (C9), as owned targets. On a corpus no family owns, pass the corpus's own markers (capture hashes, audit baselines, index and log entries) as `--owned-target PATH:user:fork` entries, which name the user as the owning family and the fork as its gate. Register the ladder the roles use with `--severity` at `init` whenever it differs from the default, and render that ladder into every brief's invariant preamble.

`accept` checks each finder's coverage list against the inputs its unit recorded. `rows --phase verify --role source-lens --from-records <verify-pattern>` and `rows --phase verify --role page-lens --from-records <verify-pattern>` create the Verify rows, one row per lens for every write-bound finding, each sourced from that finding's record and labelled for its own lens. `rows --phase find --from-gaps <critic-row>` creates the gap-unit rows from the completeness critic's accepted return.

`rows --phase write --role writer --from-records <repair-record-id>` creates one repair row per failing path, keyed on that path's lowest-id blocking or should-fix finding record, and `rows --phase review --role recheck --from-records <repair-record-id>` creates that path's re-check row from the same accepted record. The repair brief passes `--kind repair --target <path>` and the re-check brief passes `--kind recheck --target <path>`, the failing path. Issue the re-check brief before that path's repair row dispatches, so the row records the pre-repair file as its input version, and dispatch the re-check row once the repair row is accepted (C5).

Accept the plan against every target path the surviving findings name. The linter differential, which compares the lint output at the baseline and at the end, runs last as a `gate`. Before `close`, each changed marked path has a hand-off or fork row. A hand-off row passes the marker update to the owning family's gate, and a fork row puts it to the user.
</ledger_steps>

<phases>
1. **Find**: a read-only finder reads each unit against its cited sources and reads no earlier return.
2. **Verify**: two refute-by-default lenses test each write-bound finding, meaning each finding that would lead to an edit, and each lens reads the Find return that raised it.
3. **Write**: a writer applies each target path's confirmed block, the confirmed findings for that path, reading the findings file.
4. **Review**: a read-only reviewer reads each changed path's diff against the baseline, with its Write return.
</phases>

<width>
Find gets one finder per unit row. Verify takes the write-bound findings plus a fixed sample of each unverified band, times two lenses, in batches of at most five (C7). An unverified band is a severity band left out of full verification. Write gets one writer per target path. Review gets one reviewer per changed path in the net diff, the orchestrator's own edits and the index included (C1). The repair round gets one repairer and one re-checker per failing path. The plan caps the gap units, the extra units the completeness critic proposes for ground the earlier passes missed (C6). Verify, gap-unit, and repair rows come from accepted records (P4). Lenses and reviewers run no shallower than the passes they check.

A run whose context estimate crosses half the host's window spans sessions at wave ends (P1).
</width>

<roles_and_returns>
Writers, repairers, and the validator, the roles that may write files, write return files. Every finding carries `claim`, `severity`, `quote`, and `anchor`, and each examined entry carries its `receipt`, matched against the input version its row recorded (P3). `accept` rejects a return that omits any of them.

The finder returns its label, its unit, and findings. Each finding carries an id, a kind (dropped detail, misread, overcompressed, false fork, integration hole, or wrong connection), a severity, a class (fix or decide), the page path and quote, the source path, anchor, and quote, and a suggested fix. A fix-class finding is one the sources settle, and a decide-class finding goes to the user. The finder also returns its coverage per path (read in full, searched, or unreachable), what it examined and cleared, beyond-brief finds, and incidents.

The completeness critic returns its `gaps` list, one entry per gap unit carrying the gap unit's full brief, with the coverage records it read and the items it confirmed present with their anchors.

The source lens re-reads the source in context, and the page lens re-reads the page and searches the corpus. Each lens returns, per finding, a verdict (confirmed, partly, or refuted), a corrected statement for partly, the settling span, and a confidence.

The writer re-reads the cited source and applies exactly its block. It returns applied, rejected, or routed per finding, with the span it re-read. It also returns contradictions between its instructions and the source, the recorded decisions it touched, and incidents.

The reviewer returns issues with a kind (instruction unapplied, unsupported, lost qualifier, dropped content, misquote, decision changed, or prose), a severity, the hunk, the source span, and a fix. A hunk is one changed block of a diff. It also returns the hunks it cleared.

The repairer re-derives each issue and returns applied, refuted with its span, or routed (C5).

The validator returns the invariants held, the invariants broken with path and anchor, and the proposals it left unapplied.

A role barred from file writes returns in its final message, which you relay verbatim to `accept --stdin`, never through a shell (P3).
</roles_and_returns>

<adversarial_checks>
Both lenses open from "refuted unless the evidence confirms". A partly verdict's corrected statement replaces the finding downstream. A finding survives when no lens refutes it and at least one lens returns, and it takes the lower severity. When both lenses saw it, its label is "survived both lenses, recall-confirmed". Each batch set carries one known-false control, a planted finding that its quoted source contradicts, so a verifier that confirms it has failed (C7).

The reviewer opens from the position that the edit dropped, distorted, or skipped something. It reads the diff, the writer's block, and the cited sources. It clears a hunk only with a hunk citation plus a source citation.
</adversarial_checks>

<orchestrator_gates>
These orchestrator steps run in this order, and the announcement lists them as checks. Its first step runs the gate-scope check from run-protocol.md's run-directory section before dispatch. A report step builds the report from the ledger after a clean `close` (P6).

1. **Scout**, before Find: build the inventory by script from the lineage fields, and exclude each page with no resolvable source, with its reason. Cut units one helper can read in full. Add the cross-cutting sweeps the corpus needs: a fact ledger, the open questions the sources settle, and sources no capture holds. Run the gate-scope check, record the baseline and the roster (P1), and put the scope forks, the verification scope, and the estimate to the user (C7). On a corpus no family owns, the markers the ledger steps pass to `init` as `--owned-target PATH:user:fork` entries stand as marked targets.
2. **Critic**, at the Find barrier: the completeness critic reads the coverage records, and its gap units become Find and Verify rows (C6).
3. **Findings file**, before Write: build it by script, with one block per target path. Use a planner only where root-cause clustering, grouping findings by their shared cause, needs judgement. Take its plan as a manifest, and treat any canonical statement it writes as a produced artifact (P3).
4. **Repair round**, after Review, for the paths with a blocking or should-fix issue.
5. **Terminal validation**: the validator checks the index, log, and schema invariants.
6. **Hand-offs**: capture hashes, the audit baseline, and index and log upkeep go to the owning family's gate by name, naming as examined only rows read in full (C9). On a corpus no family owns, each marker update goes to the user as a fork.
7. **Report**: the report step that the shared lines describe.

The one repair round (C5) re-enters the write phase and the checking phase that reads the repaired diff, as `<phases>` names them, for the failing rows.
</orchestrator_gates>

<failure_handling>
A plan whose tasks cover fewer target paths than the findings name stops the run before Write. The planner gets one re-invocation with the gap listed, and a second miss fails the phase, which the report states. The terminal validator writes only its named set, and it returns a shortfall report when an upstream phase produced nothing. A dead finder earns one re-invocation, and then its unit is reported unreviewed. A finding whose lenses both failed stays unverified. An aborted writer's paths are reconciled from the diff before any re-dispatch (P4).

At a turn end with rows out, send the interim report. Any later turn runs `status`, then `attach` when a run is open, and accepts every pending return before it continues (P4).
</failure_handling>

<stop_and_ask>
Put the verification scope to the user with the scope and the estimate. Before dispatch, route every write to a marked page or capture to the owning family's gate or to the user, whatever the write changes (C9). A widening from review to fix goes to the user. So does a marker advance past the rows read in full, meaning a marker that would claim more than the run read, and so does an item that fails its re-check. Every decide-class finding and every writer contradiction goes out as a decision packet (P6). Writers keep every recorded decision. Where a source undercuts a decision's premise, the writer adds one sentence saying the premise is worth revisiting.

Ask about scope and the estimate before dispatch, with the estimate beside any size guideline the host or user states, and ask before any widening past the enumerated list. An answer the request states is the user's answer. On a host with no later turn, an unanswered gate ends the run with its decision packet (P1). Create the stop file with `stop` the moment a pause request arrives, before any question (P4).
</stop_and_ask>

<report>
Build the report from the tally block, the counts `close` prints (P6). The opening sentence counts the helpers dispatched, returned, and accepted in each phase. Coverage splits into read in full by tool evidence, claimed by receipt only, only searched, and unexamined, and each unexamined class names the check that would cover it. Findings are counted raised, verified, narrowed, and refuted per lens, split into recall-confirmed and independently surfaced. Each unverified band carries its sample rate, and a zero refutation rate is named as a calibration question. List the paths written, reviewed, repaired, and re-checked, the open items by id, and each hand-off with the rows it names as examined.

Report each repaired item as re-checked once, recall-limited, and unverified end to end, or as failed after repair (C5).
</report>

<cost_profile>
Keep these whatever else is cut: coverage by construction, a review of every landed write, and baseline-differential gates. Offer each cut only as a narrowing the user chooses, with the checks it drops. Estimate the cost as rows per phase, times the per-row cost the pilot measured, plus the checking share.

The cuts are a narrower verification scope, a smaller sample of each unverified band, and a lower cap on gap units.
</cost_profile>

<tier_notes>
Inline floor: Find and Verify run as separate passes, each closing on its return file, and Review reads the per-file diffs that `diff` wrote. Batch delivery: each wave's lenses go out in the batch after its finders, and a row that returns late is marked as over its bound (P4). Notice delivery: send a unit's Verify rows once its Find return is accepted, and hold page writes until the readers return (P5). Where the notice carries no result, batch the read-only roles (P3) and poll the Review wave inside the turn (P4).
</tier_notes>

<post_run_checks>
Unit rows equal the inventory minus exclusions, and each unit has an accepted return with a coverage list. Every write-bound finding has two lens verdicts or an unverified label. Writers before the repair round equal the distinct target paths, and every changed path has a review row. Every changed marked path has a hand-off or fork row, and each hand-off names as examined only rows read in full (C9). Every premise sentence the plan routed exists in its landed page. A premise sentence is the sentence a writer adds to say that a decision's premise is worth revisiting.

Each repaired item has exactly one re-check row, at no lower depth than its first check.
</post_run_checks>

<family_owned_variant>
When the user names this skill for a knowledge base the wiki family owns, the family writer stays the only writer. The orchestrator runs the scout, Find, the critic, and Verify at its own level. It then hands `wiki_fix` the confirmed findings as its scope, once the user approves the list. After the writer returns, the orchestrator runs Review and sends every repair back to `wiki_fix` as a findings list the user approves. It relays the family agent's report as that family's contract requires. The family agent keeps its own checks, and the variant restates none of them.
</family_owned_variant>

</fidelity_review>
