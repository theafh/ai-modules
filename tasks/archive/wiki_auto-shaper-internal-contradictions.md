---
description: Reconcile two auto_shaper_wiki self-contradictions: the lint-clean exit criterion its own contested-page protocol makes unreachable, and stale body-Sources anatomy references the linter deprecates.
scope: plugins/knowledge_management
created: 2026-07-19T18:51:20
updated: 2026-08-05T19:00:38
status: ready
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

1. **Exit-criterion carve-out.** Rewrite `<lint_clean>` and `<relint_until_clean>` in place so the clean bar reads: lint exits 0 with no blocking findings and no warn findings other than every `quality` warn whose message is the contested dispute signal (`contested: true — reconcile or document the dispute`) on any page that remains `contested: true` at end of audit — whether marked this run or already contested before it — those persist by design for human review per `<leave_contested_pages>` and stay in the final report. Keep the info-level intentional-finding carve-out as is. Phrase the criterion once and have the second occurrence reference the first, so the two spots cannot drift apart again.
2. **Anatomy repairs.** Rewrite the `<section_order_or_gaps>` entity example to one the anatomy table supports (for example, an `entity` page with no Relationships section), and rewrite the summary anatomy inside `<fix_procedure_vs_concept_misclassification>` to end at "Open threads", matching the SKILL.md table.

**Harness baseline.** Add Layer 2 scenario `AS-5` and record its failure against the current agent text before rewriting the exit criterion; that failure is the pre-change baseline Acceptance item 4 measures against.

**Out of scope:**

- Changing the linter's warn severity for `contested: true` — that warn is the designed human-review surface; the agent's criterion adapts to it, not the reverse.
- Any change to the contested-page protocol itself (marking both sides, never picking a winner).
- Carve-outs for any other surface-for-human warn. The same hazard class has at least one more member — the linter's `raw-origin` warn on an irreducible origin-field conflict, which the agent's `<fix_raw_source_frontmatter_missing>` move surfaces for the user rather than fixes — but it is rarer and carries its own signal wording, so the carve-out here stays contested-only and that case gets its own task when it bites in practice.

## Acceptance

1. Against `../plugins/knowledge_management/agents/auto_shaper_wiki.md`, tag-scoped multiline checks prove the exit-criterion rewrite:
   - `rg -U --multiline-dotall '<lint_clean>[\s\S]*?blocking or warn[\s\S]*?findings[\s\S]*?</lint_clean>'` matches today (current no-warn bar) and returns no match after the rewrite; the same pattern scoped to `<relint_until_clean>` likewise matches today and returns none after.
   - After the rewrite, the contested-warn carve-out from Approach step 1 appears as the full clean-bar statement only inside `<lint_clean>`, and `<relint_until_clean>` references that `<lint_clean>` criterion without restating the carve-out.
   - The rewritten `<lint_clean>` carries Approach step 1's carve-out substance (the contested `quality` warn signal on every page that remains `contested: true` at end of audit, whether marked this run or already contested) and keeps the intentional info-level finding carve-out Approach step 1 preserves; [wiki_meta-prose-in-page-bodies.md](wiki_meta-prose-in-page-bodies.md) owns dropping "on the page's body or" from the same `<relint_until_clean>` block.
2. Against `../plugins/knowledge_management/agents/auto_shaper_wiki.md`, `rg -U 'entity` page with no\s+Sources'` returns no match (it matches today across the line break in `<section_order_or_gaps>`), and the replacement example in`<section_order_or_gaps>` names a section the "Page anatomy" table requires for `entity` (Relationships).
3. `rg "Open threads · Sources" ../plugins/knowledge_management/agents/auto_shaper_wiki.md` returns no match, and the summary anatomy in `<fix_procedure_vs_concept_misclassification>` matches the SKILL.md table verbatim.
4. Layer 2 scenario `AS-5` is registered in `tests/wiki/layer2/evals.json` and staged by `tests/wiki/layer2/setup_scenarios.sh` following the sibling `AS-*` pattern (`skill_name: wiki_fix`, out-of-band grading, top-level `passes` denominator). The fixture wiki has one genuine cross-page contradiction; assertions prove both pages end `contested: true`, neither body is merged or hedged, and the run's `<final_line>` reports `K >= 1` contested pages. Against the current agent text the scenario fails (unreachable clean bar); with the rewrite it reaches the all-passes-clean result across that `passes` denominator. When it misses the bar, the report carries the measured rate and diverging assertions and hands disposition to the user rather than re-running for a better draw.
