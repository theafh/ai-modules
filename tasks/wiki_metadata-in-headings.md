---
description: Keep wiki headings and bold-prefix labels structural, route displaced metadata (date, source, qualifier) to its proper channel, and lint parenthesised-date suffixes at info level.
scope: plugins/knowledge_management
created: 2026-05-28T19:24:35
updated: 2026-08-05T19:37:26
status: open
reported-by: Andreas Hoffmann
---

# Stop stuffing metadata into wiki headings and bold labels

## Goal

Markdown headings and bold-prefix labels in wiki pages stay *structural*: each names the section's own subject, and where a wiki's `SCHEMA.md` declares a label vocabulary the labels match it verbatim, so readers navigate by skim and `grep`. Metadata — date, source, session ID, audience, qualifier, mandate level, scope tag — is *semantic content* and belongs in a separate channel (frontmatter, per-claim inline link, `raw/` sidecar, audit-log entry). After this task, the `auto_shaper_wiki` agent and the wiki authoring contract refuse to augment headings or labels with parenthesised metadata, and the lint surfaces such augmentation as an info-level finding.

## Context

This is one of a family of **generalisable refinements** to the wiki skills + `auto_shaper_wiki` agent. The trigger was a concrete friction point surfaced while auditing a real wiki, but the rule is stated globally so it applies to every user of the wiki skills, not just the originating case.

During that audit the auto-shaper normalised eight section labels and produced strings like:

- `**What the canon says (2026-01-15 triage session):**`
- `**What the canon says (2026-01-15 design review session):**`

The user called this "overcompression beyond recognition" — the label vocabulary is structural, the parenthesised attribution is content that belongs elsewhere.

Files involved:

- [plugins/knowledge_management/agents/auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md) — `<remediate>` section.
- [plugins/knowledge_management/skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) — authoring contract.
- [plugins/knowledge_management/skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) — heading/label lint.

Related tasks: [wiki_two-pass-normalisation.md](wiki_two-pass-normalisation.md) authors the general "two-pass remediation" rule — route displaced semantics, then normalise — as the family's single statement of it. This task is the heading-specific surface and cites that rule by name, so it depends on the named rule existing: build two-pass first, or land both together. The two also co-edit the agent's `<remediate>` section, so coordinate the wording where the edits meet.

## Approach

1. **`plugins/knowledge_management/agents/auto_shaper_wiki.md` `<remediate>` section** — name headings and bold-prefix labels as structures the "two-pass remediation" rule governs, citing that rule rather than restating its routing steps; [wiki_two-pass-normalisation.md](wiki_two-pass-normalisation.md) authors it as the family's single statement, and a second copy here is the duplication the repo's author-once convention exists to prevent. What this task states on its own is the heading-specific half: take the label vocabulary from the target wiki's SCHEMA where it defines one rather than inventing terms. The canonical SCHEMA template's page-type anatomies describe section content, not verbatim labels, so a fixed label vocabulary exists only when a wiki's SCHEMA declares it (the originating wiki's did); without one, leave the label wording alone and route only the displaced metadata.
2. **`plugins/knowledge_management/skills/wiki/SKILL.md`** — mirror the rule in the authoring contract.
3. **`plugins/knowledge_management/skills/wiki/scripts/lint.py`** — add an info-level heuristic flagging either of:
   - A heading line at H2 or deeper (`^#{2,6}\s`), or a bold-label line (`^\*\*.*\*\*:?\s*$`), longer than 60 characters. **H1 is exempt from the length rule**, because a page title follows its type anatomy rather than a section-label vocabulary: a `query` page carries its question verbatim as the title — required by both the "Page anatomy" table in `SKILL.md` and the `## Query Pages` section of `template_schema.md` — so a correctly written query title routinely runs past 60 characters and the rule would flag it. Length is also not what catches the labels in Context (those run ~52 characters); the date-suffix rule is, which is why the length rule can narrow without weakening the task.
   - A heading at any level, or a bold-label line, carrying a parenthesised date or qualifier suffix matching the regex `\([0-9]{4}-[0-9]{2}-[0-9]{2}.*?\)` (also catch shorter forms like `(2026-01-15 ...)`).

   Surface both checks as `info`-level, not blocking — the wider workflow should be able to land an edit that contains a violation while warning the author.

## Acceptance

- The agent, `SKILL.md`, and `lint.py` carry the rule and the lint heuristic, and the agent's heading-normalisation text cites the "two-pass remediation" rule by that verbatim name instead of restating its routing steps.
- A fixture `query` page whose verbatim-question H1 exceeds 60 characters draws no length finding, while an over-60-character H2 on the same page does.
- Fixture wiki with mixed-source entries carrying parenthesised attribution suffixes → after `wiki_fix`:
  - The fixture wiki's SCHEMA declares a label vocabulary; labels match it verbatim (no parenthetical attribution).
  - Displaced metadata appears in `sources:` or a `raw/` sidecar.
  - The audit report names the routing as part of the per-file change list.
- `tests/wiki/run_all.sh --layer2` passes.
