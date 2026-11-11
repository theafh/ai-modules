# Role prompt templates

This reference holds the prompt template for each role the shapes name. Every
template opens with the pass's first concrete action and states each
prohibition as something the pass does. A role body can arrive inside the user
turn with no authority over the conversation around it, so each contract is
written as actions the pass performs in its own turn.

The invariant preamble, the access block, and the closing block wrap every
template. `brief` renders them from files in the run directory.

## Invariant preamble

Reused unchanged across producing and checking passes. Fill the bracketed
slots once per run, and tag every settled fact with its evidence tier.

```text
Read [the run's request, intent, and orient records] before writing anything.

Vocabulary: [the three to six terms this run keys on, one clause each].

Severity ladder, highest first: blocker (the artifact is wrong or unusable),
major (a stated requirement goes unmet), minor (a real defect that changes no
decision), note (an observation worth recording).

Settled facts, each tagged measured or read with its source:
- [measured] [the fact, the command that measured it, and the value it
  returned].
- [read] [the fact, the artifact whose finished content states it, and the
  span].

Unverified premises, each tagged documented, placeholder, or inferred, with
the probe that would settle it:
- [documented] [the claim, its source, and the read or command that would
  settle it].
- [placeholder] [the claim, the note it comes from, and its probe].
- [inferred] [the claim, what it was inferred from, and its probe].

Return your result in the shape the brief below names. Perform your own item
and delegate no part of it; work you cannot complete comes back as an
out-of-scope finding.
```

## Access block

One per phase. It names what the pass reads, what it writes, and the reaches it
forgoes.

```text
Open only the paths this brief names, and read each one in full.

Read: [the input paths, with the snapshot copy of each under the run's
snapshot directory].

Write: [the one return path, and the one target path where this pass holds a
write grant].

Read-only operations: [the named operations this pass may use].

Forgo: [the reaches this pass leaves alone, as P5 names them, such as network
access, credentials, other helpers' transcripts, and the ledger].
```

## Closing block

`brief` appends this block to every brief. It carries the return channel, the
route by which the return reaches the orchestrator, and the END line.

```text
Return your result through [the return channel: write returns/<label>.md as
your last act, or end your final message with the block].

Route: [how the return reaches the orchestrator].

End with: END [label]

Repeat the brief token: [token].

Delegate no part of your item; perform your own item.

Bound: [the wall-clock bound in seconds].
```

## Producing pass

```text
Read [the one target path], then read [CHARTER.md or the named boundary
document] where the repository carries one.

[invariant preamble]

[access block]

Your target path: [exactly one path].

Situation: [what stands at that path today].
Target state: [what it reads like when this item is done].

Write only [the one path]. Leave these untouched: [the neighbouring artifact
classes]. Check your planned edit against the boundary document first; on a
conflict, write nothing, leave the file byte-for-byte unchanged, and report the
conflict.

Finish within [the wall-clock bound].

Return: a fenced JSON block with these keys, in this order: `label`, `brief`,
`status`, `verdict`, `examined`, `checklist`, `findings`, `forks`,
`beyond_brief`, `incidents`, `own_authority`, `alternatives`,
`brief_corrections`, `dropped_suspicions`, `notes`. Give each `examined` entry
the `path`, `how`, and the verbatim `receipt` line C8 requires for that path.
Add the item identifier [role:item] and what you changed as extra keys.
```

## Lens pass

```text
Read [the identical corpus every lens reads] under the lens named below.

[invariant preamble]

[access block]

Your lens: [lens name]. The question it asks: [one sentence].

Sibling passes cover the other angles, so spend your effort on depth under
this lens rather than breadth across the others.

Return: a fenced JSON block with these keys, in this order: `label`, `brief`,
`status`, `verdict`, `examined`, `checklist`, `findings`, `forks`,
`beyond_brief`, `incidents`, `own_authority`, `alternatives`,
`brief_corrections`, `dropped_suspicions`, `notes`. Put findings under this
lens only in `findings`, each with its verdict, confidence, quote, anchor, and
severity. An empty `findings` list is a valid and expected result.
```

## Checking pass

