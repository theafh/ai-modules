# J6. Understand-then-synthesize research

<research_synthesis>

<trigger>
It runs under a lens panel and applies only after the selector matched that shape.

The ask is research, an assessment, a feasibility study, or mining across a large corpus into one deliverable, such as a specification, a task, an assessment, or a proposal.
</trigger>

<ledger_steps>
Open the run with `init` over the corpus manifest, the list of sources in scope, with its exclusions and one topic row per reader.

`rows --phase verify --from-records '*:findings:*'` creates one verifier row per finding record before any verifier brief exists, and it runs once Judge's returns are accepted. Each reader records its load-bearing claims as findings, and each drafter records its own draft's load-bearing claims as findings, so every load-bearing claim, the leading option's among them, has a row and every row gets a verifier.

Accept the synthesis candidate only by its echoed id, the identifier its return repeats back. The deliverable and every later artifact get check rows.
</ledger_steps>

<phases>
1. **Understand**: a reader per topic row returns tiered facts and reads no earlier return. Each topic row carries a reason. The shared preamble and the phase's access block, which states what the pass may read and write, give these rules: no writes, cite file and line, tag every fact as measured, read, documented, placeholder, or inferred, and name what could not be verified (C10). The return template holds facts and open questions, and each lineage gets at least one lens on outcome and reaction evidence.
2. **Draft**: three to five drafters each write one angle, reading the briefing file merged from the Understand returns. The angles include the user's floated option and one angle arguing that the premise is wrong. Helper-derived material enters each brief as a hypothesis the drafter verifies, with a brief-corrections slot where the drafter records what it found wrong in its brief.
3. **Judge**: a judge per criterion scores the full draft set, reading every draft by path. It scores on an anchored scale with a one-line definition per point, ranks at most three fatal flaws with a span each, and states the strongest argument against its own verdict.
4. **Verify**: a neutral refuter tests each load-bearing claim, reading the judges' returns and the drafts they score. Verification covers the premises and the leading option's claims. Each claim is stated neutrally, the refuter names what would make it survive, and it returns survives, narrowed, or refuted with a span.
</phases>

<width>
Understand gets one reader per topic row. Draft gets three to five drafters, Judge one judge per criterion, and Verify one verifier per load-bearing claim. One critic runs with one surplus read, and each shipped artifact gets one checker.

A run whose context estimate crosses half the host's window spans sessions at wave ends (P1).
</width>

<roles_and_returns>
The reader returns facts with tier and span, open questions, and what it could not verify. The drafter returns its draft with its label, its load-bearing claims as findings, and brief corrections. The verifier returns, per claim id, a verdict, a span, a confidence, and what would make the claim survive. The judge returns as its phase states, and the critic returns gaps with file-and-line citations and paste-ready fixes.

A role barred from file writes returns in its final message, which you relay verbatim to `accept --stdin`, never through a shell (P3).
</roles_and_returns>

<adversarial_checks>
A pivotal number, one the verdict turns on, gets one blind derivation (`variants.md`, `## Blind derivation`). Refutation is neutral. Before the synthesis reads any candidate, recovered results pass the identity check: one distinguishing line of the candidate must match what the judges said about it (P3).
</adversarial_checks>

<orchestrator_gates>
These orchestrator steps run in this order, and the announcement lists them as checks. Its first step runs the gate-scope check from run-protocol.md's run-directory section before dispatch. A report step builds the report from the ledger after a clean `close` (P6).

