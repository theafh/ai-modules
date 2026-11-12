# J7. Check-only audit sweep

<check_only_audit>

<trigger>
It runs under per-artifact fan-out and applies only after the selector matched that shape.

The ask sweeps a set of artifacts with an audit and reports what to fix, read-only. Any fix runs later and only on the user's word.
</trigger>

<ledger_steps>
Open the run with `init` over the resolver's artifact list, the list the repository's own resolver produces. Register the ladder the roles use with `--severity` at `init` whenever it differs from the default, and render that ladder into every brief's invariant preamble.

Every deterministic checker runs through `gate` before dispatch. Findings become ledger records, and `rows --phase verify --from-records <finding-pattern>` creates one verifier row per finding before any verifier brief exists. `rows --phase review --role sweep --from-records <confirmed-finding-record>` creates one sweep row per confirmed class, from one of its confirmed findings. `rows --phase review --role check --from-records <review-row>:confirmations:<index>` creates one probe row per probed unit from that unit's confirmation record.
</ledger_steps>

<phases>
1. **Review**: a reviewer reads each artifact, and one reads each comparison cluster, a group of related artifacts compared with each other. Each reads no earlier helper return. Per-artifact reviewers carry the depth checks, which read one artifact closely, and cluster reviewers carry only cross-member comparisons. The union of clusters equals the artifact list, singletons, the artifacts alone in a cluster, receive their neighbours' text, and a cluster above about five members hands its depth checks to per-artifact helpers.
2. **Verify**: a refute-by-default verifier tests each finding, reading that finding's record from the review returns. It works on atomic claims, which are findings split into single claims, and each refutation cites its span. It gives a real but low-value finding its own verdict, and it runs at no lower depth than the reviewer.
</phases>

<width>
Review gets one reviewer per artifact plus one per comparison cluster, and Verify gets one verifier per finding.

A run whose context estimate crosses half the host's window spans sessions at wave ends (P1).
</width>

<roles_and_returns>
Every finding carries `claim`, `severity`, `quote`, and `anchor`, and each examined entry carries its `receipt`, matched against the input version its row recorded (P3). `accept` rejects a return that omits any of them.

The reviewer returns findings as atomic claims, a read receipt for every mandated rubric, what it examined and cleared per criterion, and a `confirmations` list holding one entry per unit it cleared, each entry carrying the unit's `path` and the span that cleared it; `accept` imports each entry as a confirmation record, because `confirmations` is already in `RECORD_LISTS`. The verifier returns a verdict per atomic claim with its settling span, including the direction of the recommendation, such as whether to add or remove text.

A role barred from file writes returns in its final message, which you relay verbatim to `accept --stdin`, never through a shell (P3).
</roles_and_returns>

<adversarial_checks>
`accept` checks each read receipt against the input version its row recorded, never against the live file. Count a path as read only where tool evidence shows a full read, and report a path claimed by receipt alone as unverified by tool evidence (C8). Pair receipts with the class re-sweep, which is the recall check: it searches every unit again for each confirmed class of defect. A clean result without citations routes back once, and the join keeps dead and clean apart, so a helper that died never counts as clean (P3).
</adversarial_checks>

<orchestrator_gates>
These orchestrator steps run in this order, and the announcement lists them as checks. Its first step runs the gate-scope check from run-protocol.md's run-directory section before dispatch. A report step builds the report from the ledger after a clean `close` (P6).

1. **Scout and deterministic checkers**, before Review: enumerate the artifacts with the repository's own resolver, and run the gate-scope check and every deterministic checker over the whole set. Read the repository's test and coverage model before judging any gap. Write the settled results into the preamble, the shared opening every helper brief carries, as measured facts, and share them with the user while the helpers run.
2. **Class sweep and recall probe**, after Verify and before any unit is called clean: `rows --phase review --role sweep --from-records <confirmed-finding-record>` creates one sweep row per confirmed class, from one of its confirmed findings, and that row covers every unit. A confirmed class is a kind of defect a verifier confirmed at least once. Each clean unit chosen for the recall probe gets one probe row from that unit's confirmation record, so a second reviewer re-checks a unit the first review called clean (C8). The orchestrator creates that row with `rows --phase review --role check --from-records <review-row>:confirmations:<index>`, passing the literal id of the unit's entry in the reviewer's `confirmations` list, so the probe row's label stays distinct from the unit's Verify rows.
3. **Report**: per-unit status lists with counts computed from them, and the fix-or-file fork, which asks the user whether to fix the findings or file them as follow-up tasks.
</orchestrator_gates>

<later_run_fix>
A later run, opened by the user's word per the trigger's later-run condition, runs one fix pass. A single writer re-derives each finding and checks each recommendation's direction against the standing rules and the user's latest preference. It re-runs the deterministic checkers, accounts for every removed line, and gets the paired check over the diff. A prior-art check, which looks for the same work already filed or built, runs before any follow-up task is filed.
</later_run_fix>

<failure_handling>
A null review, one that returned nothing, leaves its unit unreviewed. A verifier that threw an error leaves its finding unverified. Neither counts as clean or refuted.

At a turn end with rows out, send the interim report. Any later turn runs `status`, then `attach` when a run is open, and accepts every pending return before it continues (P4).
</failure_handling>

<stop_and_ask>
The fix-or-file fork and every direction conflict go to the user. A direction conflict is a recommendation whose direction clashes with the standing rules or the user's preference. Commits and version bumps wait for the user's explicit request.

Ask about scope and the estimate before dispatch, with the estimate beside any size guideline the host or user states, and ask before any widening past the enumerated list. An answer the request states is the user's answer. On a host with no later turn, an unanswered gate ends the run with its decision packet (P1). Create the stop file with `stop` the moment a pause request arrives, before any question (P4).
</stop_and_ask>

<report>
Count units as clean with citation, clean after the probe, or unreviewed, and findings as refuted, narrowed, or downgraded. Label each survivor from its ledger tag: "survived its verifier, recall-confirmed" where the verifier's brief relayed it. Reserve "confirmed" for a finding surfaced independently or re-derived against the source. Split the confirmations into recall-confirmed and independently surfaced, and close with the fork.
</report>

<cost_profile>
Keep these whatever else is cut: coverage by construction, a review of every landed write, and baseline-differential gates. Offer each cut only as a narrowing the user chooses, with the checks it drops. Estimate the cost as rows per phase, times the per-row cost the pilot measured, plus the checking share.

Two cuts are possible. Dropping comparison clusters drops the cross-member comparisons. Dropping the recall probe on clean units drops the direct recall measure beside the class sweep.
</cost_profile>

<tier_notes>
Inline floor: reviewers run as separate passes, and the report says verification is recall-limited. Batch delivery: the reviewers go out in one batch and the verifiers in the next. Notice delivery: each finding's verifier row comes from `rows` as its review is accepted, and its verifier goes out then. Poll the final wave inside the turn with `accept --wait` (P4).
</tier_notes>

<post_run_checks>
Every unit has a state, every clean unit carries citations, and the counts match the lists. Every receipt matched the input version its row recorded, every path counted as read has tool evidence of a full read, and every finding record has a verifier row.
</post_run_checks>

</check_only_audit>
