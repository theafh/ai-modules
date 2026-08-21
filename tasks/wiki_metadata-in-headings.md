---
description: Keep wiki headings and bold-prefix labels structural, route displaced metadata (date, source, qualifier) to its proper channel, and lint both heading-label heuristics (length; ISO-date) at info.
scope: plugins/knowledge_management
created: 2026-05-28T19:24:35
updated: 2026-08-21T17:28:10
status: ready
reported-by: Andreas Hoffmann
---

# Stop stuffing metadata into wiki headings and bold labels

## Goal

Markdown headings and bold-prefix labels in wiki pages stay *structural*: each names the section's own subject, and where a wiki's `SCHEMA.md` declares a label vocabulary the labels match it verbatim, so readers navigate by skim and `grep`. Metadata — date, source, session ID, audience, qualifier, mandate level, scope tag — is *semantic content* and belongs in a separate channel (frontmatter, per-claim inline link, `raw/` sidecar, audit-log entry). After this task, the `auto_shaper_wiki` agent and `SKILL.md` `<write_or_update_pages>` refuse to augment headings or labels with parenthesised metadata, and `lint.py` surfaces both Approach `heading-label` heuristics as info-level findings.

## Context

This is one of a family of **generalisable refinements** to the wiki skills + `auto_shaper_wiki` agent. The trigger was a concrete friction point surfaced while auditing a real wiki, but the rule is stated globally so it applies to every user of the wiki skills, not just the originating case.

During that audit the auto-shaper normalised eight section labels and produced strings like:

- `**What the canon says (2026-01-15 triage session):**`
- `**What the canon says (2026-01-15 design review session):**`

The user called this "overcompression beyond recognition" — the label vocabulary is structural, the parenthesised attribution is content that belongs elsewhere.

Files involved:

- [plugins/knowledge_management/agents/auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md) — `<remediate>` section.
- [plugins/knowledge_management/skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) — `<write_or_update_pages>` and `<narrow_inline_checks>` severity summary.
- [plugins/knowledge_management/skills/wiki/references/lint_checks.md](../plugins/knowledge_management/skills/wiki/references/lint_checks.md) — lint check matrix and severity buckets.
- [plugins/knowledge_management/skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) — heading/label lint.

Related tasks: [wiki_two-pass-normalisation.md](archive/wiki_two-pass-normalisation.md) authors the general "two-pass remediation" rule — route displaced semantics, then normalise — as the family's single statement of it. This task is the heading-specific surface and cites that rule by name, so it depends on the named rule existing: build two-pass first, or land both together. The two also co-edit the agent's `<remediate>` section, so coordinate the wording where the edits meet. [wiki_page-type-growth-and-anatomy.md](wiki_page-type-growth-and-anatomy.md) owns clarifying how a custom page-type anatomy names its structural labels (Approach **Custom-type anatomy rule in `template_schema.md`**; Acceptance **Fixture D**); this task consumes that declaration shape for SCHEMA label vocabulary and does not re-author it.

## Approach

