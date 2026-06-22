---
description: Redesign update_changelog so past entries are immutable — drop the retroactive status-marker re-evaluation that rewrites already-written entries.
scope: plugins/ai_dev/skills/update_changelog
created: 2026-06-02T19:37:57
updated: 2026-06-22T10:20:11
status: ready
reported-by: Andreas Hoffmann
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
- The model being adopted: past entries are immutable (add-only), and the *kind* of change is carried by the new entry's category rather than by a mutated status marker. The skill's current `<categories>` axis is a custom vocabulary (`Implementation/runtime`, `Refactor`, `Refactor/perf` / `Perf/runtime`, `Refactor/runtime reliability`, `Docs/specs-only`); this redesign replaces it with the small standard set defined in the Approach. Supersession folds into that axis cleanly — a replacement or removal becomes a fresh entry under its own day, so the old entry is never touched.
- This was assessed in the session that filed this task; the author chose the immutable-entries direction over keeping the marker overlay.
- Sibling cleanup task that depends on this one landing first: [changelog_history-driven-rebuild.md](changelog_history-driven-rebuild.md) — the one-time manual rebuild of the existing `CHANGELOG.md`. Land this skill redesign first.

## Approach

Edit `plugins/ai_dev/skills/update_changelog/SKILL.md` so past entries are immutable:

- **Remove the `<status_re_evaluation>` procedure step entirely.** No run re-reads or re-marks past entries.
- **Strip the marker-assignment clause from the `<day_loop>` per-day substep.** That substep currently ends "…choose categories, compose a 2-5 word day theme, and assign status markers by checking each entry against the current state of the codebase." Drop the trailing "and assign status markers …" clause — no status slot remains to fill — while keeping the aggregate-related-changes-into-logical-entries, choose-categories, and compose-day-theme work intact.
- **Retire the three-marker overlay** (`[active]` / `[changed later]` / `[superseded]`) and its header legend line. Once entries are immutable every entry is a frozen fact at write time, so a live marker is noise. The `<entry_line>` format drops the `[status]` slot.
- **Replace the `<categories>` vocabulary so it carries supersession.** Swap the existing custom categories (`Implementation/runtime`, `Refactor`, `Refactor/perf` / `Perf/runtime`, `Refactor/runtime reliability`, `Docs/specs-only`) for a small standard set: `added` (new features or capabilities), `changed` (behaviour different than before), `deprecated` (retired or removed, or kept only for legacy use and no longer to be used), `refactored` (same output from the same input, but faster, more robust, or less buggy), and `docs` (documentation- or spec-only change). The old categories map onto these — `Implementation/runtime` → `added`/`changed`; the `Refactor*` / `Perf*` family → `refactored`; `Docs/specs-only` → `docs`. Supersession now rides this axis: when something is replaced or removed, the new entry in the later day's section carries the story as `deprecated` or `changed` — the old entry is never touched.
- **Strengthen the immutability rules.** `<date_immutability>` and `<preserve_existing>` should now state plainly that entries already present — date, text, and category — are frozen once written; later committed changes are recorded only as new entries or day sections, never by rewriting existing entries. Leave room for the bounded last-recorded-day reconciliation owned by [changelog_incremental-day-boundaries.md](changelog_incremental-day-boundaries.md), while removing any wording that licenses editing entries already present.
- **Keep context safety, but remove append wording.** `<context_safety>` should still require one-day-at-a-time processing and flushing each completed day before moving to the next, but it must not say completed day sections are "append[ed]" to `CHANGELOG.md`; rely on `<newest_first>` for inserting new day sections below the header.
- **Update the `<objective>`, `<output_contract>` header/legend, `<status_markers>` (delete), and the `description:` frontmatter** so they no longer promise per-entry "current code state" markers; the description's marker enumeration must go.
- **Reconcile `<model_authority>`** which currently lists "status-marker evaluation" as a model-owned job — drop that responsibility.
- Keep everything else (day grouping, newest-first, one-entry-per-logical-change, files-changed line, one-day-at-a-time context safety, the `prepare_changelog_day.sh` tool contract) intact.

Non-goals: do not touch the existing `CHANGELOG.md` content in this task — the one-time rebuild is the sibling task. Do not change incremental date selection or last-recorded-day reprocessing here; [changelog_incremental-day-boundaries.md](changelog_incremental-day-boundaries.md) owns that procedure. Do not add new languages or build steps; this is a prose edit to one `SKILL.md`.

## Acceptance

- `SKILL.md` no longer contains a `<status_re_evaluation>` step, the `[active]`/`[changed later]`/`[superseded]` legend, or a `<status_markers>` block, and the `<entry_line>` format has no `[status]` slot.
- The `<day_loop>` per-day procedure substep no longer instructs assigning status markers; only the aggregate-related-changes-into-logical-entries, choose-categories, and compose-day-theme steps remain.
- The `description:` frontmatter no longer enumerates status markers; it describes an immutable-entry (add-only), day-grouped changelog.
- The `<objective>` no longer promises per-entry "current code state" status markers; it describes a day-grouped, add-only history derived from git commits.
- `<model_authority>` no longer lists status-marker evaluation among the model-owned jobs.
- `<categories>` is the standard `added` / `changed` / `deprecated` / `refactored` / `docs` set defined in the Approach (the prior custom vocabulary is gone), and supersession is expressible as a `deprecated` or `changed` entry on a new day.
- `<date_immutability>` / `<preserve_existing>` state that entries already present are frozen (date, text, category), later committed changes are recorded only as new entries or day sections, and no clause licenses rewriting entries already present or forbids the last-recorded-day reconciliation owned by [changelog_incremental-day-boundaries.md](changelog_incremental-day-boundaries.md).
- `<context_safety>` keeps the one-day-at-a-time and flush-before-next-day rules, but no longer says completed day sections are appended to `CHANGELOG.md`.
- No remaining internal contradiction between context-safety (don't re-read the whole history) and the procedure (which no longer re-reads it).
