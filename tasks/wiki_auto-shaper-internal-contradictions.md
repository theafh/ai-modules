---
description: Reconcile two auto_shaper_wiki self-contradictions: the lint-clean exit criterion its own contested-page protocol makes unreachable, and stale body-Sources anatomy references the linter deprecates.
scope: plugins/knowledge_management
created: 2026-07-19T18:51:20
updated: 2026-07-29T21:54:35
status: checked
reported-by: Andreas Hoffmann
---

# Reconcile auto_shaper_wiki's exit criterion and stale anatomy references

## Goal

The `auto_shaper_wiki` agent's rules stop contradicting the canon it enforces. Its clean-exit criterion tolerates the warn findings its own contested-page protocol necessarily produces, so an audit that finds a genuine cross-page contradiction can terminate honestly instead of facing an unreachable "no warn findings" bar. And its two surviving references to a body "Sources" section are rewritten to the current page anatomy, so the agent stops being instructed to add the exact section the linter flags as deprecated.

## Context

Both defects live in [agents/auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md).

**Unreachable exit criterion.** The chain: the `<fix_cross_page_contradiction>` move mandates setting `contested: true` on every side of a found contradiction; the linter's `check_quality_signals` emits a **warn** for each `contested: true` page ("contested: true — reconcile or document the dispute" — verified on a fixture); the `<lint_clean>` objective and `<relint_until_clean>` verify step both require iterating "until the script exits 0 with no blocking or warn findings", with an intentional-finding carve-out for info level only; and `<leave_contested_pages>` forbids resolving contested pages ("The agent flags them; the human resolves them"). So the moment the agent correctly applies its own protocol it creates a warn it is forbidden to clear, while `<run_until_done>` tells it not to stop early. The `<final_line>` contract ("K contested pages flagged") shows completion-with-contested-pages was always intended — the exit criterion just never got the carve-out. For an autonomous writer this is a real hazard: the pressure of "reach zero warns" points at un-marking contested pages, the one outcome the human-review protocol exists to prevent.

**Stale body-Sources anatomy.** The `<section_order_or_gaps>` check names "an `entity` page with no Sources" as a missing-required-section example, and `<fix_procedure_vs_concept_misclassification>` specifies the summary anatomy as "Topic and scope · Key findings by sub-topic · Open threads · Sources". The current canon says the opposite everywhere else: the "Page anatomy" table in [skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) lists no Sources section for any type and states "pages do not carry a separate body 'Sources' section"; [references/template_schema.md](../plugins/knowledge_management/skills/wiki/references/template_schema.md) matches; the linter's `check_sources_section` flags the heading as deprecated; and the agent's own `<fix_external_source_pointer>` exists to remove or rename it. An agent obeying the two stale lines manufactures the exact section another of its own checks then flags — add/flag/remove churn across audits, plus wrong section scaffolding applied during procedure-to-summary relocations.

Co-edit coordination: [wiki_meta-prose-in-page-bodies.md](wiki_meta-prose-in-page-bodies.md) drops the "on the page's body or" wording from the same `<relint_until_clean>` block this task rewrites — coordinate so both edits land coherently in that block.

## Approach

1. **Exit-criterion carve-out.** Rewrite `<lint_clean>` and `<relint_until_clean>` in place so the clean bar reads: lint exits 0 with no blocking findings and no warn findings other than the `quality` warns on pages this audit marked or confirmed `contested:` — those persist by design for human review per `<leave_contested_pages>` and are surfaced in the final report. Keep the info-level intentional-finding carve-out as is. Phrase the criterion once and have the second occurrence reference the first, so the two spots cannot drift apart again.
2. **Anatomy repairs.** Rewrite the `<section_order_or_gaps>` entity example to one the anatomy table supports (for example, an `entity` page with no Relationships section), and rewrite the summary anatomy inside `<fix_procedure_vs_concept_misclassification>` to end at "Open threads", matching the SKILL.md table.

**Out of scope:**

- Changing the linter's warn severity for `contested: true` — that warn is the designed human-review surface; the agent's criterion adapts to it, not the reverse.
- Any change to the contested-page protocol itself (marking both sides, never picking a winner).

## Acceptance

1. `rg "no blocking or warn findings" ../plugins/knowledge_management/agents/auto_shaper_wiki.md` shows the bare phrase superseded in both `<lint_clean>` and `<relint_until_clean>` by the contested-warn carve-out, stated once and referenced from the second site.
2. `rg "page with no Sources" ../plugins/knowledge_management/agents/auto_shaper_wiki.md` returns no match, and the replacement example names a section the "Page anatomy" table actually requires for `entity`.
3. `rg "Open threads · Sources" ../plugins/knowledge_management/agents/auto_shaper_wiki.md` returns no match, and the summary anatomy in `<fix_procedure_vs_concept_misclassification>` matches the SKILL.md table verbatim.
4. A behavior scenario in the wiki test harness stages a fixture wiki with one genuine cross-page contradiction and runs the audit flow: both pages end `contested: true`, neither body is merged or hedged, the run terminates with the final line reporting at least one contested page, and the scenario fails against the current agent text (which cannot satisfy its own exit bar) while passing with the rewrite.
5. `tests/wiki/run_all.sh` passes.
