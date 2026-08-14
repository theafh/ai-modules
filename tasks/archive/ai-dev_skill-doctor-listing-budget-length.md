---
description: Calibrate skill_doctor's listing-budget length finding; diagnose bare listing entries as budget truncation or name-only override, not a YAML parse bug.
scope: plugins/ai_dev/skills/skill_doctor
created: 2026-08-11T17:26:49
updated: 2026-08-13T22:32:17
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Calibrate skill_doctor's description-length finding to the listing budget

## Goal

A `skill_doctor` run warns when a `description:` is long enough to be at risk of
being dropped from the harness's skill listing, on a single-skill run as well as a
family run, and states the budget arithmetic that makes it a risk. A reader who
sees a skill listed with no description at all learns from the skill's guidance
that the cause is budget truncation over an empty usage history, or a per-skill
listing override, so the diagnosis does not send them hunting for a YAML parse bug
that is not there.

## Context

Claude Code does not hand the model every skill description in full. The listing
it builds has a character budget, and a skill that does not fit is listed by name
alone, with no description. Read out of the CLI binary under
`~/.local/share/claude/versions/<version>` (version 2.1.226) and confirmed against
`~/.claude.json` on 2026-08-11:

- **Budget** = `contextWindow × 4 bytes-per-token × skillListingBudgetFraction`,
  where the fraction defaults to `0.01`. That is roughly 8,000 characters at a
  200k-token window. The `SLASH_COMMAND_TOOL_CHAR_BUDGET` environment variable
  overrides the computed value outright.
- **Per-entry cost** = `len(name) + 4 + min(len(description), skillListingMaxDescChars)`
  for a full entry, against `len(name) + 2` for a name-only entry.
  `skillListingMaxDescChars` defaults to `1536`, and a longer description is
  truncated to it.
- **Rank when the total overruns** = a recency-weighted usage score,
  `usageCount × max(0.5 ^ (daysSinceUse / 7), 0.1)`, read from the `skillUsage`
  map in `~/.claude.json`. Entries are kept greedily in that order while budget
  remains; everything else drops to name-only.
- Both `skillListingMaxDescChars` and `skillListingBudgetFraction` are real
  `settings.json` keys, so a user can raise either.
- A second, unrelated cause produces the same bare entry: a per-skill listing
  override keyed by skill name, whose `name-only` value the CLI documents as
  listing the skill without its description, beside `user-invocable-only` and
  `off`. A diagnosis that names only the budget sends a reader with an override
  in place looking in the wrong direction, so the guidance covers both.

The consequence for skill authoring is a cold-start trap: a never-invoked skill
scores 0 on that ranking, so a new skill with a long description is first in line
to lose its description precisely when nobody has used it yet and the description
is the only thing that could get it invoked. The observed case, from a five-skill
plugin in another repository, is a skill with a 1,047-character description and no
usage record that appeared in the session listing as a bare name while its four
siblings, all with usage records, kept theirs; trimming it to 821 characters was
the mitigation.

`scripts/discovery_safety.py` cannot currently see this. Its only length signal is
the `sibling_length_outlier` finding, which fires on
`abs(len(desc) - mean_len) > max(120, mean_len * 0.75)` and returns early when
fewer than two siblings carry a description. On that five-skill set the lengths
were 1047, 887, 781, 624, and 591 against a mean near 786, so the threshold came
out at 590 and the one description that actually got dropped drew no finding at
all. A single-skill run gets no length signal whatever.

The skill's `<discovery_safety>` block lists the dimensions the script audits,
including length outliers, and is where the diagnosis guidance belongs.

Co-edit: [ai-dev_skill-doctor-typographic-punctuation-finding.md](ai-dev_skill-doctor-typographic-punctuation-finding.md)
and [ai-dev_skill-doctor-agent-scope.md](../ai-dev_skill-doctor-agent-scope.md) also
edit this script, and both of those plus
[ai-dev_skill-doctor-scope-failure-reporting.md](ai-dev_skill-doctor-scope-failure-reporting.md)
add scenarios to the same script-test runner, so coordinate those surfaces.

## Approach

Add an absolute per-description length finding to `scripts/discovery_safety.py`
that runs per skill, independent of how many siblings are in the selected set, and
keep the existing sibling-relative outlier finding beside it: the two answer
different questions, one about budget risk and one about family consistency.

Pin the threshold at one-eighth of the default listing budget: 1000 characters
against the roughly 8000-character default (contextWindow × 4 ×
skillListingBudgetFraction at 0.01). Carry the derivation in a comment on the
constant naming skillListingBudgetFraction, the bytes-per-token factor, and
skillListingMaxDescChars. Report the finding at
`warning` severity, consistent with every other description-quality judgement the
skill makes, and have the message state the measured length, the threshold, the listing
budget, and that a listing overrun drops descriptions by recency-weighted usage
ranking with never-invoked skills first.

Then rewrite the `<discovery_safety>` passage that describes the length dimension
so it states the budget, the ranking by recency-weighted usage, and the
name-only-entry symptom. That gives the reader the diagnosis for a skill listed
without its description and supersedes the current wording, which treats length
only as a sibling comparison.

**Out of scope:**

- Reading the user's `skillUsage` map to score a specific skill's real risk. The
  finding stays a static property of the file under audit.
- Reading or writing `settings.json` to detect a raised
  `skillListingBudgetFraction` or `skillListingMaxDescChars`.
- The block-versus-warn severity line, which the skill states deliberately.

## Acceptance

1. A single selected skill whose description exceeds the new threshold produces
   the length finding at warning severity in the JSON warnings array and not in
   blocking, proving the check no longer depends on having siblings.
2. A selected set of two or more skills, each staged with a description
   exceeding the new threshold and with lengths close enough that
   `sibling_length_outlier` fires for none, produces the length finding for
   each of them.
3. The finding's message states the measured character count and the threshold,
   explains that a listing overrun drops descriptions by recency-weighted usage
   ranking with never-invoked skills first, and searching the output for the word
   `budget` returns a match.
4. A short description well under the threshold produces no length finding, and
   the existing `sibling_length_outlier` finding still fires on a set staged to
   trigger it, unchanged in code and severity.
5. Staging the five recorded lengths 1047, 887, 781, 624, and 591 as one selected
   set produces the new finding for the 1047-character entry, which today's
   sibling-relative check misses.
6. `tests/skill_doctor/script_tests/run.sh` gains the scenarios from items 1, 2,
   4, and 5 and passes alongside its existing scenarios.
7. The skill's `<discovery_safety>` block states the budget arithmetic, the
   recency-weighted usage ranking, and that a listing entry showing no description
   means either budget truncation or a per-skill `name-only` listing override
   rather than unparseable frontmatter, with no remaining passage that frames
   length as a sibling comparison only.
8. The threshold constant's comment names skillListingBudgetFraction (0.01), the
   bytes-per-token factor (4), and skillListingMaxDescChars (1536).
