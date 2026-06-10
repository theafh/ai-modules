---
description: Redesign update_changelog so past entries are immutable — drop the retroactive status-marker re-evaluation that rewrites already-written entries.
scope: plugins/ai_dev/skills/update_changelog
created: 2026-06-02T19:37:57
updated: 2026-06-10T22:05:12
status: open
---

# Make update_changelog entries immutable and stop mutating past entries

## Goal

Stop the `update_changelog` skill from reaching back to rewrite already-written
changelog entries. A changelog is a chronological record of *what changed, when* —
each entry is a permanent fact about a moment in time. The current design treats
the changelog as a live status dashboard instead, re-evaluating a status marker on
every past entry on each run so it reflects *current* code state. That is the wrong
job for a changelog (current state lives in the code, README, and docs), it is the
expensive part of the skill, and it creates pressure that makes the model
illegally rewrite prior summary text. Redesign the skill so past entries are
immutable: a change is recorded only as a **new entry on the date it happened**,
never by mutating the old entry. Note the wording trap — this is *add-only*, not
"append": in a newest-first log the new entry is inserted at the **top, below the
header**, not appended at the bottom.

## Context

- Skill file: `plugins/ai_dev/skills/update_changelog/SKILL.md`.
- The behaviour is **not** LLM overindexing — the skill explicitly instructs it. Two clauses drive it:
  - `<status_markers>` / the header legend define `[changed later]` and `[superseded]`, markers that can only be set by looking at state *later* than the entry's own date — so they are inherently retrospective and must be mutated on later runs.
  - `<status_re_evaluation>` (last procedure step): "re-evaluate status markers on every existing entry section-by-section. Promote `[active]` entries to `[changed later]` … and to `[superseded]` …".
- Two structural flaws this redesign resolves:
  - **Self-contradiction.** `<context_safety>` says process one day, flush it, and let already-written days "fall out of working context … histories can exceed any context window." But `<status_re_evaluation>` requires walking *every* existing entry against current code on every run — the exact whole-history re-read the skill forbids. Cost grows with the changelog.
  - **Preserve-vs-annotate collision.** `<preserve_existing>` says "do not rewrite prior summaries," yet a bare `[superseded]` marker is uninformative ("superseded by what?"), so the model appends parentheticals to old entries to make the marker meaningful — breaking the preserve rule. Live example in the repo's own `CHANGELOG.md`: the `2026-05-29` entry was edited on a later run to append "(`task_health` was renamed to `task_fix` later.)" — the rename happened `2026-05-31`.
- The model being adopted: past entries are immutable (add-only), and the *kind* of change (`Added` / `Changed` / `Deprecated` / `Removed` / `Fixed`) is expressed as a category on the new entry. The skill already has a `<categories>` axis; supersession folds into it cleanly.
- This was assessed in the session that filed this task; the author chose the immutable-entries direction over keeping the marker overlay.
- Sibling cleanup task that depends on this one landing first: [changelog_history-driven-rebuild.md](changelog_history-driven-rebuild.md) — the one-time manual rebuild of the existing `CHANGELOG.md`. Land this skill redesign first.

## Approach

Edit `plugins/ai_dev/skills/update_changelog/SKILL.md` so past entries are immutable:

- **Remove the `<status_re_evaluation>` procedure step entirely.** No run re-reads or re-marks past entries.
- **Retire the three-marker overlay** (`[active]` / `[changed later]` / `[superseded]`) and its header legend line. Once entries are immutable every entry is a frozen fact at write time, so a live marker is noise. The `<entry_line>` format drops the `[status]` slot.
- **Fold supersession into the `<categories>` axis.** Add `Removed` and `Deprecated` (and confirm `Changed` is expressible) so that when something is replaced or removed, the new entry in the later day's section carries the story via its category — the old entry is never touched.
- **Strengthen the immutability rules.** `<date_immutability>` and `<preserve_existing>` should now state plainly that past entries — date, text, and category — are frozen once written; later runs only *add* new day sections at the top. Remove any wording that licenses editing old entries. One carve-out, defined in [changelog_incremental-day-boundaries.md](changelog_incremental-day-boundaries.md): the last recorded day stays completable until no unrecorded commits remain for it — a run may add entries for newly-found commits, extend its `Files changed:` line, and revise its theme — while entries already present stay frozen; every older day is frozen in full.
- **Update the `<objective>`, `<output_contract>` header/legend, `<status_markers>` (delete), and the `description:` frontmatter** so they no longer promise per-entry "current code state" markers; the description's marker enumeration must go.
- **Reconcile `<model_authority>`** which currently lists "status-marker evaluation" as a model-owned job — drop that responsibility.
- Keep everything else (day grouping, newest-first, one-entry-per-logical-change, files-changed line, one-day-at-a-time context safety, the `prepare_changelog_day.sh` tool contract) intact.

Non-goals: do not touch the existing `CHANGELOG.md` content in this task — the one-time rebuild is the sibling task. Do not add new languages or build steps; this is a prose edit to one `SKILL.md`.

## Acceptance

- `SKILL.md` no longer contains a `<status_re_evaluation>` step, the `[active]`/`[changed later]`/`[superseded]` legend, or a `<status_markers>` block, and the `<entry_line>` format has no `[status]` slot.
- The `description:` frontmatter no longer enumerates status markers; it describes an immutable-entry (add-only), day-grouped changelog.
- `<categories>` includes `Removed`/`Deprecated` (and `Changed`) so supersession is expressible on a new entry.
- `<date_immutability>` / `<preserve_existing>` state that past entries are frozen (date, text, category) and runs only prepend new day sections, carrying the last-recorded-day carve-out from the Approach; no clause licenses rewriting entries already present.
- No remaining internal contradiction between context-safety (don't re-read the whole history) and the procedure (which no longer re-reads it).