```text
Read the producer's return at [path] in full, then read [the artifact] and its
per-file diff under [the diff path].

[invariant preamble]

[access block]

Open from this position: the work is incomplete or wrong. Concede it only
after running this checklist, and cite the span that settled each line:

1. [check one]
2. [check two]
3. [check three]

Carry these two standing lines in every checklist. First, every hunk maps to a
brief line or an approved-edit id, and every approved id maps to at least one
hunk. Second, no hunk introduces a defect the repository's rules ban, such as a
lost claim, hedge, contrast, number, link, or attribution, or a format
violation.

A clean verdict that cites no span routes back for re-checking, which costs the
run another pass, so weigh the citation you give rather than reaching for the
clean line. Narrow an overstated claim to what the artifact supports instead of
killing it, and carry the narrowed wording into your return.

Work read-only, using [the named read-only operations]. Where running a
command needs approval rather than being refused outright, stay clear of shell
use and read the files directly.

Return: a fenced JSON block with these keys, in this order: `label`, `brief`,
`status`, `verdict`, `examined`, `checklist`, `findings`, `forks`,
`beyond_brief`, `incidents`, `own_authority`, `alternatives`,
`brief_corrections`, `dropped_suspicions`, `notes`. Put a verdict and its
citing span per checklist line in `checklist`, the findings in `findings`, and
the narrowed wording in `notes`.
```

## Synthesis pass

```text
Read the returns at [paths] in full, keyed by item identifier.

[invariant preamble]

[access block]

[digests, capped at [N] characters each, with the trimmed identifiers listed]

Your material may have been cut at that cap. Re-read anything load-bearing
from the source at [corpus pointer] rather than resting on the digest. These
identifiers had detail trimmed: [identifiers].

Union the proposals: two passes raising the same item is shared priors rather
than confirmation, so keep each proposal and send it through its own check.
Join and partition by item identifier rather than by arrival order. Keep every
discarded finding with its one-line reason.

Return: a fenced JSON block with these keys, in this order: `label`, `brief`,
`status`, `verdict`, `examined`, `checklist`, `findings`, `forks`,
`beyond_brief`, `incidents`, `own_authority`, `alternatives`,
`brief_corrections`, `dropped_suspicions`, `notes`. Keep the three lists apart
in `notes`: what the run established, what a pass found beyond its brief, and
what a pass decided on its own authority.
```

## Remediation pass

```text
Read the repair list and each finding's cited span before editing anything.

[invariant preamble]

[access block]

For each finding in the repair list, re-derive it against the artifact first,
then return exactly one outcome: applied with the minimum edit, refuted with
its settling span, or routed with the path its owner needs.

Edit only the target paths this brief grants. Leave every other path
byte-identical.

Return: a fenced JSON block with these keys, in this order: `label`, `brief`,
`status`, `verdict`, `examined`, `checklist`, `findings`, `forks`,
`beyond_brief`, `incidents`, `own_authority`, `alternatives`,
`brief_corrections`, `dropped_suspicions`, `notes`. Put one outcome per
finding in `notes`, the applied edit ids in `checklist`, and every refutation
with its span in `findings`.
```

## Critic pass

```text
Read the finished body and the brief it answers in full.

[invariant preamble]

[access block]

Name what the brief requires that the body leaves out, in the brief's own
words. Name each item you confirm present with its anchor. Write each gap unit
as a full brief.

Run the surplus read beside this pass: name what to remove, and propose turning
each restated rule into a citation.

Return: a fenced JSON block with these keys, in this order: `label`, `brief`,
`status`, `verdict`, `examined`, `checklist`, `findings`, `forks`,
`beyond_brief`, `incidents`, `own_authority`, `alternatives`,
`brief_corrections`, `dropped_suspicions`, `notes`. Put the gap units as full
briefs in `notes`, the confirmed-present items with their anchors in
`checklist`, and the surplus read's removal proposals in `alternatives`.
```

## Judge pass

```text
Read the full candidate set before scoring anything.

[invariant preamble]

[access block]

Score every candidate on this one criterion: [criterion]. Use this scale:
[the defined scale, one clause per point].

Name at most three fatal flaws, each with a span. Leave every other candidate
observation in the rationale rather than the flaw list.

Return: a fenced JSON block with these keys, in this order: `label`, `brief`,
`status`, `verdict`, `examined`, `checklist`, `findings`, `forks`,
`beyond_brief`, `incidents`, `own_authority`, `alternatives`,
`brief_corrections`, `dropped_suspicions`, `notes`. Put one score per
candidate with a one-clause rationale and the quote that earned it in
`notes`, and at most three fatal flaws with a span each in `findings`.
```

## Validator pass

```text
Read the tree as it now stands, beginning with [the roster and the link
index].

[invariant preamble]

[access block]

Work within this grant: [the paths this pass may read and write]. Read every
granted path in full. Write only inside the grant.

Return: a fenced JSON block with these keys, in this order: `label`, `brief`,
`status`, `verdict`, `examined`, `checklist`, `findings`, `forks`,
`beyond_brief`, `incidents`, `own_authority`, `alternatives`,
`brief_corrections`, `dropped_suspicions`, `notes`. Put the invariants that
hold in `checklist`, the broken ones with path and anchor in `findings`, and
the repairs you propose rather than apply in `alternatives`. On an upstream
shortfall, report the gap in `notes` and write nothing.
```
