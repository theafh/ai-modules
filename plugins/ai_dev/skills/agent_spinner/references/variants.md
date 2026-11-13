# Lower-frequency variants

Six ways to run helpers that earn their cost rarely: keeping concurrent helpers
isolated, returning replicated draws unreduced, deriving an answer blind, running
a balanced challenge over two costs, firing calibration controls, and splitting a
hypothesis into its readings. Reach for one when the run's specific failure mode
calls for it, rather than by default, and follow the recipe that names it where a
recipe applies it.

## Information isolation between concurrent helpers

**When.** Two or more helpers work the same question at once and the run needs
their looks to stay independent, because a shared intermediate turns two
independent looks into one look plus an echo.

**How.** Give each helper the source material and its own brief, and give it
nothing a sibling produced. Withhold sibling identities, sibling counts, and
any running tally. Where a helper needs a fact a sibling also derived, hand it
the source span rather than the sibling's rendering of it.

**Cost.** Isolation buys independence and spends re-derivation: each helper
pays again for the same reading. Spend it where the independence is the point,
such as a paired refute-by-default check, and skip it where a shared preamble
keeps the passes consistent, because only a fact measured against the primary
system, or read in finished content of the artifact the claim is about, settles
(C10). Documentation-derived, placeholder, and inferred facts stay conditional
in every pass. Report an isolated pass as blind by prompt, and as blind only
where an audit of the host's helper logs, at a path the caller supplies, shows
no read outside its admitted inputs (C2).

**Return.** Each helper returns its own findings with its own citations. The
orchestrator unions them and sends each through its own check, because two
isolated helpers agreeing still measures shared priors rather than truth.

## Replicated draws returned unreduced

**When.** One indivisible factual or arithmetic claim carries the verdict, and
a single draw's variance is the risk. `<width>` reserves replication of an
identical prompt for exactly this case.

**How.** Send the identical prompt N times, with N stated before dispatch.
Ask each draw to show its own derivation: the span it read, the steps it took,
and the value it reached.

**Return.** Report the draws unreduced, one line each, with its derivation. A
majority, an average, or a "3 of 5 agree" line is the reduction this variant
exists to avoid, because agreement among draws of one model measures shared
priors rather than confirmation. A draw whose brief carried the claim counts as
recall-confirmed (C7).

**Reading the result.** Draws that agree and derive the value the same way
raise confidence in the reading. Draws that agree by different derivations are
the stronger signal. Draws that disagree hand the orchestrator a real fork:
re-derive the claim against the source, and report which derivation the source
supports.

## Blind derivation

**When.** The orchestrator's own claim, a pivotal number, a built design under
challenge, or a user's hypothesis carries the verdict.

**How.** One pass derives the answer from the question and its sources before
it can see the claim. Where the claim is a change in the working tree, the pass
reads `snapshot --base` copies of the base commit. Where the claim is text, such
as a hypothesis, preference notes, or withheld verdicts, that text enters the
run only through `brief`'s withheld-text input, and it is written out after the
pass returns (P2). The pass reads each named file in full or searches it by
explicit path (P5).

**Return.** Its own resolution with its derivation, labelled blind by prompt
(C2).

**Reading the result.** At the inline floor, run the blind pass first, before
the withheld text exists, and state its residual recall, meaning what the shared
context may still have shown it.

## Balanced challenge

**When.** A trade-off between two costs, such as a merge against a split, or a
change against the status quo.

**How.** One challenger per side under a symmetric stance, the user's objective
in the user's own words in each brief, and a status-quo cost beside each
proposal (C2).

**Reading the result.** Each challenger argues its own side at full strength,
because a reject-by-default stance on a two-cost question lets the status quo
win by construction.

## Calibration controls

**When.** A stage whose verdicts carry the decision, or a search whose empty
result would count.

**How.** Fire every count and search on a known positive before an empty result
counts (C4). In a search of a snapshot, the brief names a token present in the
copies, and a search that misses it falls back to full reads reported as blind,
as `option-panel.md` and `disputed-claim.md` apply it. Each verify batch carries
a known-false control, a planted finding a sound verifier refutes, and each
unverified band gets a fixed sample (C7).

**Reading the result.** A stage over more than a handful of items at 0 or 100
percent refutation is non-discriminating, and its information lies in its
narrowings and surviving forms. A uniform verdict distribution sends the
orchestrator back to the prompts for steering (C7).

## Splitting a hypothesis into its readings

**When.** The request carries a hypothesis or floats an option.

**How.** Split it into its distinct readings, brief each as an option or claim
of its own, and keep the hypothesis text out of any blind pass's workspace until
that pass returns.

**Return.** The decision packet states each reading's fate: ruled out, collapsed
into another option, or survived (P6).
