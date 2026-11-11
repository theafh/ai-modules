<!-- markdownlint-disable MD026 -->
<!-- The ten check headings are contract text: the C1..C10 titles carry their
     closing period, and other skills cite them by number and title. -->

# Checks

This reference is the procedure behind the checking rules in `SKILL.md`. It
holds ten checks, C1 to C10, in the order a run meets them. Each check states
when it runs, the numbered steps that carry it out, and a **Checks** line
naming the facts a reviewer can verify against the run's own files.

The run protocol's six parts are P1 to P6; cite them by that label alone.

A few terms recur below. `init` opens a run and records the baseline, the state
of the tree at the start. A row is one helper job in the ledger, such as a
writer row or a check row, and the roster lists every row. A producer is the
helper whose work a checker tests. A refute-by-default check starts from the
position that the work is wrong and concedes only after its checklist. A gate
is a deterministic command, such as a linter, that `gate` runs and records. A
narrowing is any reduction in what the run checks, and the report names every
narrowing.

## C1. Check every landed write.

**Trigger.** Any write lands: a helper's file, the orchestrator's merge or
inline edit, a remediation, a filing, a split, a repoint, a regeneration, or an
outbound draft under `outbound/`.

1. Run `diff` so every path's net change is measured against the baseline,
   untracked files included. It attributes each change to a writer row, the
   orchestrator, or an outside source.
2. Run `diff --add-checks` so each changed path gets a check row. A diff that
   changes a claim gets one read-only checker. Gates cover pointer-only hunks,
   which change only paths, identifiers, link targets, or slugs.
3. Give a set whose every hunk is a glyph-for-glyph substitution a sampled
   checker set only on the user's word.
4. Write the checker's brief by path. It names the producer's return, the
   brief or approved-edit list or acceptance list, the per-file diff under
   `diffs/`, and its snapshot copy.
5. Carry two standing lines in every checklist. First, every hunk maps to a
   brief line or an approved-edit id, and every approved id maps to at least
   one hunk. Second, no hunk introduces a defect the repository's rules ban,
   such as a lost claim, hedge, contrast, number, link, or attribution, or a
   format violation.
6. Land an approved edit set as anchored replacements keyed by edit id, with a
   whole-file regeneration only where an edit needs one. Run
   `diff --approved-edits` to map each changed block.
7. Revert or route an unmapped hunk as a new issue, then run the check once
   more.
8. Give the orchestrator's own writes check rows too, and give an append-only
   record a post-write assertion. The orchestrator never certifies its own
   inline work.

**Checks.** `close` refuses while a changed path lacks an accepted check from
another row, a covering gate, or an unverified disposition.

## C2. Build a clean checker.

A checker's brief carries nothing that could steer its verdict.

1. Aim the check at the artifact or edit that will ship. Copy the checklist
   verbatim from the artifact's acceptance contract, one line per item.
2. Write each line to test that the required form is present on every governed
   surface and that the old form is absent.
3. Split compound findings into atomic claims, and treat a recommendation's
   direction as a claim.
4. Use the closed verdict set: confirmed; narrowed, with corrected wording
   that propagates; refuted, with its settling span, the quoted text that
   settles it; and right diagnosis with a different fix.
5. Use the closed confidence set: high, a settling span the checker read;
   medium, a partial or indirect span; and low, inference the checker states.
   Tag every finding with one.
6. Give every alternatives entry a disposition.
7. Keep out of the brief any expected verdict, preference, prior-round digest,
   or orchestrator-authored repair rule, so an idea of the orchestrator's
   enters as a labelled proposal.
8. For the orchestrator's own claim or a pivotal number, derive the answer
   blind from the question and the sources in one pass, and keep the claim out
   of the workspace until that pass returns.
9. Report a blind or isolated pass as "blind by prompt", the label for a pass
   kept blind by withholding text from its brief. Report it as blind only when
   the host's helper logs, read at a path the caller supplies, show no read
   outside its admitted inputs. A helper that runs the ledger breaches
   containment, and the same log reading catches it.
10. Give a trade-off one challenger per side under a symmetric stance. Test
    each challenger against the user's objective in the user's own words, with
    a status-quo cost beside each proposal.
11. Keep a re-gate, a repeated run of a gate, to its admitted inputs, with
    transcript and state directories off limits.
