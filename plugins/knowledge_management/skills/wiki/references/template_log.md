# Wiki Log

> Chronological record of wiki changes. Append-only.
> Format: `## [YYYY-MM-DD] action | subject`
> Actions: ingest, update, query, lint, create, archive, delete, audit, import, session-wrapup
> Entries: an operation that creates or updates wiki files appends one entry; an
> operation that changes no file appends none. Lint and audit runs are the
> exception — each records its outcome, including a zero-change one, as a
> process record.
> Body: list only files actually created or updated. Skip files that were
> inspected, considered, or deliberately left unchanged, and do not narrate
> decisions about what not to do. Aim for roughly 20 lines per entry.
> When this file exceeds 500 entries, rotate: rename to log-YYYY.md, start fresh.

## [{{TODAY}}] create | Wiki initialized

- Domain: [to be configured in SCHEMA.md]
- Structure created with SCHEMA.md, index.md, log.md, raw/, entities/, concepts/, comparisons/, queries/, summaries/, procedures/