1. **Scout and manifest**, before Understand: inventory every candidate source with counts, deduplicate by content hash, and write the included and excluded sources with a reason for each. Class each source as intent, outcome, or reaction evidence. Run the requirement-source scout (who asked, and where it was discussed), reading each source or asking for it. Run the gate-scope check, and announce the manifest, the unique counts, and the estimate.
2. **Briefing merge**, after Understand: write one briefing file with the open questions attached to their sections, passed by path. Settle only measured and read facts. A documented, placeholder, or inferred fact stays conditional in the unverified-premises block, the part of a brief that lists unsettled claims, and a deliverable states it with the probe that would settle it (C10). Start the flag ledger, a file that lists every narrowed claim, unverified note, and condition with its record id, and add to it each claim Verify narrows. Run the primary-source probe, a check against the system the claim is about, for every negative claim the verdict rests on (C10). Re-derive the three to five claims the verdict will rest on while the helpers run.
3. **Deliverable merge and flag-ledger pass**, after Verify: you or one merge writer merge the deliverable. A separately prompted pass then reads the flag ledger against it and reports each entry used unnarrowed or with its condition unmet, and every such entry blocks. The pass's accepted return carries one finding record per blocking entry, and the run leaves that record undisposed until the entry is resolved, so `close` exits nonzero while one stands (P6).
4. **Critic with its surplus read**, after the flag-ledger pass: a repository-grounded completeness critic and its paired surplus read both review the merged deliverable, and their gaps and uncontested removals fold into it before the check (C6).
5. **Check what ships**, after the critic: run the paired check on the merged deliverable (C1), and the same check on every later artifact built on the run. For an outbound message, that check runs before the send approval.
6. **Report**, after `close` on either exit: the report the **Report.** field describes, and when the exit is not clean it names each open entry that blocked the close and states in its opening sentence that `close` exited non-zero, as P6 requires.

Gates beside the steps. The gates count the helpers dispatched, returned, and accepted per phase. They count settled facts by tier, with only measured and read facts counted as settled. The ledger holds zero unresolved conflicts. The verdict distribution is not uniform: when every claim fell the same way, re-read the prompts for steering (C7, and `variants.md`, `## Calibration controls`).
</orchestrator_gates>

<failure_handling>
The acceptance gate, which is the check `accept` makes, runs before any brief uses a return. A placeholder earns one re-invocation, and a hollow return blocks the phase that depends on it.

At a turn end with rows out, send the interim report. Any later turn runs `status`, then `attach` when a run is open, and accepts every pending return before it continues (P4).
</failure_handling>

<stop_and_ask>
Requirement sources out of reach, and scope, go to the user. The user approves before any outbound send. A limit that a critic proposes and that trades against the user's stated aim is adopted only as a surfaced decision, after re-reading the case it cites.

Ask about scope and the estimate before dispatch, with the estimate beside any size guideline the host or user states, and ask before any widening past the enumerated list. An answer the request states is the user's answer. On a host with no later turn, an unanswered gate ends the run with its decision packet (P1). Create the stop file with `stop` the moment a pause request arrives, before any question (P4).
</stop_and_ask>

<report>
The report gives the tiers, with the provenance class of every number, and the unverified list with each claim's probe. It names the candidate the synthesis used, by id and score, lists the items added and removed with reasons, and states yield.
</report>

<cost_profile>
Keep these whatever else is cut: coverage by construction, a review of every landed write, and baseline-differential gates. Offer each cut only as a narrowing the user chooses, with the checks it drops. Estimate the cost as rows per phase, times the per-row cost the pilot measured, plus the checking share.

The cuts are drafters beyond three, which drop angles, and verifier rows for claims the verdict does not rest on, which drop secondary checks.
</cost_profile>

<tier_notes>
Inline floor: readers run as separate passes, with the briefing on disk. Batch delivery: one batch per phase, with independent phases in one wave. Notice delivery: re-derive the load-bearing claims while waiting inside the turn in `accept --wait` polls (P4).
</tier_notes>

<post_run_checks>
The coverage the lenses read matches the manifest, counting a path as read only where tool evidence shows a full read (C8). Every claim and number in the deliverable carries its tier, every fact below the read tier is stated as conditional with its probe, and no flag-ledger entry is used unnarrowed. Every shipped artifact has a check row, and the synthesis names its candidate by id.
</post_run_checks>

</research_synthesis>
