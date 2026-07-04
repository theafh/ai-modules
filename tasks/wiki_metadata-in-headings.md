---
description: Keep wiki headings and bold-prefix labels to a fixed structural vocabulary; route displaced metadata (date, source, qualifier) to its proper channel.
scope: plugins/knowledge_management
created: 2026-05-28T19:24:35
updated: 2026-07-04T14:43:36
status: open
reported-by: Andreas Hoffmann
---

# Stop stuffing metadata into wiki headings and bold labels

## Goal

Markdown headings and bold-prefix labels in wiki pages are *structural*: they match a small fixed vocabulary so readers can navigate by skim and `grep`. Metadata — date, source, session ID, audience, qualifier, mandate level, scope tag — is *semantic content* and belongs in a separate channel (frontmatter, per-claim inline link, `raw/` sidecar, audit-log entry). After this task, the `auto_shaper_wiki` agent and the wiki authoring contract refuse to augment headings or labels with parenthesised metadata, and the lint surfaces such augmentation as an info-level finding.

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

Related tasks: [wiki_two-pass-normalisation.md](wiki_two-pass-normalisation.md) (the routing of displaced semantics is the same mechanism applied to all normalisation cases, not just headings; this task is the heading-specific surface).

## Approach

1. **`plugins/knowledge_management/agents/auto_shaper_wiki.md` `<remediate>` section** — when normalising a heading or bold-prefix label, route displaced metadata (date, source, qualifier, audience, mandate level, scope tag) to its structured channel *before* applying the normalisation, and take the label vocabulary from the target wiki's SCHEMA where it defines one rather than inventing terms. The canonical SCHEMA template's page-type anatomies describe section content, not verbatim labels, so a fixed label vocabulary exists only when a wiki's SCHEMA declares it (the originating wiki's did); without one, leave the label wording alone and route only the displaced metadata.
2. **`plugins/knowledge_management/skills/wiki/SKILL.md`** — mirror the rule in the authoring contract.
3. **`plugins/knowledge_management/skills/wiki/scripts/lint.py`** — add an info-level heuristic flagging either of:
   - A heading line (`^#+\s`) or bold-label line (`^\*\*.*\*\*:?\s*$`) longer than 60 characters.
   - A heading or bold-label line containing a parenthesised date or qualifier suffix matching the regex `\([0-9]{4}-[0-9]{2}-[0-9]{2}.*?\)` (also catch shorter forms like `(2026-01-15 ...)`).

   Surface both checks as `info`-level, not blocking — the wider workflow should be able to land an edit that contains a violation while warning the author.

## Acceptance

- Editing the three files above lands the rule + lint heuristic.
- Fixture wiki with mixed-source entries carrying parenthesised attribution suffixes → after `wiki_fix`:
  - The fixture wiki's SCHEMA declares a label vocabulary; labels match it verbatim (no parenthetical attribution).
  - Displaced metadata appears in `sources:` or a `raw/` sidecar.
  - The audit report names the routing as part of the per-file change list.
- `tests/wiki/run_all.sh --layer2` passes.
