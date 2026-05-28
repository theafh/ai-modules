---
description: Keep wiki headings and bold-prefix labels to a fixed structural vocabulary; route displaced metadata (date, source, qualifier) to its proper channel.
scope: plugins/knowledge_management
created: 2026-05-28T19:24:35
updated: 2026-05-28T20:07:08
status: open
---

# Stop stuffing metadata into wiki headings and bold labels

## Goal

Markdown headings and bold-prefix labels in wiki pages are *structural*: they match a small fixed vocabulary so readers can navigate by skim and `grep`. Metadata — date, source, session ID, audience, qualifier, mandate level, scope tag — is *semantic content* and belongs in a separate channel (frontmatter, per-claim inline link, `raw/` sidecar, audit-log entry). After this task, the `wiki_auto_shaper` agent and the wiki authoring contract refuse to augment headings or labels with parenthesised metadata, and the lint surfaces such augmentation as an info-level finding.

## Context

This is one of a family of **generalisable refinements** to the wiki skills + `wiki_auto_shaper` agent. The trigger was a concrete friction point during the 2026-05-26 audit of `wiki/todos/bet-assistant-updates.md` in the `ai-assets` repo, but the rule is stated globally so it applies to every user of the wiki skills, not just the originating case.

During that audit the auto-shaper normalised eight section labels and produced strings like:

- `**What the canon says (2026-05-22 review-routing session):**`
- `**What the canon says (2026-05-22 agent-runtime POC bet authoring session):**`

The user called this "overcompression beyond recognition" — the label vocabulary is structural, the parenthesised attribution is content that belongs elsewhere.

Files involved:

- [plugins/knowledge_management/agents/wiki_auto_shaper.md](../plugins/knowledge_management/agents/wiki_auto_shaper.md) — `<remediate>` section.
- [plugins/knowledge_management/skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) — authoring contract.
- [plugins/knowledge_management/skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) — heading/label lint.

Related tasks: [wiki_two-pass-normalisation.md](wiki_two-pass-normalisation.md) (the routing of displaced semantics is the same mechanism applied to all normalisation cases, not just headings; this task is the heading-specific surface).

## Approach

1. **`plugins/knowledge_management/agents/wiki_auto_shaper.md` `<remediate>` section** — when normalising a heading or bold-prefix label, keep the vocabulary to the SCHEMA-defined set; route displaced metadata (date, source, qualifier, audience, mandate level, scope tag) to its structured channel *before* applying the normalisation. The wiki SCHEMA defines the heading vocabulary per page type; consult it rather than inventing terms.
2. **`plugins/knowledge_management/skills/wiki/SKILL.md`** — mirror the rule in the authoring contract.
3. **`plugins/knowledge_management/skills/wiki/scripts/lint.py`** — add an info-level heuristic flagging either of:
   - A heading line (`^#+ `) or bold-label line (`^\*\*.*\*\*:?\s*$`) longer than 60 characters.
   - A heading or bold-label line containing a parenthesised date or qualifier suffix matching the regex `\([0-9]{4}-[0-9]{2}-[0-9]{2}.*?\)` (also catch shorter forms like `(2026-05-22 ...)`).

   Surface both checks as `info`-level, not blocking — the wider workflow should be able to land an edit that contains a violation while warning the author.

Bump versions only at commit time per the repo's one-bump-per-session rule.

## Acceptance

- Editing the three files above lands the rule + lint heuristic; both run cleanly through `make lint`.
- Fixture wiki with mixed-source entries carrying parenthesised attribution suffixes → after `wiki_fix`:
  - Labels match SCHEMA vocabulary verbatim (no parenthetical attribution).
  - Displaced metadata appears in `sources:` or a `raw/` sidecar.
  - The audit report names the routing as part of the per-file change list.
- `tests/wiki/run_all.sh --layer2` passes.