12. Count a verdict that read an earlier verdict as recall-confirmed, and
    re-run it once in isolation. That re-run's brief names none of the earlier
    verdicts, and the re-run carries the blind-by-prompt label unless the logs
    show no read of them.
13. Give the last clean draw of a repeated gate, meaning its last passing run,
    one refute pass whose clears rest on external evidence.

**Checks.** Checklist lines at least match the acceptance items in number, the
brief lint finds no steering phrase, every orchestrator claim has a blind pass,
every return carries an alternatives list that may be explicitly empty, every
alternatives entry has a disposition, and every blind or isolated pass carries
its label.

## C3. Hand off verbatim and unsteered.

Each checker reads the producer's own words.

1. Keep producers' returns and gate verdicts in their files, and have checkers
   read them in full by path. A checker brief holds no paraphrase.
2. Head a checker brief with a routing summary only when it is labelled as
   routing, with the verbatim material following.
3. Give a pasted payload a stated cap, a truncation notice, and its trimmed
   identifiers, and have the pass re-read load-bearing detail from the source.
4. Quote the issue sentence each approval resolves and the sentence each
   rejection was measured against.
5. Have the writer apply only bytes the checker saw, keyed by edit id.
6. Read returns by P6's reading rule, which reads every record that needs
   judgement in full, and never cut them by character offset.

**Checks.** Every producer return appears in its checker's brief by path or
verbatim, a spot diff of one proposal against the checker's input shows no
loss, and the applied text equals the approved text.

## C4. Run deterministic gates against the baseline, with positive controls.

**Trigger.** At `init`, and after every later run of a named gate.

Every gate result is a measured comparison between the baseline and the final
tree. A positive control is a known positive, a planted case the gate must
report, so that an empty result means something. At `init` the ledger plants
one such file per file type the gates read.

1. Run every named gate on the baseline and on the final tree, and report
   baseline-to-final deltas per category, warnings included.
2. Treat a gate's baseline as a snapshot copy of the base commit overlaid with
   the baseline copies of files modified at the start. Run a baseline gate with
   that snapshot copy as its root, and apply the path filter, which drops
   findings under the run directory, only outside that root.
3. Keep a gate that did not report the planted file at `init` with its `init`
   run as its baseline.
4. Run each command as `gate NAME -- ARGV` with an expectation: `exit0` records
   a silent pass as silent, `nonempty` fails on empty output, and `count` needs
   a counter whose positive control passed.
5. Name a gate whose executable does not resolve as unavailable, which the
   report names as a narrowing. Where a gate the recipe relies on is
   unavailable, widen checker coverage to every changed file or ask the user.
6. Fire every self-written count first on a known positive through
   `diff --count` and record that it did. Take patterns from a file and count
   them in Python, with no shell-quoted alternation, and follow the shell floor
   `harness_portability` states.
7. Print both sides' exit status and summary line for a comparison, and let
   equality stand only where both sides met their expectation.
8. For prose, count per file the modal and requirement words, hedges, numbers,
   links, quoted strings, negation and contrast markers, dashes, and character
   growth. Judge each count against the direction the rule explains, and run a
   wrap-seam detector.
9. Mirror the writers' preserve list, the text writers must leave unchanged, in
   the gate exclusions, and keep the change's own vocabulary visible in the
   filters. State a sample's size, and let it support only a claim about the
   sample.
10. Run the change-specific gates: move integrity with status and similarity,
    the anchor re-grep, append-only assertions, and date-only change
    detection. Send capture hashes to the owning family's gate (C9).

**Checks.** Every gate line carries its expectation, resolved executable, exit
status, and baseline and final values, every zero has a passing control, and
every gate that sees the run directory carries the path filter or a narrowing.

## C5. One repair round with one re-check.

**Trigger.** Any item fails verification.

1. Put every item that failed verification in the repair list, whatever
   verdict word the checker used, including each instance a confirmed class
   sweep found (C8). Each enters repair once.
2. Pass findings bound for a writer through a refute-by-default check first.
3. Have a remediator, the helper that makes repairs, re-derive each finding and
   return applied, refuted with its span, or routed.
4. Give a repair pass that refutes none of many findings a spot
   re-derivation.
