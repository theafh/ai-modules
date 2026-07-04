---
description: Add growth-pattern awareness to the wiki size lint — canonical per-type defaults plus a SCHEMA `## Lint` growth bullet — and make custom-type anatomies name their session-derived-source label.
scope: plugins/knowledge_management
created: 2026-05-28T19:25:37
updated: 2026-07-04T14:43:36
status: open
reported-by: Andreas Hoffmann
---

# Declare page-type growth patterns; clarify custom-type anatomy for session-derived sources

## Goal

Two adjacent failures around page-type contracts get fixed together:

1. **Lint reads a growth pattern before emitting size findings.** Every page type resolves to a growth pattern — `fixed | backlog (self-trimming) | monotonic-append | unbounded-synthesis` — and the 200-line size finding defers for growing types until a much higher threshold, where it recommends splitting or graduating entries instead of sanctioning a healthy backlog or synthesis page.
2. **Custom page-type anatomies cover session-derived sources explicitly.** A wiki that declares a custom type states in that type's SCHEMA section which label its entries use for session-derived sources, removing the ambiguity that drives parenthetical heading annotation and silent redefinition of terms like "canon".

## Context

This is one of a family of **generalisable refinements** to the wiki skills + `auto_shaper_wiki` agent. The trigger was a concrete friction point surfaced while auditing a real wiki, but the rule is stated globally so it applies to every user of the wiki skills, not just the originating case. During that audit the auto-shaper either parenthetically annotated a paragraph heading (see [wiki_metadata-in-headings.md](wiki_metadata-in-headings.md)) or silently broadened the definition of "canon" in a page-summary paragraph (see [wiki_meta-prose-in-page-bodies.md](wiki_meta-prose-in-page-bodies.md)) — both remediation smells driven by an ambiguous custom page-type contract. Separately, lint size findings landed in the page body as sanction prose even though that page type's growth past 200 lines is its expected behaviour.

Two facts about the shipped plugin shape the design:

- The canonical page-type enum in the SCHEMA template is `entity | concept | comparison | query | summary | procedure`. The originating wiki's `todo` is a **custom** type — honoured because `lint.py` parses each wiki's `type:` enum from its own SCHEMA frontmatter block (the `TYPE_ENUM_RE` read) — and `log.md` / `index.md` are special files outside the page walk that the size check never visits. Growth therefore lands as canonical defaults in the linter plus a per-wiki declaration for custom types.
- SCHEMA.md already has a machine-read config channel: the `## Lint` section, which `lint.py` parses fence-safe for the `Page-check exclusions:` bullet (`LINT_EXCLUDE_RE`). The growth declaration follows that established pattern rather than inventing a second parse convention.

Files involved:

- [template_schema.md](../plugins/knowledge_management/skills/wiki/references/template_schema.md) — the `## Lint` section and the custom-declaration guidance.
- [lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) — `check_page_size` and the `## Lint` section parse.
- [lint_checks.md](../plugins/knowledge_management/skills/wiki/references/lint_checks.md) — document the growth-aware size behaviour.
- [auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md) — the line containing "note the rationale on the page's body or" (locate by phrase).

Related tasks:

- [wiki_meta-prose-in-page-bodies.md](wiki_meta-prose-in-page-bodies.md) — its step dropping the "on the page's body or" wording from the auto-shaper overlaps with the final step here. Coordinate the two so the wording is removed exactly once.
- [wiki_metadata-in-headings.md](wiki_metadata-in-headings.md) — the parenthetical-attribution failure this task partly causes by leaving the anatomy ambiguous.
- [wiki_lint-accepted-info-suppression.md](wiki_lint-accepted-info-suppression.md) — owns the instance-level accept mechanism; the decided boundary: a declared growth pattern defers size findings type-wide, while the accept mechanism covers an individual reviewed finding.

## Approach

1. **Canonical defaults in `lint.py`** — map the built-in types: `entity`, `concept`, `procedure`, `comparison` → `fixed`; `summary`, `query` → `unbounded-synthesis`. Defaults live in the linter so existing wikis get them with no migration.
2. **Custom-type declaration in the SCHEMA `## Lint` section** — one labeled bullet, for example `- Growth patterns: todo=backlog`, parsed with the same fence-safe scan as `Page-check exclusions:` and additive over the defaults. Document the bullet in the template's `## Lint` section (as documentation inside a fenced example, mirroring the exclusions bullet) and in `lint_checks.md`.
3. **Growth-aware `check_page_size`** — resolve each page's effective pattern (declaration first, then canonical default, then `fixed` for an undeclared custom type): `fixed` keeps today's over-200 info finding; `backlog`, `monotonic-append`, and `unbounded-synthesis` defer to 1000 lines, past which the finding recommends split-or-graduate-entries rather than a body sanction.
4. **Custom-type anatomy rule in `template_schema.md`** — beside the existing custom-declaration guidance, state that a wiki declaring a custom type defines that type's section anatomy, including the label its entries use for session-derived sources. The originating wiki's `todo` anatomy — a "What the canon says" paragraph reading awkwardly for entries sourced from recorded sessions — is the motivating illustration.
5. **`auto_shaper_wiki.md`** — at the line containing "note the rationale on the page's body or" (locate by phrase), drop "on the page's body or"; sanction rationale routes to `SCHEMA.md` or `log.md`, never the page body. Coordinate with [wiki_meta-prose-in-page-bodies.md](wiki_meta-prose-in-page-bodies.md) so the wording is removed exactly once across both tasks.

## Acceptance

- **Fixture A** — a wiki whose SCHEMA declares `todo` in its frontmatter type enum and `todo=backlog` on the `## Lint` growth bullet; a 250-line todo page → no size finding, no sanction prose after `wiki_fix`.
- **Fixture B** — same wiki, 1200-line todo page → one finding recommending split or graduate-entries; no body sanction.
- **Fixture C** — a 250-line `summary` page in a wiki with no growth bullet → no size finding (canonical default covers built-in types).
- **Fixture D** — the fixture SCHEMA's custom-type section names its session-derived-source label; a todo entry sourced from a recorded session uses that label verbatim with no parenthetical attribution, and attribution lives in frontmatter `sources:` pointing at `raw/meetings/<slug>.md`.
- `template_schema.md` and `lint_checks.md` document the growth bullet, the canonical defaults, and the deferral thresholds.
- `tests/wiki/run_all.sh --layer2` passes.
