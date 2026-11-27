# Wiki Log

> Chronological record of wiki changes. Append-only for settled entries.
> Format: `## [YYYY-MM-DD HH:MM] action | subject`. The timestamp is local
> 24-hour wall-clock time, and it is what keeps every new heading unique.
> Actions: ingest, update, query, lint, create, archive, delete, audit, import, session-wrapup, rotate
> Entries: an entry settles at commit. A `## [` entry the last commit already
> contains is settled, and append-only protects it. An entry the working tree
> adds is open, and a later edit that corrects or refines the same work folds
> into that open entry instead of adding one of its own. One open entry covers
> one work unit, meaning one subject or change set, so unrelated work in the
> same uncommitted span keeps separate entries. Work that no commit ships, such
> as a block deleted and then restored, leaves no entry. An operation that
> changes no file appends none, and a lint run is logged only when it changed
> files. An audit run is the one zero-change exception, because its entry
> carries the baseline the next audit scopes from. An entry per edit or per
> clean check turns the log into a record of transitions instead of a record of
> what shipped. In a wiki outside version control, every entry written in the
> current session stays open until that session ends.
> Repair: append-only binds a settled entry's substance, so never reword, reorder, or delete what a settled entry records. An entry may still be edited to repair a structural or lint break it introduced, such as a heading that collides with an earlier one or malformed markdown, provided the repair keeps what the entry records and where it sits. Legacy date-only headings stay valid as written; a colliding one is disambiguated by suffixing the later heading, never by inventing a time the entry never recorded. An open entry takes folds under `Entries:`, and a repair to a settled entry is never a fold target.
> Scope: an entry records changes to this wiki, and only those. Name the files
> under the wiki and what changed on each. A change elsewhere in the repository
> that holds the wiki belongs to that change's own commit message, and
> knowledge worth keeping goes onto the wiki page that owns it, after which the
> entry names that page instead of restating it. This keeps the log an index
> into the wiki's own history rather than an entry that reads as a commit
> message with one wiki bullet attached, or a parking lot for findings no page
> carries.
> Body: list only files actually created or updated. Skip files that were
> inspected, considered, or deliberately left unchanged, and do not narrate
> decisions about what not to do. Leave out the session that produced the
> change: who asked for what, drafts that were replaced, and corrections made
> before the work was committed all stay out, because an entry describes what
> the wiki now holds and what changed in it. Redaction leaves no trace in the
> log: removing or anonymizing content writes no entry and appears in no entry,
> whether the redacted work is open or settled. Aim for roughly 20 lines per
> entry.
> When this file exceeds 500 entries, rotate: rename to log-YYYY.md — or to the first free log-YYYY-N.md when that name is taken — start fresh; the new log carries no baseline, so the next audit reads every page in the wiki in full and records a fresh baseline only when it does, otherwise writing `unavailable`.

## [{{NOW}}] create | Wiki initialized

- Domain: [to be configured in SCHEMA.md]
- Structure created with SCHEMA.md, index.md, log.md, raw/, entities/, concepts/, comparisons/, queries/, summaries/, procedures/
