# Wiki Log

> Chronological record of wiki changes. Append-only.
> Format: `## [YYYY-MM-DD HH:MM] action | subject`. The timestamp is local
> 24-hour wall-clock time, and it is what keeps every new heading unique.
> Actions: ingest, update, query, lint, create, archive, delete, audit, import, session-wrapup
> Entries: an operation that creates or updates wiki files appends one entry; an
> operation that changes no file appends none. Lint and audit runs are the
> exception — each records its outcome, including a zero-change one, as a
> process record.
> Repair: append-only binds the substance, so never reword, reorder, or delete
> what a past entry records. An entry may still be edited to repair a
> structural or lint break it introduced, such as a heading that collides with
> an earlier one or malformed markdown, provided the repair keeps what the
> entry records and where it sits. Legacy date-only headings stay valid as
> written; a colliding one is disambiguated by suffixing the later heading,
> never by inventing a time the entry never recorded.
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
> decisions about what not to do. Aim for roughly 20 lines per entry.
> When this file exceeds 500 entries, rotate: rename to log-YYYY.md, start fresh.

## [{{NOW}}] create | Wiki initialized

- Domain: [to be configured in SCHEMA.md]
- Structure created with SCHEMA.md, index.md, log.md, raw/, entities/, concepts/, comparisons/, queries/, summaries/, procedures/
