---
description: Make the size lint and the prose split thresholds growth-pattern aware (per-type defaults + SCHEMA `## Lint` growth bullet), and make custom-type anatomies name their session-derived-source label.
scope: plugins/knowledge_management
created: 2026-05-28T19:25:37
updated: 2026-09-05T21:26:04
status: open
reported-by: Andreas Hoffmann
---

# Declare page-type growth patterns; clarify custom-type anatomy for session-derived sources

## Goal

Two adjacent failures around page-type contracts get fixed together:

1. **Lint reads a growth pattern before emitting size findings.** Every page type resolves to a growth pattern (`fixed | backlog (self-trimming) | monotonic-append | unbounded-synthesis`), and the 200-line size finding defers for growing types until a higher threshold, where it recommends splitting or graduating entries instead of sanctioning a healthy backlog or synthesis page. The prose canon moves with the check: the split-threshold statements in the wiki skill, the schema template, and the agent's objectives state the same per-pattern thresholds, so the linter and the authoring guidance stop disagreeing about when a page is oversized.
2. **Custom page-type anatomies cover session-derived sources explicitly.** A wiki that declares a custom type states in that type's SCHEMA section which label its entries use for session-derived sources, removing the ambiguity that drives parenthetical heading annotation and silent redefinition of terms like "canon".

## Context

This is one of a family of **generalisable refinements** to the wiki skills + `auto_shaper_wiki` agent. The trigger was a concrete friction point surfaced while auditing a real wiki, but the rule is stated globally so it applies to every user of the wiki skills, not just the originating case. During that audit the auto-shaper either parenthetically annotated a paragraph heading (see [wiki_metadata-in-headings.md](wiki_metadata-in-headings.md)) or silently broadened the definition of "canon" in a page-summary paragraph (see [wiki_meta-prose-in-page-bodies.md](wiki_meta-prose-in-page-bodies.md)). Both are remediation smells driven by an ambiguous custom page-type contract. Separately, lint size findings landed in the page body as sanction prose even though that page type's growth past 200 lines is its expected behaviour.

Two facts about the shipped plugin shape the design:

- The canonical page-type enum in the SCHEMA template is `entity | concept | comparison | query | summary | procedure`. The originating wiki's `todo` is a **custom** type, honoured because `lint.py` parses each wiki's `type:` enum from its own SCHEMA frontmatter block (the `TYPE_ENUM_RE` read), and `log.md` / `index.md` are special files outside the page walk that the size check never visits. Growth therefore lands as canonical defaults in the linter plus a per-wiki declaration for custom types.
- SCHEMA.md already has a machine-read config channel: the `## Lint` section, which `lint.py` parses fence-safe for the `Page-check exclusions:` bullet (`LINT_EXCLUDE_RE`). The growth declaration follows that established pattern rather than inventing a second parse convention.

Files involved:

- [template_schema.md](../plugins/knowledge_management/skills/wiki/references/template_schema.md): the `## Lint` section, the custom-declaration guidance, and the `**Split a page** when it exceeds ~200 lines` threshold bullet.
- [lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py): `check_page_size` and the `## Lint` section parse.
- [lint_checks.md](../plugins/knowledge_management/skills/wiki/references/lint_checks.md): document the growth-aware size behaviour.
- [skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md): the `<write_or_update_pages>` "**Split** a page that exceeds ~200 lines" bullet and the `<pages_stay_scannable>` pitfall.
- [auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md): the `<topic_separation>` objective, plus a verify-only pass over the line containing "note the rationale on the page's body or" (locate by phrase).

Related tasks:

- [wiki_meta-prose-in-page-bodies.md](wiki_meta-prose-in-page-bodies.md) owns dropping the "on the page's body or" wording from the auto-shaper and the wider no-meta-in-body prohibition; the matching step here is verify-only.
- [wiki_metadata-in-headings.md](wiki_metadata-in-headings.md): the parenthetical-attribution failure this task partly causes by leaving the anatomy ambiguous.
- [wiki_lint-accepted-info-suppression.md](archive/wiki_lint-accepted-info-suppression.md) owns the instance-level accept mechanism; the decided boundary: a declared growth pattern defers size findings type-wide, while the accept mechanism covers an individual reviewed finding. Both tasks add a bullet to the same SCHEMA `## Lint` section and register it in the same agent `<configurable_zones>` list, so coordinate those two edits whichever lands first.

