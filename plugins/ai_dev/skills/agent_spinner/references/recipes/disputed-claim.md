# J8. Disputed-claim settlement

<disputed_claim>

<trigger>
It runs under a two-refuter settlement check and applies only after the selector matched that shape.

Two passages of a source, or a source and its derived documents, disagree on a figure or claim, and the ask is to settle it, usually with an edit. A disagreement the ask only asks about is a read-only diagnostic. A disagreement the ask wants settled by an edit matches the two-refuter settlement check, and then this recipe.
</trigger>

<ledger_steps>
Keep your hypothesis, your own proposed resolution, out of the run directory until the deriver returns. Hand it to `brief` as withheld text when the deriver's brief is rendered, so only its hash enters the deriver's row. Write its text after the deriver returns.

Open the run with `init` over one sweep row per corpus. `snapshot` copies the sources, and every reading brief names those copies' paths. Give every alternatives entry, each alternative reading a refuter returns, a disposition with `dispose`, and surface each alternative to the user as a fork in the decision packet. The net diff audits the write set before `close`.
</ledger_steps>

<phases>
1. **Sweep**: a sweeper per corpus returns every occurrence with its provenance and reads no earlier return. Each occurrence carries its exact quote, its anchor, and a provenance class: finished prose, placeholder or to-do note, comment, or derived page. A sweeper's first search of the snapshot must find a token the brief names as present there (C4). When that control finds nothing, the sweeper reads each named file in full and reports the search as blind.
2. **Derive**: one blind deriver resolves the question from the sources (`variants.md`, `## Blind derivation`). It reads the sweep returns' provenance classes and never the hypothesis, and it returns its own resolution with its derivation.
3. **Refute**: two refuters test the proposed edit, reading the sweep returns and the proposed edit as before-and-after text, and their briefs exist only after the deriver returns. Each opens from the position that the edit is wrong or incomplete. Refutation covers a better-supported value, a rewording that keeps the value but changes what it refers to, and a value resting on placeholder content. Each refuter returns its alternatives with derivations and the provenance of every number the edit introduces, and a boolean-only return, a bare yes or no, is rejected.
</phases>

<width>
Sweep gets one sweeper per corpus, Derive one blind deriver, and Refute two edit refuters, with the count and its reason stated first.

A run whose context estimate crosses half the host's window spans sessions at wave ends (P1).
</width>

<roles_and_returns>
The sweeper returns occurrences with provenance. The deriver returns its resolution and derivation. The refuter returns a verdict, alternatives with derivations, and the provenance of each number.

A role barred from file writes returns in its final message, which you relay verbatim to `accept --stdin`, never through a shell (P3).
</roles_and_returns>

<adversarial_checks>
Replicated draws, several runs of one identical prompt, are reported unreduced (`variants.md`, `## Replicated draws returned unreduced`). A seeded confirmation, one whose brief carried the claim, counts as recall-confirmed.
</adversarial_checks>

<orchestrator_gates>
These orchestrator steps run in this order, and the announcement lists them as checks. Its first step runs the gate-scope check from run-protocol.md's run-directory section before dispatch. A report step builds the report from the ledger after a clean `close` (P6).

1. **Hypothesis hash**, before Sweep: settle your hypothesis and keep its text out of the run directory, so it reaches the ledger only as the hash that **Ledger steps.** describes.
2. **Decision packet**, after Refute: every alternative and every placeholder-sourced number goes to the user as a fork with a recommendation. A number settles only when it is measured, or read in finished prose of the source the claim is about. A number from a placeholder or to-do note, a comment, or a derived page stays conditional (C10). Writes stay blocked behind any gate you announced.
3. **Write and net-diff audit**, after the user answers: apply the edit, then run the net-diff audit against the committed baseline. Flag metadata-only changes, such as a changed date with no other change, and revert or explain them. Check that a log entry's file list equals the net diffstat, and then run the paired check over the diff.
4. **Report**, from the ledger after a clean `close`.

Gates beside the steps. The gates are the net diff and a check that no marker added and removed within one run leaves a date-only change.
</orchestrator_gates>

<failure_handling>
On a host without a schema for helper returns, use the validated template with one re-ask (P3).

At a turn end with rows out, send the interim report. Any later turn runs `status`, then `attach` when a run is open, and accepts every pending return before it continues (P4).
</failure_handling>

<stop_and_ask>
Write nothing before the user answers while any alternative or placeholder-sourced number exists.

Ask about scope and the estimate before dispatch, with the estimate beside any size guideline the host or user states, and ask before any widening past the enumerated list. An answer the request states is the user's answer. On a host with no later turn, an unanswered gate ends the run with its decision packet (P1). Create the stop file with `stop` the moment a pause request arrives, before any question (P4).
</stop_and_ask>

<report>
The report puts each checker on its own line with its derivation and its ledger tag: recall-confirmed where its brief relayed the claim, and independently surfaced otherwise. Reserve "confirmed" for a resolution surfaced independently or re-derived against the source, and split the confirmations into recall-confirmed and independently surfaced. Label the derivation blind by prompt unless the log audit shows otherwise, and give the provenance class of every number.
</report>

<cost_profile>
Keep these whatever else is cut: coverage by construction, a review of every landed write, and baseline-differential gates. Offer each cut only as a narrowing the user chooses, with the checks it drops. Estimate the cost as rows per phase, times the per-row cost the pilot measured, plus the checking share.

The cut is the second edit refuter, taken as a `<coverage_tradeoff>` narrowing rather than a second allowed width: it drops the second independent look at the edit, and the run puts the narrowing to the user before the refuters' briefs exist, naming the alternatives and placeholder-sourced numbers that look would have surfaced, and takes the cut only on the user's word.
</cost_profile>

<tier_notes>
Inline floor: run the blind derivation first, before the hypothesis text exists in the run directory, and state its residual recall, because one context holds both. Batch delivery: sweep, derivation, and refutation go out as separate batches, and the refuters' batch waits for the deriver's accepted return. Notice delivery: render the refuters' briefs once the deriver's return is accepted, and poll inside the turn with `accept --wait` (P4).
</tier_notes>

<post_run_checks>
The deriver's brief carries no hypothesis text, the roster held only its hash until the deriver returned, and the report labels the derivation blind by prompt unless the log audit shows otherwise. Every number traces to finished content or a measurement, or carries its provenance class and a fork. No write landed between an announced fork and the user's answer, and the log's file list matches the net diffstat.
</post_run_checks>

</disputed_claim>
