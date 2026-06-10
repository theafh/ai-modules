---
description: Cut wiki_auto_shaper token consumption from unconditional full-file reads — make orient reads conditional and switch the page walk to Grep-first, bounded reads.
scope: plugins/knowledge_management
created: 2026-05-28T20:05:29
updated: 2026-06-10T22:05:12
status: open
---

# Stop the auto-shaper's unconditional full-file reads (orient + page walk)

## Goal

A `wiki_auto_shaper` run consumes far fewer tokens by not reading large files it does not need. Two phases change: orientation stops unconditionally reading the full SKILL plus every template, and the per-page audit walk stops reading every page in full when the linter already says where the issues are. Audit fidelity is preserved — the agent still reaches the same verdicts — but without the linear-in-wiki-size full-read cost.

## Context

Two phases of [agents/wiki_auto_shaper.md](../plugins/knowledge_management/agents/wiki_auto_shaper.md) read whole files unconditionally, and both costs scale badly:

1. **Orientation over-reads.** `<read_canonical_references>` (around lines 158-188) lists several full-file reads as mandatory orientation: the wiki `SKILL.md` (tens of KB), `template_schema.md`, `template_index.md`, `template_log.md`, `init_wiki.sh`, and `raw_taxonomy.md`. Immediately afterward, `<scaffold_drift>` (around lines 399-509) runs `diff -u` of the live `SCHEMA.md`/`index.md`/`log.md` against the same templates (lines ~412-418) — which is the authoritative line-level comparison. So the bulk template reads are largely redundant with a diff the agent runs anyway.

2. **Whole-wiki page reads even when lint is clean.** `<page_first_iteration>` (around lines 209-233) mandates walking the working set "page by page" with a full read of each page and is flagged load-bearing, so the agent will not shortcut it. When the linter returns zero blocking/zero warn, the agent still issues one full `Read` per page across the entire wiki and concludes each is clean — fixing nothing, at a cost that grows linearly with wiki size (hundreds of reads on a large wiki).

The prose-level checks that genuinely need page content (instance leakage on procedure pages, topic-mixing, cross-page contradictions) can be narrowed first with `Grep` across the tree, reading in full only the pages a grep flags. Structural checks are already the linter's job.

Files involved:

- [plugins/knowledge_management/agents/wiki_auto_shaper.md](../plugins/knowledge_management/agents/wiki_auto_shaper.md) — `<read_canonical_references>` (~158-188), `<page_first_iteration>` (~209-233), `<scaffold_drift>` (~399-509).

## Approach

1. **Make orient reads conditional.** In `<read_canonical_references>`, stop unconditionally reading every template in full. Rely on the `diff -u` in `<scaffold_drift>` for the authoritative scaffold comparison, and read a specific template only when a diff hunk needs interpreting. Read `SKILL.md` by the section the run needs (Grep/offset for the page-type enum, thresholds, etc.) rather than the whole file. Keep `raw_taxonomy.md` available but read on demand.
2. **Add a scaling clause to `<page_first_iteration>`.** Preserve the page-first verdict semantics (the agent still owns a per-page judgement) but change *how* it gathers evidence:
   - For prose-only checks (instance-content leakage, topic-mixing, contradiction detection), `Grep` the relevant patterns across the wiki first and `Read` in full only the pages the grep flags.
   - When the linter returns zero blocking and zero warn, do not full-read every page to re-confirm cleanliness; sample or skip the structural re-read and reserve full reads for pages the grep heuristics flag.
   - Cap the number of full-file reads, or scale the depth of the walk to wiki size, so a clean large wiki does not trigger hundreds of reads.
3. **Keep it explicit that this is an efficiency change, not a fidelity cut** — the agent must still detect the same prose-level issues; it just stops paying the full-read cost where the linter or a targeted grep already answers the question.

## Acceptance

- On a clean wiki (lint returns zero blocking/zero warn), an auto-shaper run does **not** issue a full `Read` of every page; full reads are bounded and reserved for grep-flagged pages.
- Orientation no longer reads every template in full unconditionally; the scaffold comparison still happens via `diff -u`.
- Prose-level issues (instance leakage, topic-mixing, contradictions) are still detected on a fixture wiki that contains them — the grep-first path flags and full-reads the offending pages.
- `tests/wiki/run_all.sh` passes with no regression in audit outcomes.
