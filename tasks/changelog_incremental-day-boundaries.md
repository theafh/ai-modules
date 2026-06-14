---
description: Fix incremental-run date selection — reprocess the last recorded day plus all following, and use only committed work, since same-day commits can land after the last entry.
scope: plugins/ai_dev/skills/update_changelog
created: 2026-06-02T20:06:20
updated: 2026-06-10T22:05:12
status: open
reported-by: Andreas Hoffmann
---

# Make incremental runs reprocess the last recorded day, from committed history only

## Goal

Make the skill spell out the runtime facts an agent must rediscover on every
incremental run, and fix the date-selection bug that drops same-day work. Today
`<enumerate_dates>` says to "drop dates already covered by the most recent day
section" — so once a day has a section, the skill never looks at that day again.
But commits frequently land **on the same calendar day, after** the changelog was
last generated. Those commits are silently lost: they belong to a day the skill
now considers "done." Fix the boundary so an incremental run re-derives from the
**last recorded day inclusive** through HEAD, and state plainly that only
**committed** history is in scope — never uncommitted working-tree state.

## Context

- Skill: `plugins/ai_dev/skills/update_changelog/SKILL.md`, the `<enumerate_dates>` procedure step and the `<newest_first>` / `<context_safety>` policies.
- The runtime-discovery facts the skill should make explicit (an agent has to find these out fresh each run, and the prose currently leaves them implicit):
  - **Only committed work counts.** The changelog is git-history-derived; entries describe commits, never uncommitted edits in the working tree. (This is also the lesson from session `07a4d5ec`, where an agent hand-wrote entries for uncommitted changes and they had to be reverted — see the do-not-hand-edit follow-up.)
  - **The last recorded day is provisionally complete, not frozen.** Find the most recent `## YYYY-MM-DD` heading in `CHANGELOG.md`; that day may have gained commits after the section was written. So the run must reconsider that day, not skip it.
  - **Reprocess the last recorded day + every following day.** Enumerate distinct commit dates from the last recorded day **inclusive** through the newest commit, and (re)build each. A day strictly older than the last recorded day is settled and stays untouched.
- The bundled script is already correct here: `prepare_changelog_day.sh` selects a day by `--after=DATET00:00:00 --before=DATET23:59:59`, so re-running it for the last recorded day returns **all** of that day's commits, including ones added after the last run. The fix is in the skill's date-enumeration logic, not the script. (Note: the same-day `git log --since=DATE --until=DATE` footgun an agent hit in session `413ad030` was a manual ad-hoc command, not the script — the script uses the correct timestamped bounds.)
- Reprocessing the last recorded day means **adding** entries/files for commits not yet recorded and, where needed, revising that day's theme and `Files changed:` line — completing a day that was written before it was over, **without rewriting any entry already present** (consistent with the freeze model in [changelog_immutable-entries-redesign.md](changelog_immutable-entries-redesign.md)). A day becomes frozen only once no unrecorded commits remain for it.

## Approach

- Rewrite `<enumerate_dates>` so an incremental run:
  1. Reads only the most recent `## YYYY-MM-DD` heading from `CHANGELOG.md` (bounded read — not the whole file) to learn the last recorded day `D`.
  2. Runs `git log --reverse --format='%ad' --date=short --no-merges --after=<D>T00:00:00 | sort -u` (or equivalent) to list distinct commit dates from `D` inclusive through HEAD.
  3. Rebuilds day `D` and every later day, newest-first on insert, via the per-day script.
  - When `CHANGELOG.md` does not exist yet, behavior is unchanged (enumerate the full history oldest-first).
- Add a short `<scope_of_a_run>` (or fold into `<enumerate_dates>`) stating: only committed history is in scope; the last recorded day is reopened because same-day commits may post-date its section; days older than the last recorded day are settled.
- Define how reopening day `D` reconciles with its existing section: add entries for the newly-found commits, extend the `Files changed:` line, and revise the theme if the day's focus shifted — without rewriting entries already present.
- Keep `<context_safety>` intact (one day at a time, flush before next) — this change touches only *which* days are in scope, not the one-at-a-time processing.

Non-goals: no change to per-day commit selection inside the script (already correct); no change to the output format beyond the day-`D` reconciliation rule.

## Acceptance

- `<enumerate_dates>` re-derives dates from the last recorded day **inclusive** through HEAD on an incremental run; it no longer instructs dropping the most recent recorded day.
- The skill states explicitly that only committed history is in scope (no uncommitted working-tree entries) and why the last recorded day is reopened (same-day-after commits).
- The day-`D` reconciliation rule is defined: add/extend the existing section, never rewrite entries already present.
- A scenario check: with a changelog whose newest day is `D` and a new commit added on `D` after generation, an incremental run picks up that commit and adds it to day `D`'s section.
- First-run (no `CHANGELOG.md`) behavior is unchanged.
