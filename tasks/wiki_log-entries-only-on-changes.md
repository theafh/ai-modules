---
description: Make the wiki log contract single-voiced: log.md entries only when wiki files changed — fix the query step, log-template preamble, and schema-template every-action rule.
scope: plugins/knowledge_management
created: 2026-06-11T17:46:27
updated: 2026-06-11T17:46:27
status: open
reported-by: Andreas Hoffmann
---

# Log entries only on wiki changes

## Goal

The wiki skill's logging contract becomes single-voiced: `log.md` gains an
entry exactly when an operation created or updated wiki files, and a
read-only query session leaves `log.md` byte-identical. This is the general
behaviour definition whose absence caused the motivating incident (see
Context); the fix lands in the skill prose and templates, not as a
point-patch for one session.

## Context

The skill currently states two contradictory rules about query logging, and
an agent can comply with either while violating the other:

- `plugins/knowledge_management/skills/wiki/SKILL.md`, `<query>` section,
  final step: "Update `log.md` with the query and whether it was filed" —
  mandates a log write even when the query filed nothing, and mandates
  narrating the not-filed decision.
- Same file, `<update_navigation>` (inside `<ingest>`): "List only files
  actually created or updated … do not narrate decisions about what *not*
  to do", echoed by the `<log_only_what_changed>` pitfall: "never narrate
  inspected-but-unchanged files or 'did not edit' decisions".

The bundled templates encode the same conflation of *action* with *change*:

- `plugins/knowledge_management/skills/wiki/references/template_log.md`
  preamble: "Chronological record of all wiki actions" with the action enum
  `ingest, update, query, lint, create, archive, delete` — three lines above
  its own "list only files actually created or updated" body rule.
- `plugins/knowledge_management/skills/wiki/references/template_schema.md`,
  conventions list: "Every action must be appended to `log.md`".

Motivating incident (2026-06-09, a personal German-language wiki): a query
session answered from a 12-page synthesis, filed no page, told the user so —
and its only file write in the whole session was a `log.md` append whose
body line read "Nicht als Query-Page gefiled" (not filed as a query page).
A sibling session the same evening answered the same question and wrote
nothing at all. Both behaviours are defensible readings of the
contradictory instructions above.

Ripple: the linter's boilerplate check (`references/lint_checks.md`,
`boilerplate` row) enforces the `log.md` preamble verbatim against
`template_log.md`, and the `wiki_auto_shaper` agent diffs and aligns that
preamble during audits. Editing the template therefore makes every existing
wiki's preamble drift (warn) until its next audit pass aligns it — the
designed propagation path, no extra action needed here.

Related tasks:

- [wiki_log-rotation-and-retrieval](wiki_log-rotation-and-retrieval.md) —
  co-edits the same `template_log.md` preamble region (rotation rule) and
  the SKILL.md log-handling prose; coordinate the preamble wording if both
  land near each other.
- [wiki_query-page-filing-decision](wiki_query-page-filing-decision.md) —
  co-edits the same `<query>` numbered workflow; its mandatory one-line
  in-chat report becomes the only trace of an unfiled query once this task
  removes the log trace. Implement that task after or together with this
  one.

## Approach

Rewrite the three contradictory statements in place (one source of truth
per rule; the changes-only rule already lives in `<update_navigation>` and
the `<log_only_what_changed>` pitfall — the other passages align to it):

1. **`<query>` final step** (SKILL.md): a query that filed a page or
   updated pages appends one `query` log entry listing those files; a query
   that changed no files appends nothing — the one-line in-chat report
   (sibling task above) is its only trace.
2. **`template_log.md` preamble**: replace "Chronological record of all
   wiki actions" with change-scoped wording (e.g. "Chronological record of
   wiki changes") and add one sentence stating that operations which change
   no files write no entry. Keep `query` in the action enum — it stays
   legitimate for queries that filed pages.
3. **`template_schema.md` conventions**: replace "Every action must be
   appended to `log.md`" with change-scoped wording aligned to the
   preamble.

Constraint: zero-change `lint` and `audit` *outcome* entries (the
`<inline_iteration_loop>` outcome line in SKILL.md and the
`wiki_auto_shaper` audit entry) are deliberate process records produced by
a different mechanism than content operations. Word the preamble so the
changes-only rule governs content operations without outlawing those
outcome entries.

Open decision: whether zero-change `lint`/`audit` outcome entries remain
sanctioned at all. Default an implementer takes without further input: they
remain — removing them would ripple into `wiki_auto_shaper` and the
existing audit-trail convention, which is out of this task's scope.

## Acceptance

1. `rg "whether it was filed" plugins/knowledge_management/skills/wiki/SKILL.md`
   returns no match, and the `<query>` workflow's log step conditions the
   log write on files created or updated by the query.
2. `rg "all wiki actions" plugins/knowledge_management/skills/wiki/references/template_log.md`
   returns no match, and the preamble states the changes-only rule plus the
   explicit no-entry handling for zero-change operations.
3. `rg "Every action must be appended" plugins/knowledge_management/skills/wiki/references/template_schema.md`
   returns no match, replaced by change-scoped wording.
4. Reading the `<query>` log step, `<update_navigation>`, and
   `<log_only_what_changed>` together yields one consistent rule; no
   sentence in the wiki skill instructs writing a log entry for a session
   that changed no wiki file.
5. A behaviour-layer scenario in the wiki test harness stages a fixture
   wiki, runs an answer-only query session (no page filed), and asserts
   `log.md` is byte-identical before and after (e.g. checksum comparison);
   the scenario fails against the current skill text and passes with the
   rewrite.
