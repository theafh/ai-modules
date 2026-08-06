---
description: Extend the log template's verbatim-enforced action enum to cover the shipped writers — audit, import, session-wrapup — so the plugin's own components stop writing off-enum log entries.
scope: plugins/knowledge_management
created: 2026-07-19T18:51:20
updated: 2026-08-05T19:47:00
status: implemented
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Cover every shipped log writer in the log template's action enum

## Goal

The action enum declared in the log template's preamble names every entry action the plugin's own components write. Today three shipped writers fall outside it, and the verbatim-boilerplate enforcement locks the gap in place: a wiki owner cannot extend the enum without tripping a warn, and the audit agent actively reverts such an extension. After this task, the canonical enum and the shipped writers agree, and the standard scaffold-alignment path propagates the corrected preamble to existing wikis.

## Context

[references/template_log.md](../plugins/knowledge_management/skills/wiki/references/template_log.md) declares: "Actions: ingest, update, query, lint, create, archive, delete". Three components permanently write entries outside that set:

- the `auto_shaper_wiki` agent's `<append_audit_log_entry>` writes an `audit |` entry on every completed audit, including clean ones ([agents/auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md));
- `wiki_import` appends an `import |` entry ([skills/wiki_import/SKILL.md](../plugins/knowledge_management/skills/wiki_import/SKILL.md));
- `wiki_wrapup` appends a `session-wrapup |` entry ([skills/wiki_wrapup/SKILL.md](../plugins/knowledge_management/skills/wiki_wrapup/SKILL.md)).

The gap cannot be fixed wiki-side: the linter's `boilerplate` check enforces the `log.md` preamble verbatim against the template, and the agent's `<fix_log_preamble_drift>` move instructs "Restore the canonical preamble lines (entry format, action enum, …)" — so an owner who adds `audit` to their own preamble gets a warn and then has the edit reverted at the next audit. The template line is the only legitimate edit point.

Editing the template makes every existing wiki's preamble drift (one warn) until its next audit aligns it — the designed propagation path, as [wiki_log-entries-only-on-changes.md](archive/wiki_log-entries-only-on-changes.md) documents in its Ripple note. That sibling has shipped its rewrite of this exact preamble region (change-scoped header wording, an added `Entries:` sentence, `query` kept in the enum), so word the Actions line once against that current preamble text.

## Approach

Rewrite the "Actions:" line in `template_log.md` in place so the enum lists the current writer set: the existing seven actions plus `audit`, `import`, and `session-wrapup`. Align that same `Actions:` line in every durable harness copy at `tests/wiki/layer2/*/HOME/**/wiki/log.md` (exclude `workspace/`) to the new enum — edit those lines in place, or restage with `setup_scenarios.sh`, which rematerializes them through `init_wiki.sh`. Layer1 scratch trees rematerialize from the template under `run_all.sh` and need no separate Actions edit. No enforcement change — the preamble stays a verbatim slot, which is exactly what propagates the corrected line outward.

**Out of scope:**

- Renaming the writers' actions onto existing enum words (an `audit` entry filed as `lint`, a `session-wrapup` filed as `ingest`) — that erases the distinction the entries exist to record.
- Scoping the Actions line out of the verbatim-enforced region — that weakens the boilerplate guarantee for the whole preamble to solve a one-line staleness.
- Making the linter validate entry actions against the enum — the enum is documentation for writers; enforcement of entry bodies is not established anywhere today and would be new scope.

## Acceptance

1. The "Actions:" line in `template_log.md` lists `audit`, `import`, and `session-wrapup` alongside the pre-existing actions, as one canonical line (no second Actions line or appended addendum).
2. A fixture wiki materialized from the updated template passes the linter's boilerplate check with no preamble finding — the materialized `log.md` preamble equals the template preamble above the first `##` heading.
3. The shipped wording from [wiki_log-entries-only-on-changes.md](archive/wiki_log-entries-only-on-changes.md) survives this task's edit: the preamble still carries the change-scoped rule and its `Entries:` sentence, and `rg "all wiki actions"` on the template still returns no match.
4. Every non-workspace `tests/wiki/layer2/*/HOME/**/wiki/log.md` carries the new canonical `Actions:` line matching `template_log.md`, and `tests/wiki/run_all.sh` passes.
