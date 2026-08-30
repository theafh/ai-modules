# Wiki Schema

This LLM-Wiki is managed by the `wiki` skill created by Andreas F. Hoffmann from the `knowledge_management` plugin in [theafh AI-repo](https://github.com/theafh/ai-modules).

## Domain

[What this wiki covers — e.g., "AI/ML research", "personal health", "startup intelligence"]

## Conventions

- **Folder layout is the type axis only.** Every page lives directly at
  `<pluralized-type>/<slug>.md` — flat, one layer deep (`concepts/transformer.md`,
  `entities/openai.md`). No thematic prefix folders, no sub-folders inside a type
  folder, no pages at the wiki root. Thematic scope is expressed through `tags:`
  and `type:`, both of which have explicit declared sets in this schema; the
  folder tree does not carry a second axis. The linter blocks misfiled pages and
  warns when a declared type folder is missing on disk.
- File names: lowercase, hyphens, no spaces (e.g., `transformer-architecture.md`)
- Every wiki page starts with YAML frontmatter (see below)
- Cross-link with standard relative markdown links: `[transformer](../concepts/transformer.md)`
  from a different folder, `[transformer](transformer.md)` from the same folder.
  Minimum 2 outbound links per page.
- When updating a page, always bump the `updated` date
- Every new page must be added to `index.md` under the correct section
- Every operation that creates or updates wiki files must be appended to
  `log.md`; an operation that changes no file writes no entry (lint and audit
  runs excepted — each records its outcome as a process record)
- **Provenance:** this is an LLM-first wiki — attribution belongs *next to*
  the claim it attributes, not collected at the bottom of the page. The
  `sources:` frontmatter is the canonical list of every raw file the page
  draws on, and the linter validates each path resolves on disk. Pages do
  not carry a body "Sources" section, and per-claim attribution uses inline
  standard-markdown links:

  ```markdown
  Transformers replaced RNNs for most sequence tasks by 2019
  ([Vaswani 2017](../raw/papers/attention-is-all-you-need.md)).
  ```

  Footnote markers (`[^name]` / `[^name]: …`) are not used: they split the
  claim from its evidence across the page, render inconsistently across
  markdown viewers, hide their targets from the broken-link check, and
  easily drift into dangling references.

- **Derived from:** some pages exist because external material exists — a
  doctrine file in another repo, a codebase the page distills, a notebook
  the analysis was extracted from — where that external material is **not**
  itself the subject of classification, so it does not get captured into
  `raw/<kind>/<slug>.md`. That lineage lives in an optional bottom-of-page
  `## Derived from` section (bulleted list of external paths, URLs, or
  descriptors with whatever standing commentary applies). The heading is
  deliberately distinct from `## Sources` so the linter does not flag it as
  the deprecated body-Sources section — `sources:` frontmatter remains the
  single structured channel (strict `raw/<kind>/<slug>.md` paths,
  lint-validated), while `## Derived from` is the unstructured channel for
  external derivation material that lives outside the wiki by design. A
  page may have `sources:`, `## Derived from`, both, or neither.

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
source_url: https://example.com/article    # for an externally-published source (its public URL)
source_path: ../shared/spec.md             # for an in-repo source, relative from the wiki root
ingested: YYYY-MM-DD
sha256: <hex digest of the raw content below the frontmatter>
---
```

`source_url:` records where an externally-published source was fetched from. `source_path:`
records a source kept **inside the repository the wiki ships within**, written as a relative path
from the wiki root — it may point outside the wiki directory (for example `../shared/spec.md`) but
must stay inside the repo, and it is never an absolute or `~`-prefixed path, since a path that
leaves the repo or names a machine-specific prefix resolves only on the machine that wrote it and
dangles on every clone. Reach for it when the ingested source is a file the repo already tracks;
the linter blocks an absolute or repo-escaping `source_path:` and a relative one that does not
resolve on disk. (A wiki that is not in a repository is local-only and ships nowhere, so this rule
does not apply to it — its paths only ever resolve on the one machine that holds them.)

A local file that lives **outside the repository** — a chat-session transcript, a local note, a
working file under a home directory with no public URL — takes no path at all. Excerpt enough of
its content into the sidecar body to stand on its own, and note its locality in prose, for example
"Local file on the author's workstation; relevant content excerpted below." A machine-local
absolute path would only add a pointer that breaks everywhere else, so the excerpt is the
authoritative copy and the sidecar carries neither `source_url:` nor `source_path:`.

**Reconciling a mislabeled or legacy sidecar.** A sidecar written before the two-field split, or
one that mis-filed its origin, reconciles onto this contract by a single test: *is the corrected
state deterministically recoverable from the values present, without inventing or discarding
provenance?* When it is, the move is deterministic and lossless, and applies automatically:

- A `file://` URL or a bare path in `source_url:` that names an in-repo target becomes a
  `source_path:` — a relative path from the wiki root, which may point outside the wiki directory
  via `../` — and the `source_url:` is dropped.
- An absolute or `~`-prefixed `source_path:` that resolves to an in-repo file normalizes to its
  wiki-root-relative equivalent — the same file, portably spelled.
- A remote URL sitting in `source_path:` becomes `source_url:`.
- Two fields naming the *same* origin collapse to the one field whose form fits, dropping the
  duplicate.

When the values do not settle it, a human decides — reconciliation stops and the case is surfaced
rather than guessed:

- Two fields naming *different* plausible origins: choosing one discards provenance, so the user picks.
- A value that fits no field and whose removal would strand the source — an out-of-repo `file://`
  or absolute path with no stand-alone body excerpt — drops to a body excerpt plus a prose locality
  note only once a human confirms it.

These cases illustrate the recoverable-without-inventing-or-discarding test; they are not a closed list.

The `sha256:` lets a future re-ingest of the same source skip processing when content is unchanged,
and flag drift when it has changed. Compute over the body only (everything after the closing
`---`), not the frontmatter itself. Use `python3 scripts/compute_sha256.py raw/<kind>/<slug>.md`
to write or refresh the field — the script handles the body-boundary detail correctly and
keeps the rest of the frontmatter intact. Run it without arguments to refresh every raw file at
once (it walks the discovered wiki's `raw/` tree).

## Tag Taxonomy

[Define 10–20 top-level tags for the domain. Add new tags here BEFORE using them.]

Example for AI/ML:

```text
- Models: model, architecture, benchmark, training
- People/Orgs: person, company, lab, open-source
- Techniques: optimization, fine-tuning, inference, alignment, data
- Meta: comparison, timeline, controversy, prediction
```

The linter reads only unfenced `- Label: tag, …` bullets, so the block above is
documentation rather than the live taxonomy — replace it with your own unfenced
bullets. Until you do, the linter reports "no Tag Taxonomy section" rather than
validating pages against these placeholder tags.

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

## Summary Pages

Answers "what's the *overview* of topic X?" — topic-organized digest of
multiple sources, re-found by browsing the topic. Include:

- Topic and scope
- Key findings or claims, organized by sub-topic
- Open threads / unresolved questions

## Query Pages

Answers "what's the answer to *my specific question*?" —
question-organized synthesis filed back so future re-asks hit the page
instead of re-deriving. Use when the question shape itself is what makes
the answer valuable. Include:

- The question, verbatim, as the title
- The synthesized answer with cross-links to entity / concept / source pages
- Confidence and caveats

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

## Lint

`scripts/lint.py` walks every Markdown file under the type folders and always
skips the `raw/` and `_archive/` trees. A vault that also holds non-page
folders — synced notes, generated artifacts, imported working files — names
them here so the page rules (frontmatter, links, structure, orphans) stay off
files that were never meant to be wiki pages:

```text
- Page-check exclusions: notes, generated
```

List the directory names directly under the wiki root, comma-separated, on one
`Page-check exclusions:` bullet. The names are additive to the always-skipped
`raw/` and `_archive/`, not a replacement. Omit the bullet when the vault holds
only pages — the default skips the two standard trees and nothing else. The
linter reads this bullet only outside fenced code blocks, so the example above
is documentation rather than a live setting.
