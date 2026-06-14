---
description: Make the newest-first day insertion a single anchored prepend against a stable header boundary, so the agent stops mis-splicing day order.
scope: plugins/ai_dev/skills/update_changelog
created: 2026-06-02T20:21:26
updated: 2026-06-10T22:05:12
status: open
reported-by: Andreas Hoffmann
---

# Anchor the newest-first day insertion so the agent stops mis-ordering

## Goal

Keep the changelog newest-first (the convention and the intended read) while
removing the write-time friction that ordering has caused. The struggle is
mechanical, not about the order itself: newest-first means each new day must be
**spliced in between the header and the first existing day**, and the skill drives
that as a repeated, loosely-anchored "insert directly after the header" — so the
agent occasionally places a day in the wrong seam or reorders existing days. Fix it
by defining one stable anchor and making insertion a single, unambiguous prepend
against it.

## Context

- Skill: `plugins/ai_dev/skills/update_changelog/SKILL.md` — the `<newest_first>` policy ("insert new day sections directly after the header"), the `<day_loop>` substep ("Insert the completed day section directly after the header block"), and the matching `<procedure>` steps.
- Why the order stays newest-first (decided in the session that filed this task): it is the preferred read and what a changelog reader expects — latest at the top; oldest-first/append would be easier for the agent but would make *human* readers scroll to the bottom for the latest. The right fix is to make the producer reliable, not to flip a reader-facing order.
- Root of the struggle: "insert after the header" has no crisp anchor, and a cold build over a long history does many such inserts in a row (process oldest→newest, each inserted at top), multiplying the chance of a misplaced or reordered day.
- Interaction with sibling tasks (cross-link, sequence deliberately):
  - [changelog_incremental-day-boundaries.md](changelog_incremental-day-boundaries.md) owns `<enumerate_dates>` and which days a run (re)builds. This task owns *how* those day sections land in the file. They meet at the insert step — keep their wording consistent.
  - [changelog_immutable-entries-redesign.md](changelog_immutable-entries-redesign.md) makes the common run purely additive at the top (no marker re-walk), which is what makes a single clean prepend possible.
  - [changelog_large-output-protocol.md](changelog_large-output-protocol.md) governs reading the per-day blob; unrelated to the insert seam but part of the same write loop.

## Approach

- **Define a stable anchor in `<output_contract>`.** The header block (H1 + legend/intro lines) ends at a recognizable boundary; the first `## YYYY-MM-DD` heading is the top of the day list. The invariant: new day sections always go **immediately between the header block and the current first day heading**, never inside the header, never below an existing day. The invariant governs **new** day sections: when a run reopens the last recorded day (the day-`D` reconciliation in [changelog_incremental-day-boundaries.md](changelog_incremental-day-boundaries.md)), that day's existing section is extended in place, not re-inserted.
- **Incremental run (few new days — the common case): one anchored prepend.** Build all the run's day sections into a single block already ordered newest-first, then perform **one** insert that splices that block between the header and the first existing day heading (anchor the edit on that first existing heading). One edit, one seam, nothing reordered.
- **Cold build (no `CHANGELOG.md`, long history): per-day insert against the same anchor.** Keep `<context_safety>` (process one day at a time oldest→newest, flush before the next so prior days fall out of context). Each completed day is inserted immediately after the header block — the same stable anchor — so processing oldest→newest yields newest-first without holding the whole history in context. The anchor is identical to the incremental case; only the batch size differs, and that is governed by context-safety.
- **Bound the read needed to find the seam.** To locate the insertion point, read only the header block plus the first existing `##` heading (a small bounded read), not the whole file.
- **Rewrite `<newest_first>`, `<day_loop>`, and the `<procedure>` insert substeps** to state the anchored operation explicitly (single-block prepend for incremental, per-day anchored insert under context-safety for cold build), replacing the current loose "insert directly after the header" phrasing.
- Keep the skill self-contained — describe the operation inline; no pointer to sibling skills in the shipped prose.

Non-goals: do not change the reading order (stays newest-first); do not change which days a run processes (that is the incremental-day-boundaries task); do not add a marker re-walk (the immutable-entries task removes it).

## Acceptance

- `<output_contract>` defines the header-block boundary as a stable anchor and states the invariant that new day sections sit between the header and the first existing day heading, including the reopened-last-day carve-out.
- `<newest_first>` / `<day_loop>` / `<procedure>` specify: incremental runs do a single anchored prepend of a newest-first block; cold builds insert per day against the same anchor under `<context_safety>`.
- The skill instructs a bounded read (header + first day heading) to find the seam, not a whole-file read.
- A scenario check: an incremental run that adds two new days produces them in newest-first order at the top, with every pre-existing day unchanged and in its original order.
- `<context_safety>` still holds for a cold build over a long history (one day at a time, flushed).
