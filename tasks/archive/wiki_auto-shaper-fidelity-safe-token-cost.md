---
description: Cut auto_shaper_wiki token cost via a safe orient-phase trim and change-scoped page reads, while preserving every reflective prose check the linter cannot catch.
scope: plugins/knowledge_management
created: 2026-06-27T11:12:00
updated: 2026-07-30T11:23:55
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Cut auto_shaper_wiki token cost without weakening the reflective prose audit

## Goal

A `auto_shaper_wiki` run consumes fewer tokens — both the fixed per-run orientation cost and the cost that scales with wiki size — while still detecting every prose-level issue it detects today. Two facets ship together: the orientation phase stops unconditionally reading large reference files it can derive on demand, and the per-page audit walk stops re-reading unchanged pages every run by scoping reads to what changed rather than to wiki size. Audit fidelity is the hard constraint: the reflective checks that only surface when a model reads a page's prose keep running on every page that needs them.

## Context

The load-bearing fact is the split between mechanical and reflective checks. The bundled linter (`scripts/lint.py`, matrix in `references/lint_checks.md`) validates structure only — frontmatter, link resolution, file location, tag membership, sha256, size, markdown style. Of the agent's fourteen assess-phase checks only four are mechanically or diff-detectable (`cross_link_starvation`, `wrong_directory_for_declared_type`, `raw_subtree_drift`, `scaffold_drift`). The other ten are reflective: they carry no reliable grep signature and the linter never produces them — `topic_mixing`, `type_anatomy_mismatch`, `section_order_or_gaps`, `procedure_instance_leakage`, `procedure_vs_concept_misclassification`, `tag_drift`, `provenance_violation`, `external_source_pointer`, `confidence_violation`, and `cross_page_contradiction`. For those ten the full read of the page is the audit; a clean lint result is silent on all of them. The wiki skill states this in its `<broad_audits>` note: the agent "audits the prose for issues the linter cannot see".

Files this task edits or relies on:

- Agent: `plugins/knowledge_management/agents/auto_shaper_wiki.md` — orient phase `<read_canonical_references>` and the `<read_schema>` / `<read_index>` / `<read_recent_log>` reads; assess phase `<page_first_iteration>` and `<scaffold_drift>`; policy `<single_orientation_pass>`, `<iterate_page_first_not_check_first>`, `<run_until_done>`.
- Rubric the reflective checks consume: `plugins/knowledge_management/skills/wiki/SKILL.md` — the "Page anatomy" table, "Page Types: Pick by Question", "Capture Procedure" (the strip-the-name test), the procedure-vs-concept discriminator, and "Page thresholds".
- Linter ground truth: `plugins/knowledge_management/skills/wiki/scripts/lint.py` and `references/lint_checks.md`.
- Regression harness: `tests/wiki/run_all.sh`.

This task supersedes [the deferred grep-first attempt](wiki_auto-shaper-read-token-cost.md), which proposed grep-first reads and skipping the walk when lint is clean. That approach was deferred because it would drop the reflective ten silently; reading it shows the rejected mechanism and the original cost diagnosis this task carries forward.

## Approach

Facet 1 — orient-phase trim (safe, can land first). Rewrite `<read_canonical_references>` so the canonical templates (`template_schema.md`, `template_index.md`, `template_log.md`), `init_wiki.sh`, and `raw_taxonomy.md` are read on demand rather than unconditionally in full. The `diff -u` invocations in `<scaffold_drift>` already produce the authoritative scaffold comparison, so a template is read only to interpret a specific diff hunk — notably a whole-section deletion hunk, where classifying canonical drift versus a preserved customization needs the template body. Read `$WIKI_SKILL/SKILL.md` by its contiguous semantic block — the region running from the folder-layout and page-type material through the "Page anatomy" table, plus the "Capture Procedure" tests — rather than the whole file, and read the "Page thresholds" figure when a size finding needs it. Keep unconditional: the `<read_schema>` / `<read_index>` / `<read_recent_log>` full reads of the wiki's own SCHEMA, index, and log, and all three `diff -u` calls in `<scaffold_drift>`.

