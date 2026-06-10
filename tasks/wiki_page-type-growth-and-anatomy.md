---
description: Add a `growth:` declaration per wiki page type and teach the lint to defer size findings for declared-backlog/monotonic-append/synthesis pages; disambiguate todo anatomy for non-canonical sources.
scope: plugins/knowledge_management
created: 2026-05-28T19:25:37
updated: 2026-06-10T22:05:12
status: open
---

# Declare page-type growth patterns; clarify todo anatomy for non-canonical sources

## Goal

Two adjacent failures around page-type contracts get fixed together:

1. **Page-type anatomy now covers canonical and non-canonical sources uniformly.** The todo page-type's three-paragraph anatomy (`Where` / `What the canon says` / `Suggested fix`) currently treats every entry's source as a canonical upstream document. When the source is a recorded authoring session, "What the canon says" reads awkwardly. SCHEMA explicitly states whether "canon" covers session-derived rules and which label the middle paragraph uses, and every author and agent uses the chosen wording without parenthetical augmentation.
2. **Lint reads a declared `growth:` pattern before emitting size findings.** A `todo` page's growth past 200 lines is the *expected* shape of a healthy backlog; the lint should not flag it as a sanction. Each page type declares its growth pattern — `fixed | backlog (self-trimming) | monotonic-append | unbounded-synthesis` — and the linter defers.

## Context

This is one of a family of **generalisable refinements** to the wiki skills + `wiki_auto_shaper` agent. The trigger was a concrete friction point during the 2026-05-26 audit of `wiki/todos/bet-assistant-updates.md` in the `ai-assets` repo, but the rule is stated globally so it applies to every user of the wiki skills, not just the originating case.

During that audit the auto-shaper either parenthetically annotated the middle-paragraph heading (see [wiki_metadata-in-headings.md](wiki_metadata-in-headings.md)) or silently broadened the definition of "canon" in a page-summary paragraph (see [wiki_meta-prose-in-page-bodies.md](wiki_meta-prose-in-page-bodies.md)) — both remediation smells driven by the ambiguous page-type contract.

Separately, lint size findings landed in the page body as sanction prose even though the backlog's growth past 200 lines is the page type's expected behaviour.

Files involved:

- Target-wiki `SCHEMA.md` template inside the wiki skill bundle (the file the wiki skill writes when bootstrapping a wiki).
- [plugins/knowledge_management/skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py).
- [plugins/knowledge_management/agents/wiki_auto_shaper.md](../plugins/knowledge_management/agents/wiki_auto_shaper.md) (the line currently containing "note the rationale on the page's body or in `SCHEMA.md`", around lines 944-946).

Related tasks:

- [wiki_meta-prose-in-page-bodies.md](wiki_meta-prose-in-page-bodies.md) — its step dropping the "on the page's body or" wording from the auto-shaper overlaps with step 4 here. Coordinate the two so the wording is removed exactly once.
- [wiki_metadata-in-headings.md](wiki_metadata-in-headings.md) — the parenthetical-attribution failure this task partly causes by leaving the anatomy ambiguous.

## Approach

1. **Target-wiki `SCHEMA.md` template** — extend each page-type definition with a `growth:` declaration:
   - `todo` → `backlog` (self-trimming).
   - `log` / `changelog` → `monotonic-append`.
   - `entity` / `concept` / `procedure` → `fixed`.
   - `synthesis` → `unbounded-synthesis`.
   - `index` → `fixed`.
2. **`plugins/knowledge_management/skills/wiki/scripts/lint.py`** — when emitting the 200-line size finding, look up the page's declared type and growth pattern; skip the finding for `backlog`, `monotonic-append`, and `unbounded-synthesis` types below a much higher threshold (e.g., 1000 lines). For `backlog` past 1000 lines, emit a split-or-graduate-entries recommendation rather than a body-sanction note.
3. **Target-wiki `SCHEMA.md` template** — in the todo page-type clause, state explicitly whether "canon" covers session-derived rules and which middle-paragraph label is canonical. Remove the ambiguity that lets the agent invent parenthetical annotations.
4. **`plugins/knowledge_management/agents/wiki_auto_shaper.md`** — at the line currently containing "note the rationale on the page's body or in `SCHEMA.md`" (locate by phrase, around lines 944-946), drop "on the page's body or". If a sanction is genuinely needed beyond what SCHEMA declares, route it to `log.md`, never the page body. Coordinate with [wiki_meta-prose-in-page-bodies.md](wiki_meta-prose-in-page-bodies.md) so the wording is removed exactly once across both tasks.

## Acceptance

- Three fixture scenarios all behave correctly:
  - **Fixture A** — `todo` page at 250 lines (within the `backlog` pattern): `wiki_fix` emits no size finding, adds no sanction prose.
  - **Fixture B** — `todo` page at 1200 lines: size finding with split or graduate-entries recommendation; not sanctioned in body.
  - **Fixture C** — `todo` page with one entry sourced from a recorded session: middle-paragraph label matches SCHEMA verbatim, no parenthetical attribution; source attribution lives in frontmatter `sources:` pointing at `raw/meetings/<slug>.md`.
- `tests/wiki/run_all.sh --layer2` passes.