5. Re-check each repaired item once, at no lower depth than its first check,
   against a snapshot copy taken before the repair.
6. Report a pass as re-checked once, recall-limited, and unverified end to end,
   and a fail as failed after repair.
7. Wait for the user's word before a second round.
8. Guard a follow-up fan-out on its count, so it dispatches only when its list
   holds items.

**Checks.** The repair list equals the failed items plus the confirmed
class-sweep instances, each repaired item has one re-check row at no lower
depth than its first check, and at most one round runs without the user's word.

## C6. Aim critics at the run's own conclusions.

**Trigger.** A finished body needs a what-is-missing read.

1. Have a completeness critic read the earlier passes' coverage records and
   propose a capped number of gap units, which run through find and verify. A
   gap unit is one missing item, written as a full brief.
2. Pair every completeness critic with a surplus read that names what to
   remove, turning restated rules into citations. Put a contested removal of
   load-bearing content to the user.
3. Divide scout critics three ways. A scout is the pass that surveys the items
   before dispatch. One critic refutes every item the scout called current, one
   reads recent commits for landed work no item accounts for, and one scans
   outward from the touched code.
4. Before any contract repair, have a sibling-surface enumerator list every
   surface that carries the same contract.
5. Give a design a repository-grounded critic with read access and a charge
   list of named mechanisms, platform limits, collisions with shipped siblings,
   required test surfaces, and cost. Re-derive every disqualifying gap it names.

**Checks.** Every retained item maps to the brief and to an acceptance check,
gap units have rows, and disqualifying gaps were re-derived.

## C7. Set verification scope, depth, and calibration.

**Trigger.** Before dispatch, and again at every stage that reports a rate.

The run states how much it verifies, and controls show whether its verifiers
can catch a false finding.

1. State the verification scope, its estimate, and any narrowing before
   dispatch, and verify every finding that drives a write.
2. Fix a small random sample of each band left unverified before dispatch. A
   band is a group of findings, such as one severity level.
3. Report that sample's refutation and re-tiering rates, and put widening to
   the user with its cost.
4. Report each stage's refutation and narrowing rates. Call a stage over more
   than a handful of items at 0 or 100 percent non-discriminating, with its
   information in its narrowings and surviving forms.
5. Give each verifying stage one known-false control, a planted finding that
   its quoted source contradicts. A verifier that confirms the control fails,
   and its batch is re-verified under a different framing.
6. Hold checker depth at or above the producer's. Where no depth control
   exists, state rigour as behaviour in the brief: read each rule's full text,
   cite a span per line, and name the minimum reads.
7. Record requested model and effort from `dispatch` and observed values from
   `accept` in the roster. Let `close` flag every checker below its producer's
   depth, name each flag in the report as a narrowing, and list both values per
   role.
8. Choose a checker role whose contract is review.
9. Reserve "independent" for passes that shared neither the claim nor its
   framing. Report replicated draws unreduced, so each run of a repeated prompt
   keeps its own result.
10. Apply the survival labels `<confirmation_provenance>` states, with the
    tally splitting confirmations by the tags `accept` recorded.

**Checks.** Rates are reported per stage, every row records requested and
observed model and effort with each checker below its producer flagged, and
unverified counts and the confirmation split come from the roster.

## C8. Sweep residuals and classes, and check receipts.

These rules find what a diff-scoped check missed, and they test whether helpers
read what they claim to have read.

1. After a diff-scoped check, which looks only at the changed hunks, sweep the
   target class across every in-scope item on the final tree, edited or not,
   under the writers' exclusions. The target class is the kind of text the
   change targets, such as an old term.
2. Classify each residual, each instance the sweep still finds, as kept, citing
   its rule or class, or as missed.
3. Enumerate every instance of a confirmed finding class, or of a class the
   user ruled borderline, across the scope, each with a disposition.
4. Take a read receipt of its path and one verbatim line for every mandated
   input. `accept` checks each receipt against the input version its row
   recorded, never against the live file. That version is the baseline copy for
   a writer's target and the snapshot for a reader.
5. Earn one re-invocation for a mismatched receipt, then report the unit
   unreviewed.
6. State, criterion by criterion, what an empty return examined and the span
   that cleared it.
