# Wiki Schema

This LLM-Wiki is managed by the `wiki` skill created by Andreas F. Hoffmann from the `knowledge_management` plugin in [theafh AI-repo](https://github.com/theafh/ai-modules).

## Domain

[What this wiki covers — e.g., "AI/ML research", "personal health", "startup intelligence"]

## Conventions

- File names: lowercase, hyphens, no spaces (e.g., `transformer-architecture.md`)
- Every wiki page starts with YAML frontmatter (see below)
- Cross-link with standard relative markdown links: `[transformer](../concepts/transformer.md)`
  from a different folder, `[transformer](transformer.md)` from the same folder.
  Minimum 2 outbound links per page.
- When updating a page, always bump the `updated` date
- Every new page must be added to `index.md` under the correct section
- Every action must be appended to `log.md`
- **Provenance:** On pages that synthesize 3+ sources, use standard markdown
  footnotes to attribute claims to specific raw files:

  ```markdown
  Transformers replaced RNNs for most sequence tasks by 2019.[^vaswani-2017]

  [^vaswani-2017]: raw/papers/attention-is-all-you-need.md
  ```

  Optional on single-source pages where the `sources:` frontmatter is enough.

## Frontmatter

```yaml
---
title: Page Title
created: YYYY-MM-DD
updated: YYYY-MM-DD
type: entity | concept | comparison | query | summary | procedure
tags: [from taxonomy below]
sources: [raw/articles/source-name.md]
# Optional quality signals:
confidence: high | medium | low        # how well-supported the claims are
contested: true                        # set when the page has unresolved contradictions
contradictions: [other-page-slug]      # pages this one conflicts with
---
```

`confidence` and `contested` are optional but recommended for opinion-heavy or fast-moving
topics. Lint surfaces `contested: true` and `confidence: low` pages for review so weak claims
don't silently harden into accepted wiki fact.

**Custom domain-specific fields.** Add a field beyond the canonical set only when existing
fields can't express what you need (e.g., `status: draft | reviewed | published`). Declare
it in the `## Frontmatter` block above with its value set, and add a short `### field_name`
subsection below explaining it. The linter validates declared custom fields against their
declared values and flags undeclared keys on pages. Default to the canonical fields — invent
custom ones sparingly, since each one fragments the schema across wikis.

### raw/ Frontmatter

Raw sources ALSO get a small frontmatter block so re-ingests can detect drift:

```yaml
---
source_url: https://example.com/article   # original URL, if applicable
ingested: YYYY-MM-DD
sha256: <hex digest of the raw content below the frontmatter>
---
```

The `sha256:` lets a future re-ingest of the same URL skip processing when content is unchanged,
and flag drift when it has changed. Compute over the body only (everything after the closing
`---`), not the frontmatter itself.

## Tag Taxonomy

[Define 10–20 top-level tags for the domain. Add new tags here BEFORE using them.]

Example for AI/ML:

- Models: model, architecture, benchmark, training
- People/Orgs: person, company, lab, open-source
- Techniques: optimization, fine-tuning, inference, alignment, data
- Meta: comparison, timeline, controversy, prediction

Rule: every tag on a page must appear in this taxonomy. If a new tag is needed,
add it here first, then use it. This prevents tag sprawl.

## Page Thresholds

- **Create a page** when an entity/concept appears in 2+ sources OR is central to one source
- **Add to existing page** when a source mentions something already covered
- **Skip page creation** for passing mentions, minor details, or things outside the domain
- **Split a page** when it exceeds ~200 lines — break into sub-topics with cross-links
- **Archive a page** when its content is fully superseded — move to `_archive/`, remove from index

## Page Types: Pick by Question

Each type answers a different shape of question. The first five capture
*what is true* and *why* (declarative); the sixth captures *how to act*
(procedural).

| Type | Answers |
| --- | --- |
| **entity** | "Who/what *is* X?" — a named person, org, product, model, place. |
| **concept** | "What does X *mean*, and why?" — an idea or mechanism. |
| **comparison** | "How does X *compare to* Y?" — side-by-side with verdict. |
| **summary** | "What's the *overview* of topic X?" — topic-organized digest. |
| **query** | "What's the answer to *my specific question*?" — question-organized. |
| **procedure** | "*How* should X be done?" — rule, convention, or workflow. |

When **summary** and **query** both feel possible, prefer summary — broader
entry surface. When **procedure** and **concept** feel possible, ask whether
the page *describes* (concept) or *prescribes* (procedure) — wording a
description as "rules govern X" leaves it descriptive and keeps it in
`concepts/`.

## Entity Pages

Answers "who/what *is* X?" — one page per notable entity (person, org,
product, model, place — anything with identity). Include:

- Overview / what it is
- Key facts and dates
- Relationships to other entities (relative markdown links)
- Source references

## Concept Pages

Answers "what does X *mean*, and why?" — one page per idea, mechanism, or
technique that's describable on its own. Concept pages *describe* how
something works; for *prescribing* how an operator should act, use a
procedure page instead. Include:

- Definition / explanation
- Current state of knowledge
- Open questions or debates
- Related concepts (relative markdown links)

## Comparison Pages

Answers "how does X *compare to* Y?" — side-by-side analyses with a
verdict. Include:

- What is being compared and why
- Dimensions of comparison (table format preferred)
- Verdict or synthesis
- Sources

## Summary Pages

Answers "what's the *overview* of topic X?" — topic-organized digest of
multiple sources, re-found by browsing the topic. Include:

- Topic and scope
- Key findings or claims, organized by sub-topic
- Open threads / unresolved questions
- Source references

## Query Pages

Answers "what's the answer to *my specific question*?" —
question-organized synthesis filed back so future re-asks hit the page
instead of re-deriving. Use when the question shape itself is what makes
the answer valuable. Include:

- The question, verbatim, as the title
- The synthesized answer with cross-links to entity / concept / source pages
- Confidence and caveats
- Source references

## Procedure Pages

Answers "*how* should X be done?" — one page per **procedural rule** the
agent (or human operator) applies when working in this domain (workflows,
conventions, runbooks, build steps, sourcing rules, review checklists,
naming rules). Procedure pages capture *how-to* knowledge and complement
the *what/why* knowledge in entity, concept, and comparison pages. They
are first-class wiki citizens — same frontmatter, same lint, same tag
and index discipline as content pages.

A procedure page reads as steps an operator follows. Pages that read as
facts about how a mechanism works — even when worded as "rules govern X"
— stay descriptive and file as `concept`.

Page anatomy:

- **Title** at H1; one-paragraph summary directly below stating the rule and its scope.
- **When this applies** — the trigger. What is the operator about to do that pulls this page in?
- **The rule** — the evergreen content. Tight, self-contained, independent of any specific worked example.
- **Pitfalls / edge cases** (optional) — short, rule-shaped only. Not a place for "and once we did X" narrative.
- **See Also** — links to related procedure pages and any worked-example sources where the rule was instantiated.

**Atomic vs. hub.** Atomic procedure pages answer one question (e.g.,
"how precise should my citation be?"). Hub pages chain three or more
atomic rules into a multi-step workflow and link out to the atomics;
their body is a numbered list of "now read X, then read Y, then …",
not a re-statement of the underlying rules.

**Where worked examples live.** Procedure pages hold the rule. Worked
examples and anecdotes live where they were generated:

- Source-specific worked examples — on the source sidecar in `raw/<kind>/<slug>.md`.
- Mechanism-explanation worked examples — on the relevant `concepts/` page.

If commentary starts accumulating on a procedure page, hoist it. See the
**Capture Procedure** protocol in `SKILL.md` for the strip-the-instance
workflow and the three generality tests.

## Update Policy

When new information conflicts with existing content:

1. Check the dates — newer sources generally supersede older ones
2. If genuinely contradictory, note both positions with dates and sources
3. Mark the contradiction in frontmatter: `contradictions: [page-name]`
4. Flag for user review in the lint report
