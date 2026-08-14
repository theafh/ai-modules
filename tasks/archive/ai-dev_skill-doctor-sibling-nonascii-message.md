---
description: Make skill_doctor's sibling non-ASCII finding report the measured split across the selected set, since its message asserts an ASCII-only sibling set even when several siblings carry non-ASCII.
scope: plugins/ai_dev/skills/skill_doctor
created: 2026-08-11T18:59:52
updated: 2026-08-13T22:32:17
status: deferred
reported-by: Andreas Hoffmann
---

# Make skill_doctor's sibling non-ASCII finding state what it measured

## Goal

A reader of the `sibling_non_ascii_outlier` finding learns how the selected set
actually splits on non-ASCII characters: how many siblings carry them and which
ones. The finding keeps its code, its warning severity, and its rewrite guidance,
and its message stays true whether one sibling or several carry non-ASCII.

## Deferred

Deferred as too narrowly scoped. This task repairs one false clause in the
sibling message while keeping the ASCII boundary as the trait the check fires
on, and that boundary is itself the defect: it flags every character above
codepoint 127 while the remedy the message carries addresses only typographic
punctuation. The successor
[ai-dev_skill-doctor-typographic-punctuation-finding.md](ai-dev_skill-doctor-typographic-punctuation-finding.md)
absorbs this repair as one of its acceptance items and rescopes both findings
onto the character class the remedy actually fits.

## Context

`scripts/discovery_safety.py` emits the finding with the message
`description carries non-ASCII characters while its siblings stay ASCII-only`. On
a family run over the four wiki skills, two of the four carried non-ASCII, the
finding fired for both, and each firing asserted an ASCII-only sibling set that
did not exist. The claim about the siblings is derived from nothing the script
measured, while the count it does have would state the case correctly.

The finding itself earns its place: an odd-one-out description is a real signal
about a family's formatting, and the same run also produced the correct
`description_non_ascii` encoding finding beside it, so the two stay
complementary rather than redundant.

The skill's `<discovery_safety>` section describes the sibling comparison as
covering `non-ASCII characters`, which stays accurate, so the change lands in the
script's message text rather than in the skill prose.

Co-edit: [ai-dev_skill-doctor-agent-scope.md](../ai-dev_skill-doctor-agent-scope.md)
also edits this script, and both it and
[ai-dev_skill-doctor-scope-failure-reporting.md](ai-dev_skill-doctor-scope-failure-reporting.md)
add scenarios to the same script-test runner, so coordinate those two surfaces.

## Approach

Rewrite the message so it reports the split the run measured: the number of
siblings in the selected set carrying non-ASCII characters and their names,
followed by the existing guidance to align the description by rewriting the
sentence rather than transliterating the character. A single outlier is covered by
the same wording, since a count of one states that case. Keep the finding's code
and warning severity as they are, so any caller keying on either is unaffected.

**Out of scope:**

- Which sets the sibling comparison runs over, settled by the skill as shipped.
- The block-versus-warn severity line, which the skill states deliberately.

## Acceptance

1. A staged selected set where two or more siblings carry non-ASCII produces a
   message stating the count and naming those siblings, and searching the output
   for `siblings stay ASCII-only` returns no match.
2. A staged set with exactly one non-ASCII sibling still produces the outlier
   finding, and its message names that one sibling.
3. Both cases keep the `sibling_non_ascii_outlier` code and `warning` severity,
   verified from the emitted finding.
4. The message retains its rewrite guidance, so a reader is still told to rewrite
   the sentence rather than transliterate the character.
5. `tests/skill_doctor/script_tests/run.sh` gains the multi-sibling scenario from
   item 1 and passes alongside its existing scenarios.
6. A set whose descriptions are all ASCII produces no outlier finding, unchanged
   from today.