## Approach

1. **Canonical defaults in `lint.py`.** Map the built-in types: `entity`, `concept`, `procedure`, `comparison` → `fixed`; `summary`, `query` → `unbounded-synthesis`. Defaults live in the linter so existing wikis get them with no migration.
2. **Custom-type declaration in the SCHEMA `## Lint` section.** One labeled bullet, for example `- Growth patterns: todo=backlog`, parsed with the same fence-safe scan as `Page-check exclusions:` and additive over the defaults. Document the bullet in the template's `## Lint` section (as documentation inside a fenced example, mirroring the exclusions bullet) and in `lint_checks.md`. Register it in the agent's `<configurable_zones>` entry for `template_schema.md`, which today names only the `Page-check exclusions` bullet as wiki-owned inside `## Lint`: without that entry a declared growth pattern survives on nothing but `<hunk_classification>`'s generic extends-the-canon fallback, and an audit reading it as scaffold drift would remove the declaration that keeps the wiki's size findings correct.
3. **Growth-aware `check_page_size`.** Resolve each page's effective pattern (declaration first, then canonical default, then `fixed` for an undeclared custom type): `fixed` keeps today's over-200 info finding; `backlog`, `monotonic-append`, and `unbounded-synthesis` defer to 500 lines, past which the finding recommends split-or-graduate-entries rather than a body sanction.
4. **Growth-aware prose canon.** Move the split-threshold statements outside the linter together with the check so prose and check tell one story: rewrite the `<write_or_update_pages>` split bullet and the `<pages_stay_scannable>` pitfall in `SKILL.md`, the `**Split a page**` threshold bullet in `template_schema.md`, and the `<topic_separation>` objective in `auto_shaper_wiki.md` to state the threshold per growth pattern: `fixed` types split past ~200 lines; growing types defer to step 3's higher threshold, where the action is split or graduate entries.
5. **Custom-type anatomy rule in `template_schema.md`.** Beside the existing custom-declaration guidance, state that a wiki declaring a custom type defines that type's section anatomy, including the label its entries use for session-derived sources. The originating wiki's `todo` anatomy, a "What the canon says" paragraph reading awkwardly for entries sourced from recorded sessions, is the motivating illustration.
6. **`auto_shaper_wiki.md` body-routing wording.** Verify the "note the rationale on the page's body or" wording is already gone: [wiki_meta-prose-in-page-bodies.md](wiki_meta-prose-in-page-bodies.md) owns dropping it (sanction rationale routes to `SCHEMA.md` or `log.md`, never the page body). When this task lands first, leave the wording in place for that task.

## Acceptance

- **Fixture A:** a wiki whose SCHEMA declares `todo` in its frontmatter type enum and `todo=backlog` on the `## Lint` growth bullet; a 250-line todo page → no size finding, no sanction prose after `wiki_fix`.
- **Fixture B:** same wiki, 700-line todo page → one finding recommending split or graduate-entries; no body sanction.
- **Fixture C:** a 250-line `summary` page in a wiki with no growth bullet → no size finding (canonical default covers built-in types).
- **Fixture D:** the fixture SCHEMA's custom-type section names its session-derived-source label; a todo entry sourced from a recorded session uses that label verbatim with no parenthetical attribution, and attribution lives in frontmatter `sources:` pointing at `raw/meetings/<slug>.md`.
- The split threshold reads growth-aware at every prose site: the `SKILL.md` split bullet and `<pages_stay_scannable>` pitfall, the `template_schema.md` split bullet, and the agent's `<topic_separation>` objective each state the per-pattern thresholds (fixed at ~200 lines; growing types at the deferral threshold) rather than one unqualified 200-line rule.
- `template_schema.md` and `lint_checks.md` document the growth bullet, the canonical defaults, and the deferral thresholds.
- The agent's `<configurable_zones>` entry for `template_schema.md` names the growth bullet alongside `Page-check exclusions`, so a scaffold diff reads a declared growth pattern as wiki-owned content instead of drift.
- `tests/wiki/run_all.sh --layer2` passes.