1. **`plugins/knowledge_management/agents/auto_shaper_wiki.md` `<remediate>` section** — name headings and bold-prefix labels as structures the "two-pass remediation" rule governs, citing that rule rather than restating its routing steps; [wiki_two-pass-normalisation.md](archive/wiki_two-pass-normalisation.md) authors it as the family's single statement, and a second copy here is the duplication the repo's author-once convention exists to prevent. What this task states on its own is the heading-specific half: take the label vocabulary from the target wiki's SCHEMA where it defines one rather than inventing terms. **SCHEMA label vocabulary (stated once here):** a wiki declares a label vocabulary when its SCHEMA page-type anatomy sections name the structural labels entries must use (bold-prefix / section label strings), not merely describe section content. The shipped `template_schema.md` page-type anatomies describe content rather than fixing verbatim labels, so a fixed vocabulary exists only when a given wiki's SCHEMA names those labels (the originating wiki's did). Sibling [wiki_page-type-growth-and-anatomy.md](wiki_page-type-growth-and-anatomy.md) Approach **Custom-type anatomy rule in `template_schema.md`** / Acc **Fixture D** owns clarifying that custom-type anatomies must name their session-derived-source label; this task reads that named-label shape as the vocabulary signal and does not invent a separate SCHEMA `## Label Vocabulary` channel. Without a declared vocabulary, leave the label wording alone and route only the displaced metadata. **`<fix_heading_label>` (stated once here):** under `<fix_moves>`, add `<fix_heading_label>` keyed to lint category `heading-label`. Parenthesised / ISO-date-suffix findings are remediative — cite the "two-pass remediation" rule by that verbatim name and apply **SCHEMA label vocabulary (stated once here):**. Length-only findings are acceptable info and may remain without remediative clearing.
2. **`plugins/knowledge_management/skills/wiki/SKILL.md`** — rewrite `<write_or_update_pages>` so it refuses parenthesised metadata on headings and bold-prefix labels, mirroring the agent rule without restating the family's "two-pass remediation" routing steps; rewrite `<narrow_inline_checks>` so its info-bucket summary names the new heading/label checks in lockstep with the matrix.
3. **`plugins/knowledge_management/skills/wiki/references/lint_checks.md`** — add a matrix row for the new heading/label checks and list them under the **info** severity bucket so the reference remains the structural source of truth for what `lint.py` emits.
4. **`plugins/knowledge_management/skills/wiki/scripts/lint.py`** — add info-level heuristics under category `heading-label` (both checks share that category) flagging either of:
   - A heading line at H2 or deeper (`^#{2,6}\s`), or a bold-label line (`^\*\*.*\*\*:?\s*$`), whose **structural text** — the visible label after stripping leading markdown heading markers (`#{2,6}` + following space) or bold wrappers (`**` … `**`) and an optional trailing `:`, not the full raw line — is longer than 60 characters. **H1 is exempt from the length rule**, because a page title follows its type anatomy rather than a section-label vocabulary: a `query` page carries its question verbatim as the title — required by both the "Page anatomy" table in `SKILL.md` and the `## Query Pages` section of `template_schema.md` — so a correctly written query title routinely runs past 60 characters and the rule would flag it. Length is also not what catches the labels in Context (those run ~52 characters of structural text); the date-suffix rule is, which is why the length rule can narrow without weakening the task.
   - A heading at any level, or a bold-label line, carrying a parenthesised ISO-date suffix matching the regex `\([0-9]{4}-[0-9]{2}-[0-9]{2}.*?\)`. This is the lint half only — ISO-date-parenthetical detection — not a general parenthesised-metadata detector; broader refusal stays in the agent and `<write_or_update_pages>`.

   Surface both checks as `info`-level, not blocking — the script exits 0 when only info findings remain, so the wider workflow can land an edit that contains a violation while warning the author.
5. **Harness placement** — stage `lint.py` proofs under `tests/wiki/layer1` as new `l*_lint_*` scenarios driven by `layer1/run.sh`. Stage the two `wiki_fix` / `auto_shaper_wiki` behavioural fixtures as Layer-2 scenarios **AS-6** (SCHEMA declares a label vocabulary) and **AS-7** (SCHEMA declares none): register each in `tests/wiki/layer2/evals.json` and add matching `stage_AS-6` / `stage_AS-7` blocks in `tests/wiki/layer2/setup_scenarios.sh` following the existing AS-* registration pattern, so `tests/wiki/run_all.sh --layer2` exercises both new scenarios.

## Acceptance

- The agent `<remediate>` text and `SKILL.md` `<write_or_update_pages>` refuse parenthesised metadata on headings and bold-prefix labels; the agent's `<fix_moves>` carries `<fix_heading_label>` for category `heading-label` with dispositions per Approach **`<fix_heading_label>` (stated once here):**; the agent's heading-normalisation text cites the "two-pass remediation" rule by that verbatim name instead of restating its routing steps. `lint.py` implements only the Approach heuristics (H2+/bold-label length on structural text; ISO-date parenthetical) under category `heading-label` — full refusal stays in agent/`<write_or_update_pages>`; the lint half is the ISO-date heuristic only.
- `references/lint_checks.md` carries a matrix row for the new checks (category `heading-label`) and names them under the info severity bucket; `SKILL.md` `<narrow_inline_checks>` names the same checks in its info summary (prior passages that omit them are superseded).
- Layer-1 (`l*_lint_*`): a fixture `query` page whose verbatim-question H1 exceeds 60 characters of structural text draws no `heading-label` length finding, while an H2 on the same page whose structural text exceeds 60 characters does (info `heading-label`).
- Layer-1 (`l*_lint_*`): a bold-label line whose structural text is longer than 60 characters draws an info `heading-label` length finding.
- Layer-1 (`l*_lint_*`): an H1, an H2-or-deeper heading, and a bold-label line each carrying a parenthesised ISO-date suffix (`(YYYY-MM-DD…)`) draw the info `heading-label` date-suffix finding.
- Layer-1 (`l*_lint_*`): a wiki whose only findings are those info `heading-label` hits exits 0.
- Layer-2 **AS-6** (registered in `evals.json` + `setup_scenarios.sh`): fixture wiki with mixed-source entries carrying parenthesised attribution suffixes, and a SCHEMA that declares a label vocabulary per Approach **SCHEMA label vocabulary (stated once here):** → after `wiki_fix`:
  - Labels match the SCHEMA vocabulary verbatim (no parenthetical attribution).
  - Displaced metadata appears in `sources:` or a `raw/` sidecar.
  - The audit report names the routing as part of the per-file change list.
  - Remediative clearing of parenthesised attribution used `<fix_heading_label>` per Approach **`<fix_heading_label>` (stated once here):**; length-only `heading-label` info findings may remain.
- Layer-2 **AS-7** (registered in `evals.json` + `setup_scenarios.sh`): fixture wiki whose SCHEMA declares no label vocabulary per Approach **SCHEMA label vocabulary (stated once here):** → after `wiki_fix`, label wording is left alone aside from routing displaced metadata (no invented vocabulary).
- `tests/wiki/layer1/run.sh` covers the new `l*_lint_*` scenarios; `tests/wiki/run_all.sh --layer2` exercises AS-6 and AS-7 and both pass.
