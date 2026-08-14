---
description: Rescope skill_doctor's two non-ASCII findings onto the typographic punctuation set, rename both codes after that class, drop the UTF-8 half, and report the measured sibling split.
scope: plugins/ai_dev/skills/skill_doctor
created: 2026-08-12T19:09:05
updated: 2026-08-13T22:32:02
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Rescope skill_doctor's non-ASCII findings onto typographic punctuation and report the measured sibling split

## Goal

`scripts/discovery_safety.py` flags a description for the typographic
punctuation that stands in for sentence structure, rather than for every
character above the ASCII boundary. The two findings fire on the em dash, the en
dash, the curly single and double quotes, and the ellipsis, and they leave a
description carrying an accented Latin letter, a proper name, or a non-Latin
script unflagged. Both codes name that character class rather than the writing
fault behind it, so the code claims only what a regex proves. The sibling finding
reports the split the run actually measured: how many siblings in the selected
set carry those characters and which ones. A reader of the skill's
`<discovery_safety>` prose finds one canonical statement of the narrowed
dimension.

## Context

`scripts/discovery_safety.py` decides both findings with `has_non_ascii`, which
returns true for any codepoint above 127. That predicate drives the per-skill
`description_non_ascii` warning and, through the `is_outlier_trait` helper, the
set-level `sibling_non_ascii_outlier` warning. The message both emit is written
almost entirely about the em dash: it tells the reader to split the sentence in
two and rejects a hyphen, a double hyphen, or an en dash substituted into that
slot. The trigger is therefore far broader than the remedy. A description
containing `café` or `Gödel` trips the warning and receives em-dash advice that
does not apply to it.

Characters that genuinely break a parse are already covered on the right axis,
by character class rather than by the ASCII boundary, so this task adds no
parse-safety check. `HOSTILE_CHAR_RE` blocks a named set of C0 and C1 controls,
the no-break space, the zero-width and bidi marks, and the byte-order mark.
`RISKY_PUNCT_RE` warns on `#`, `{`, `}`, `::`, and the tab, all of them plain
ASCII. The frontmatter parser separately flags an unquoted colon in a scalar.

The message's other half asks the reader to confirm every consuming manifest and
router reads UTF-8. That half goes. JSON is UTF-8 by specification and YAML 1.2
is UTF-8 or UTF-16, and every consumer in this repository is one or the other, so
the check warns about a failure that cannot occur. The one real non-ASCII
incident in this backlog concerns wiki page filenames breaking git sync, which is
a different mechanism on a different surface and leaves the description-level
portability claim unsupported.

The sibling message additionally asserts something the script never measured. Its
text reads `description carries non-ASCII characters while its siblings stay
ASCII-only`. On a family run over the four wiki skills, two of the four carried
non-ASCII, the finding fired for both, and each firing claimed an ASCII-only
sibling set that did not exist. The count the outlier helper already computes
states the case correctly.

The finding itself earns its place either way. An odd-one-out description is a
real signal about a family's formatting, and the per-skill finding and the
set-level one stay complementary rather than redundant.

Three surfaces carry the old framing beyond the script. The skill's
`<discovery_safety>` section names it in the bullet beginning `Compare sibling
descriptions inside the same selected set`, in the paragraph beginning
`Typographic non-ASCII in a description is an encoding finding`, and in the
severity paragraph's list of quality judgements. The script-test runner
`tests/skill_doctor/script_tests/run.sh` carries every check whose name contains
`non_ascii` plus the `real_shape_no_block_em_dash_lead` regression guard. The
eval surface carries the `no_hyphen_substitution` grader in
`tests/skill_doctor/evals/grade.sh` and the surface description in
`tests/skill_doctor/README.md`.

`tasks/wiki_activation-surface-and-descriptions.md` holds the other side of this
surface, and the two tasks divide it cleanly: this one changes what the check
fires on, that one changes the descriptions the check fires on. The division has
one coupling. That task's Acceptance names both `description_non_ascii` and
`sibling_non_ascii_outlier` verbatim, so the rename stops that item resolving and
this task repoints it. Neither task blocks the other, since the em dash stays a
flagged character under the old code and the new one alike.

Co-edit: [ai-dev_skill-doctor-agent-scope.md](../ai-dev_skill-doctor-agent-scope.md),
[ai-dev_skill-doctor-listing-budget-length.md](ai-dev_skill-doctor-listing-budget-length.md),
and
[ai-dev_skill-doctor-repo-convention-portability.md](ai-dev_skill-doctor-repo-convention-portability.md)
each change findings in the same script and add scenarios to the same test
runner, so coordinate those two surfaces across all four.

## Approach

Delete `has_non_ascii`. Declare `TYPOGRAPHIC_PUNCT_RE` beside `HOSTILE_CHAR_RE`
and `RISKY_PUNCT_RE`, covering the em dash, the en dash, U+2018, U+2019, U+201C,
U+201D, and the horizontal ellipsis, with a comment stating what the set covers
and why the ASCII boundary was the wrong axis. Drive the per-skill check and
`is_outlier_trait` through `.search()` and a lambda, matching how
`RISKY_PUNCT_RE` is used today.

