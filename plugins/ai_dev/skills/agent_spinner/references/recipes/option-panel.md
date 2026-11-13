# J5. Design option panel

<option_panel>

<trigger>
It runs under a lens panel and applies only after the selector matched that shape.

The ask weighs design options, challenges a built but uncommitted design, or adds a public surface or rules out a competing mechanism. A challenge to a built design matches this recipe under the same lens-panel shape, because the design is the one subject its lenses read and its Refute phase supplies the adversarial read. A question why one mechanism and not another, about a mechanism not yet built, is a single judgement question answered inline, unless the ask requests options.
</trigger>

<ledger_steps>
Open the run with `init` over one Design row per designer. Every designer brief lists the same options, with each reading of the user's hypothesis among them, where a reading is one distinct interpretation.

Create the blind base snapshot with `snapshot --base` over the tracked paths in the candidate's footprint, and name its file paths in every designer brief, so the designers see the files as they stood before the candidate change. Sighted judges and refuters, who may see the change, read a `snapshot` of the working tree.

Hand your preference notes to `brief` as withheld text, so only their hash enters the designer rows. The refuters' numbered claims become ledger records, and you build the decision packet from those records, read through `show`.
</ledger_steps>

<phases>
1. **Design**: three to five blind designers each write options over the base snapshot and read no earlier return (`variants.md`, `## Information isolation between concurrent helpers` and `## Blind derivation`). Each returns a fixed template: a verdict on the shipped mechanism and, for each option, why it wins or loses, its cost, its coverage regression, and its preferred end state. A coverage regression is coverage the option would lose, and a preferred end state is the outcome the designer would choose. Where claims can be executed, the designer builds the candidate in its own scratch copy of the base snapshot under the run directory, runs the existing suite unmodified, and reports the measured numbers. A designer's first search of the base snapshot must find a token the brief names as present there (C4). When that control finds nothing, the designer reads each named file in full and reports the search as blind.
2. **Judge**: a judge per criterion scores the full candidate set, reading every designer return by path against the repository. It scores on an anchored scale with a one-line definition per point, ranks at most three fatal flaws with a span each, and states the strongest argument against its own verdict.
3. **Refute**: lens-split refuters, one each for facts, reasoning, and consequences, test the judges' leading claims, reading the judges' returns.
</phases>

<width>
Design gets three to five designers, Judge gets one judge per criterion (two to four), and Refute gets three refuters. One critic runs with one surplus read.

A run whose context estimate crosses half the host's window spans sessions at wave ends (P1).
</width>

<roles_and_returns>
The designer and the judge return as their phases state. The refuter returns numbered claims, each with a verdict and a citation, plus its corrected recommendation verbatim. The critic returns gaps with file-and-line citations and paste-ready fixes.

A role barred from file writes returns in its final message, which you relay verbatim to `accept --stdin`, never through a shell (P3).
</roles_and_returns>

<adversarial_checks>
Read the refuters for their reasons: number every load-bearing claim, and re-derive each with shown output. A refuter's brief defaults its verdict flag to refuted, so the flag carries no information, and no survival vote comes from it. Support counts as convergence only when every preferred end state matches. The decision rests on re-derived claims and surviving forms, meaning each claim in the form that survived refutation, and the scores appear in the report as context.
</adversarial_checks>

<orchestrator_gates>
These orchestrator steps run in this order, and the announcement lists them as checks. Its first step runs the gate-scope check from run-protocol.md's run-directory section before dispatch. A report step builds the report from the ledger after a clean `close` (P6).

1. **Scout**, before Design: write the settled facts by tier (C10), meaning the baseline numbers the design addresses, each caller and the options it passes, and any precedent. Derive the candidate's footprint, the files it touches, from the modified and untracked set, then run `snapshot --base` over the tracked paths among them, because `snapshot --base` reads each path at the base commit and stops when the base commit lacks it. Confirm through the ledger's `search`, with its positive control fired, that the base snapshot holds zero hits for the candidate's distinctive tokens (P5). This shows that the blind copies lack the candidate.
2. **Framing and the scope question**, before Design: split the user's hypothesis into its distinct readings and brief each as an option of its own (`variants.md`, `## Splitting a hypothesis into its readings`). Describe the shipped mechanism neutrally, give every option the same fields, record who wrote the descriptions, and leave out selling points. Add an invite-your-own option, a slot for a designer's own proposal, and one angle arguing the change is the wrong call. Keep your preference notes out of the workspace until the designers return, and put scope and the estimate to the user.
3. **Critic with its surplus read**, after Refute: a repository-grounded completeness critic plus a surplus read (C6).
4. **Decision packet**, after the critic (P6): the packet lists each option with its supporters by role, each helper's preferred end state verbatim, and the option's strongest recorded objection. It lists every reconciling variant a helper proposed, meaning an option that reconciles the others. It states the fate of each reading: ruled out, collapsed into another option, or survived. After the choice, the chosen option's objections enter the follow-up item, each with a disposition. The run asks once before writing when an unaddressed objection narrows a blocking check.
5. **Report**, from the ledger after a clean `close`, before any build hand-off.
6. **Build hand-off**: when the ask includes building, run `multi-file-task.md` with the paired check over the diff.

Gates beside the steps. Every comparison is non-vacuous, meaning both sides ran and met their expectation (C4). Measured numbers are compared across helpers in the open, and any mismatch is reported. A base-snapshot check runs before dispatch, and a spot-check of one blind helper's commands runs afterwards.
</orchestrator_gates>

<failure_handling>
A missing designer earns one re-invocation. A judge whose tool evidence shows less than a full read of the candidate set violates its contract (P3, C8).

At a turn end with rows out, send the interim report. Any later turn runs `status`, then `attach` when a run is open, and accepts every pending return before it continues (P4).
</failure_handling>

<stop_and_ask>
Ask about the readings before dispatch, at the decision, and before building when a cheaper or safer alternative surfaced.

Ask about scope and the estimate before dispatch, with the estimate beside any size guideline the host or user states, and ask before any widening past the enumerated list. An answer the request states is the user's answer. On a host with no later turn, an unanswered gate ends the run with its decision packet (P1). Create the stop file with `stop` the moment a pause request arrives, before any question (P4).
</stop_and_ask>

<report>
The report gives the menu of options with its objection lines, each reading's fate, claims marked re-derived or taken on a helper's word, and yield. Label the designers `blind by log` where `accept --log` with `--log-format` over the host's helper transcript, at a path the caller supplies, finds no read outside the pass's admitted inputs and no ledger or spawn call, and `blind by prompt` otherwise (C2).
</report>

<cost_profile>
Keep these whatever else is cut: coverage by construction, a review of every landed write, and baseline-differential gates. Offer each cut only as a narrowing the user chooses, with the checks it drops. Estimate the cost as rows per phase, times the per-row cost the pilot measured, plus the checking share.

The cuts are designers beyond three, which drop angles, and criteria beyond two, which drop judged dimensions.
</cost_profile>

<tier_notes>
Inline floor: designers run as separate passes over the base snapshot, and the report labels the blindness recall-limited, because one context holds every pass. Batch delivery: one batch per phase. Notice delivery: the judges wait on every designer row, polled inside the turn with `accept --wait` (P4).
</tier_notes>

<post_run_checks>
The base snapshot shows zero candidate tokens through `search`, and every option has at least one analysis and an objection line. No preference note existed in the run directory before the designers returned, and the roster held only its hash. The follow-up item names each objection against the chosen option, and each reading's fate is stated.
</post_run_checks>

</option_panel>
