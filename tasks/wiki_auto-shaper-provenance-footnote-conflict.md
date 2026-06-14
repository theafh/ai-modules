---
description: Align the wiki_auto_shaper agent's provenance detection and remediation with the inline-path-link, no-footnote attribution convention the linter, schema, and SKILL already enforce.
scope: plugins/knowledge_management
created: 2026-06-12T23:32:36
updated: 2026-06-12T23:32:36
status: open
reported-by: Andreas Hoffmann
---

# Align `wiki_auto_shaper` provenance handling with the no-footnote attribution convention

## Goal

The `wiki_auto_shaper` agent's provenance detection and remediation stop emitting `[^footnote]` markers and instead attribute multi-source claims with inline standard-markdown path links — the convention the linter, schema, and authoring contract already enforce. After the change the agent reaches a clean re-lint on pages that synthesize three or more sources, where today it cannot.

Scope decision: the fix changes only the agent prose. The linter, schema, and SKILL already agree on inline path-link attribution and stay unchanged; the agent is the sole deviation and the only thing this task edits.

## Context

The agent contradicts the wiki's footnote policy, so its own re-lint pass re-flags exactly what its provenance fix just added. On any page with three or more contributing sources the agent loops, thrashes, or leaves a warning it created — the provenance remediation is self-defeating.

The contradiction is one agent file against three places that already agree with each other:

- **Agent emits footnotes.** [plugins/knowledge_management/agents/wiki_auto_shaper.md](../plugins/knowledge_management/agents/wiki_auto_shaper.md) — the `<provenance_violation>` detection block flags a page that "lacks the inline footnote markers `[^source-name]`" and asserts "the schema requires footnotes once 3+ sources contribute"; the `<fix_provenance_violation>` remediation block adds `[^source-slug]` markers plus matching `[^source-slug]: raw/<kind>/<slug>.md` definitions at the page bottom.
- **Linter forbids footnotes.** [plugins/knowledge_management/skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) — the `check_footnote_syntax` check emits a WARN-severity `footnote` issue on every `[^name]` marker and `[^name]:` definition, directing conversion to inline standard-markdown path links placed next to the claim.
- **Schema forbids footnotes.** [plugins/knowledge_management/skills/wiki/references/template_schema.md](../plugins/knowledge_management/skills/wiki/references/template_schema.md) — footnote markers "are not used".
- **SKILL forbids footnotes.** [plugins/knowledge_management/skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) — "No footnote markers"; claim-level attribution uses inline standard-markdown links.

The agent's terminal condition compounds the defect: its `<relint_until_clean>` step loops the fix until the linter exits with no blocking or warn issues, so a self-created footnote WARN blocks convergence. The cited premise — "the schema requires footnotes once 3+ sources contribute" — is itself false: no such rule exists in the schema or SKILL, and both state the opposite. Anchor edits to the named blocks (`provenance_violation`, `fix_provenance_violation`, `relint_until_clean`) and the `check_footnote_syntax` function rather than to line numbers, which drift.

Related task: [wiki_provenance-via-raw-and-sources.md](wiki_provenance-via-raw-and-sources.md) co-edits the same agent's provenance remediation (routing source records through `raw/` sidecars + `sources:` frontmatter) and presupposes inline links as the per-claim mechanism. Reconcile wording where the two edits meet so the remediation reads as one coherent rule.

## Approach

1. **Rewrite `<fix_provenance_violation>`** so remediation attributes each multi-source claim with an inline standard-markdown path link to its source file under `raw/<kind>/<slug>.md`, placed next to the claim — in place of the `[^source-slug]` markers and the bottom-of-page `[^source-slug]: …` definition block.
2. **Rewrite the `<provenance_violation>` detection** so the violation reads "a page synthesizes three or more sources but its claims lack inline path-link attribution", and drop the statement that the schema requires footnotes; point at the actual convention (inline links, no footnotes) instead.
3. **Leave the linter, schema, and SKILL unchanged** — they already encode the intended convention. Rejected alternative: relaxing `check_footnote_syntax` and the schema to permit footnotes; that would contradict the established no-footnote convention across the whole wiki, so aligning the single deviating agent is the correct direction.

## Acceptance

- A search of [wiki_auto_shaper.md](../plugins/knowledge_management/agents/wiki_auto_shaper.md) finds no instruction to add `[^name]` footnote markers or bottom-of-page `[^name]:` definitions anywhere in its provenance detection or remediation; the `<fix_provenance_violation>` block instead instructs inline path-link attribution placed next to the claim.
- The `<provenance_violation>` block defines the violation as a three-or-more-source page whose claims lack inline path-link attribution, and carries no statement that the schema requires footnotes.
- The agent's provenance language matches the no-footnote convention stated in `check_footnote_syntax` ([lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py)), [template_schema.md](../plugins/knowledge_management/skills/wiki/references/template_schema.md), and [SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md).
- A wiki page with three or more sources, attributed per the rewritten `<fix_provenance_violation>` instructions, carries inline path-link attribution and yields zero `footnote` findings from `check_footnote_syntax`. If any footnote finding remains on such a page, the alignment is incomplete and the task is not done.