Rename `description_non_ascii` to `description_typographic_punctuation` and
`sibling_non_ascii_outlier` to `sibling_typographic_punctuation_outlier`. The
names follow the shipped `sibling_<trait>_outlier` shape and name the character
class, because a regex proves a character is present and cannot prove the clause
break was unearned. Keep both at `warning` severity, since each remains a
judgement about description quality and the skill's severity line reserves
blocking for mechanical facts.

Rewrite the per-skill message to drop the UTF-8 portability sentence and keep the
remedy: split the description into two sentences where a dash holds together a
clause break the sentence never earned, and treat a hyphen, a double hyphen, or
an en dash substituted into that slot as no fix. Rewrite the sibling message so
it states the count of siblings in the selected set carrying these characters and
names them, followed by that same remedy. A single carrier is covered by the same
wording, since a count of one states that case.

Rewrite the three `<discovery_safety>` passages in place so the narrowed
dimension is stated once and the encoding framing is gone. The paragraph that
opens `Typographic non-ASCII in a description is an encoding finding` loses its
premise entirely, so it becomes a statement of what the finding now covers and
why the remedy is a rewrite rather than a substitution.

Update the two test surfaces and the inbound acceptance item in the same change,
per the standing repo rule that a skill change lands with the scenarios proving
its own new behavior and with the existing suite re-run.

**Out of scope:**

- A new parse-safety or YAML-safety check, since `HOSTILE_CHAR_RE`,
  `RISKY_PUNCT_RE`, and the frontmatter parser's unquoted-colon finding already
  cover that axis unchanged.
- Which sets the sibling comparison runs over, settled by the skill as shipped.
- Rewriting the em dashes out of the four wiki family descriptions, owned by
  [wiki_activation-surface-and-descriptions.md](../wiki_activation-surface-and-descriptions.md).

## Acceptance

1. A staged description carrying an accented Latin letter and no typographic
   punctuation produces neither the per-skill finding nor the sibling outlier,
   where the same input produces `description_non_ascii` today.
2. A staged description carrying each of the em dash, the en dash, U+2018,
   U+2019, U+201C, U+201D, and the horizontal ellipsis produces
   `description_typographic_punctuation` in every one of those seven cases.
3. Searching a full run's output for `description_non_ascii` and for
   `sibling_non_ascii_outlier` returns no match, and both new codes appear.
4. Searching the per-skill message for `UTF-8` returns no match, while the
   message still directs the reader to split the sentence and still rejects a
   hyphen, a double hyphen, and an en dash as substitutes.
5. A staged selected set where at least two siblings carry typographic punctuation
   and at least one sibling in the set does not produces a sibling message
   stating the count and naming those carriers, and searching the output for
   `siblings stay ASCII-only` returns no match.
6. Searching a staged `sibling_typographic_punctuation_outlier` message for
   `UTF-8` returns no match, while the message still directs the reader to split
   the sentence and still rejects a hyphen, a double hyphen, and an en dash as
   substitutes.
7. A staged set with exactly one carrier still produces the sibling finding, and
   its message names that one sibling.
8. A staged set whose descriptions carry none of these characters produces no
   sibling outlier finding, unchanged from today.
9. Both findings carry `warning` severity, read from the emitted findings, and a
   full run over the repository's own skills exits with the same blocking count
   as before the change.
10. Searching the skill's `SKILL.md` and `scripts/discovery_safety.py` for
    `non-ASCII` returns no match in either file, the `<discovery_safety>` bullet
    and the severity paragraph name the narrowed dimension, and the narrowed
    dimension is stated in exactly one paragraph.
11. `tests/skill_doctor/script_tests/run.sh` renames every check whose name
    contains `non_ascii` except `discovery_non_ascii_message_keeps_the_utf8_check`,
    which is removed with no successor, gains the multi-sibling scenario from
    item 5 and the accented-letter scenario from item 1, and passes in full.
12. `real_shape_no_block_em_dash_lead` still reports `blocking_count == 0` for
    the em-dash lead fixture, and that fixture now produces the typographic
    warning rather than the old code.
13. `tests/skill_doctor/evals/grade.sh` and `tests/skill_doctor/README.md`
    describe the finding by its new name, and the `no_hyphen_substitution`
    grader still passes on the `discovery_risky_sibling` eval.
14. The acceptance item in `tasks/wiki_activation-surface-and-descriptions.md`
    that names both old codes names the two new codes instead, and searching that
    file for the old code names returns no match.
15. Searching `scripts/discovery_safety.py` finds `TYPOGRAPHIC_PUNCT_RE` declared
    beside `HOSTILE_CHAR_RE` and `RISKY_PUNCT_RE` with a comment stating what the
    set covers and why the ASCII boundary was the wrong axis.