7. Quote the text that settles the line, with its anchor, for a settling span.
   A heading or an anchor alone cites no span, and its clear routes back once
   like an uncited one.
8. Where the stakes justify it, have an isolated second reviewer probe some
   clean units, and report units as clean with citation, clean after the probe,
   or unreviewed.
9. Count a path as read only where tool evidence shows a full read. Tool
   evidence is a full read of that path in the helper's log, at a path the
   caller supplies, or your own full read at the inline floor, where one
   context runs every pass. Where no log is reachable, report the path as
   claimed by receipt and unverified by tool evidence, which is a narrowing.
10. Pair receipts with the class re-sweep, which is the recall check.
11. State which claims each check clears:

    | Check | Claim it clears |
    | --- | --- |
    | a presence check | the required form at the surfaces it searched |
    | a count with a passing control | the count |
    | a header or structure check | the structure |
    | a sample | claims about the sampled items |
    | a reader comparing a diff with its source | meaning, for the hunks it read |
    | a class sweep | a universal claim over its scope |
    | an external clear, a measurement against the primary system | a claim about the world outside the repository |

12. Keep a presence, count, header, or sample check from clearing a meaning or
    universal claim.

**Checks.** Every in-scope item has a residual entry, no class grep finds an
instance ruled against its class, every receipt is found in its row's recorded
input version, and every path counted as read has tool evidence or appears as
claimed by receipt.

## C9. Hand stamps, completed artifacts, and markers to their owners.

**Trigger.** A target carries a stamp or marker, or is already complete.

A stamp is a status that a skill family's gate writes, such as a task's
`ready`. A marker is a persistent record of progress, such as a wiki audit
baseline. The owning gate is the step of the owning family that writes the
stamp or marker.

1. Record at `init` which targets carry a stamp or marker, as the owning family
   reports them.
2. Treat a completed artifact as read-only to the run, and send it to its
   audit, its close-out, or a follow-up item.
3. Route every write to such a target to the owning gate by name, or to the
   user as a fork, a decision the user makes. Do so before dispatch, whatever
   the write changes.
4. Start an artifact the run creates at its initial state, and have no pass
   write a post-gate status on it.
5. Advance a persistent marker only over what the run examined.
6. Hand each stamp, capture hash, audit baseline, and index or log entry to the
   owning family's gate by name.
7. Pass that gate the paths tool evidence shows read in full (C8), and list
   beside them each path claimed only by receipt, marked unverified.
8. Check only its own rows, and leave family file formats with the family.

**Checks.** Every changed path recorded as stamped has a routing or fork row,
whatever the write changed, and every marker hand-off counts as read only paths
with tool evidence of a full read.

## C10. Tier the evidence and keep weak claims conditional.

**Trigger.** Every fact that enters a brief, a deliverable, or an outbound
draft.

Every fact carries a label for where it came from.

1. Tag every fact in a brief, a deliverable, and an outbound draft with its
   tier. The five tiers are measured (a command run against the primary
   system), read (finished content of the artifact the claim is about),
   documented (docs, wikis, notes, other projects' guides, and declarations
   such as a retention setting), placeholder (to-do notes, templates, and
   future-phase outputs), and inferred.
2. Let only measured and read facts enter the preamble as settled, and give
   every number its tier.
3. Put a documented, placeholder, or inferred fact in the unverified-premises
   block, the preamble's list of unconfirmed claims. Have checking passes test
   it, and have a deliverable state it with the probe that would settle it,
   such as a command or a read.
4. Keep a negative or availability claim below the read tier conditional with
   its probe, or run that probe first through a vetted read-only script.
5. Hold back a section whose primary-source probe failed, or write it as
   conditional.
6. Put upstream caveats into the checking brief of any claim that rests on
   them.
7. Give a premise about how people or systems currently work its source and
   scope, and label an unconfirmed one assumed.
8. Treat helper-derived material in a later brief as a hypothesis the helper
   verifies, with a brief-corrections slot.
9. Search every open draft for a premise the orchestrator conceded as false
   before the next hand-over.
10. Let the report lint flag an absolute claim whose backing fact sits below
    the read tier.

**Checks.** Every settled fact in the preamble is measured or read, no negative
claim below the read tier stands without a condition, and every unprobed claim
appears on the unverified list with its probe.