Facet 2 — page-walk reads scoped to change, not wiki size (fidelity-preserving). Make the number of full cold page reads a function of what changed since the last audit, so every page still receives one cold full read across its lifetime and a clean re-run over an unchanged large wiki does not re-read every page:

- Incremental working-set scoping: derive the pages new or changed since the last recorded audit — from the last `audit` entry in `log.md` and/or a `git` comparison against that point — and give those the full page-first cold walk. A page unchanged since it last passed a cold walk is not re-read.
- First-audit and unknown-baseline fallback: when no prior audit baseline exists, the working set is every page (today's behaviour); the saving begins on the second audit.
- Clean-audit baseline record: every completed audit, including one that finds nothing to fix, appends a zero-change `audit` outcome entry carrying the baseline and cold-read set, so the saving begins on the second audit even when the first audit was clean on arrival. Without it a clean audit leaves no baseline and the next run re-reads the whole wiki. This is the sanctioned process record [wiki_log-entries-only-on-changes.md](wiki_log-entries-only-on-changes.md) preserves when it scopes the log to content changes.
- Optional parallelism: spread the cold per-page reads across parallel per-page sub-agents to amortise token and latency cost. This preserves the `<iterate_page_first_not_check_first>` cold-verdict independence, since each page is judged in its own context.
- Grep stays an additive prefilter only, for `procedure_instance_leakage`'s lexical subset (dates, paths, proper nouns): a grep hit adds a page to the read set, and a grep miss never removes a page from the cold walk.
- `cross_page_contradiction` reads both sides of a same-subject pair whenever either side is in the working set.

Non-goals, rejected — do not implement any of these, because each drops reflective findings with no signal to the user: grep-first gating that makes a grep hit the precondition for reading a page; skipping the page walk when lint returns zero; and any numeric or wiki-size-scaled read cap that lets an unread page be declared clean. Keep `<single_orientation_pass>` and `<run_until_done>` intact, revising their wording only where the orient trim or working-set scoping changes what they describe.

## Acceptance

- Orientation trim: on a run where `<scaffold_drift>`'s `diff -u` of SCHEMA, index, and log shows no hunks, the agent issues no full read of `template_schema.md`, `template_index.md`, `template_log.md`, `init_wiki.sh`, or `raw_taxonomy.md`, and no whole-file read of `$WIKI_SKILL/SKILL.md`; the three `diff -u` calls and the full `<read_schema>` / `<read_index>` / `<read_recent_log>` reads still run. Verify against the rewritten `<read_canonical_references>` text and an audit-run trace over a fixture wiki.
- Edit supersedes: the rewritten `<read_canonical_references>` no longer carries the prior "read … in full" unconditional mandate, and one canonical on-demand statement remains in its place.
- Reflective detection preserved: on a fixture wiki seeded with at least one ungreppable offender — a `cross_page_contradiction` between two pages and a `procedure_vs_concept_misclassification` page that carries no anomalous token — an audit run flags both. This is the regression guard the deferred grep-first approach failed.
- Incremental scoping: on a fixture wiki already audited clean once, a second run with exactly one page edited to introduce an ungreppable defect reads that page in full and flags it, while not issuing a full read of every unchanged page. Record the read set for both runs as the measurement.
- Clean-audit baseline: a clean audit (lint 0, no semantic findings) skips remediate but still appends its zero-change `audit` outcome entry recording the baseline and cold-read set, so a second audit of an unchanged clean wiki scopes incrementally instead of re-reading every page. Verify against the `<compile_issue_list>` clean path and `<append_audit_log_entry>`, and by a clean-run → edit-one-page → re-run trace whose second run reads only the edited page.
- First-audit fallback: on a fixture wiki with no prior `audit` entry in `log.md`, the working set is every page, with no silent reduction below full coverage on the first pass.
- No banned mechanism present: the agent text contains no grep-gated page selection, no skip-the-walk-when-lint-clean clause, and no size-scaled read cap, and `<iterate_page_first_not_check_first>` still forbids letting any one check gate the others.
- `tests/wiki/run_all.sh` passes with no regression in audit outcomes.
