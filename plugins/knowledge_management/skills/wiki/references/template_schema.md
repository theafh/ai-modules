# Wiki Schema

This LLM-Wiki is managed by the `wiki` skill created by Andreas F. Hoffmann from the `knowledge_management` plugin in [theafh AI-repo](https://github.com/theafh/ai-modules).

## Domain

[What this wiki covers — e.g., "AI/ML research", "personal health", "startup intelligence"]

While customizing this schema, replace every remaining example identifier in it
(slugs, page names, tags, source labels) with one drawn from this domain, so the
rules below read in the vocabulary of the wiki they govern.

## Conventions

- **File every page by type alone.** Put each page directly at
  `<pluralized-type>/<slug>.md`, flat and one layer deep (`concepts/<slug>.md`,
  `entities/<slug>.md`). Express thematic scope through `tags:` and `type:`,
  both of which have explicit declared sets in this schema, and keep the folder
  tree to that single type axis. The linter blocks misfiled pages and warns when
  a declared type folder is missing on disk.
- File names: lowercase, hyphens, no spaces (e.g., `transformer-architecture.md`)
- **Open every wiki page with YAML frontmatter** (see below).
- **Cross-link with standard relative markdown links:**
  `[<slug>](../concepts/<slug>.md)` from a different folder,
  `[<slug>](<slug>.md)` from the same folder. Give every page at least 2
  outbound links.
- **Bump the `updated` date** on every page you change.
- **Add every new page to `index.md`** under the correct section.
- **Append every operation that creates or updates wiki files to `log.md`**;
  write no entry for an operation that changes no file (lint and audit runs
  excepted — each records its outcome as a process record). **An entry records
  changes to this wiki, and only those**: its subject is a file under the wiki,
  a change elsewhere in the repository that holds the wiki goes in that change's
  own commit message, and a finding worth keeping goes onto the page that owns
  it so the entry names that page. The `Scope:` group in `log.md`'s own preamble
  carries this rule at the point of use.
- **Keep one owner per fact.** The page that owns the subject carries the
  perishable detail; a cross-cutting page carries the consequence and links to
  the owner rather than restating. Settle ownership by asking which page a
  reader would correct when the detail changes: that page owns the fact, and
  every other page that touches it links there.
- **Cite each source in the channel its object calls for.** This is an
  LLM-first wiki, so the object being attributed picks the channel. A source
  the wiki captured at `raw/<kind>/<slug>.md` is cited inline next to the claim
  it supports, through a relative markdown link into `raw/`, and is listed in
  the page's `sources:` frontmatter, which the linter validates path by path.
  External lineage the wiki never captured is recorded in the bottom-of-page
  `## Derived from` section described in the next bullet. Write per-claim
  attribution as an inline standard-markdown link:

  ```markdown
  <the claim this page makes> ([<source label>](../raw/papers/<slug>.md)).
  ```

  Footnote markers (`[^name]` / `[^name]: …`) are not used: they split the
  claim from its evidence across the page, render inconsistently across
  markdown viewers, hide their targets from the broken-link check, and
  easily drift into dangling references.

- **Record uncaptured external lineage under `## Derived from`.** Some pages
  exist because external material exists — a doctrine file in another repo, a
  codebase the page distills, a notebook the analysis was extracted from —
  where that external material is **not** itself the subject of
  classification, so it does not get captured into `raw/<kind>/<slug>.md`.
  Put that lineage in an optional bottom-of-page `## Derived from` section
  (bulleted list of external paths, URLs, or descriptors with whatever
  standing commentary applies). The heading is deliberately distinct from
  `## Sources` so the linter does not flag it as the deprecated body-Sources
  section — `sources:` frontmatter remains the single structured channel
  (strict `raw/<kind>/<slug>.md` paths, lint-validated), while
  `## Derived from` is the unstructured channel for external derivation
  material that lives outside the wiki by design. A page may have `sources:`,
  `## Derived from`, both, or neither.

An existing wiki converges on these conventions opportunistically. Each page
adopts them as it passes through audit and repair, and no migration sweep is
required.

## Frontmatter

```yaml
---
title: Page Title
created: YYYY-MM-DD
updated: YYYY-MM-DD
type: entity | concept | comparison | query | summary | procedure
tags: [from taxonomy below]
sources: [raw/articles/source-name.md]  # present when the page cites a captured source
# Optional quality signals:
confidence: high | medium | low        # how well-supported the claims are
contested: true                        # see ## Update Policy
contradictions: [other-page-slug]      # see ## Update Policy
checked: YYYY-MM-DD                    # when the claims were last checked against the subject
---
```

Carry `sources:` on a page that cites a source the wiki captured under `raw/`, and leave the
key off a page that cites none. A wiki capturing nothing into `raw/` therefore carries no
`sources:` key rather than an empty list on every page. The linter requires the remaining
fields on every page and validates each `sources:` entry it does find against disk.

`confidence` and `contested` are optional but recommended for opinion-heavy or fast-moving
topics. Lint surfaces `contested: true` and `confidence: low` pages for review, and
`## Update Policy` carries what to do with them.

`checked` records the date a page's claims were last checked against their subject. Neither
`created` nor `updated` records that, because both record when the page itself was written.
Carry `checked` on every page drawing on a moving external subject, and read a page without it
as a page to re-check. It stays an optional signal. The linter validates its YYYY-MM-DD form
when the field is present, blocks nothing on its absence, and never fills it in.

**Custom domain-specific fields.** Add a field beyond the canonical set only when existing
fields can't express what you need (e.g., `status: draft | reviewed | published`). Declare
it in the `## Frontmatter` block above with its value set, and add a short `### field_name`
subsection below explaining it. The linter validates declared custom fields against their
declared values and flags undeclared keys on pages. Apply this test before adding one. Name the
closed set of values the field takes, and name the question about a page that no canonical
field answers. A field that fails either half fragments the schema across wikis without buying
anything, so keep it out and use the canonical fields.

### raw/ Frontmatter

This subsection governs a wiki that captures external sources into `raw/`. A wiki that
captures none skips it whole.

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
`---`), not the frontmatter itself. Use
`python3 "$WIKI_SKILL/scripts/compute_sha256.py" raw/<kind>/<slug>.md` to write or refresh the
field — the script handles the body-boundary detail correctly and keeps the rest of the
frontmatter intact. Run it without arguments to refresh every raw file at once (it walks the
discovered wiki's `raw/` tree).

`$WIKI_SKILL` names the installed `wiki` skill bundle that holds `scripts/` and
`references/`, not a directory inside the wiki. Resolve it as the `<resolve_runtime_paths>`
block in the `auto_shaper_wiki` agent defines it, and resolve every other bundled script this
schema names the same way.

## Tag Taxonomy

[Define 10–20 top-level tags for the domain.]

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

**File a settled decision under the declarative type that fits what it
explains:** `concept` for the reasoning behind a single mechanism,
`comparison` for a choice argued between alternatives. The
describe-versus-prescribe test above already places these pages, so this
schema adds no separate decision-record type.

**Keep planned work on the page whose subject it extends,** in that page's
open-questions or open-threads section, for as long as it is an intent rather
than a unit of work. Once it becomes a unit of work it graduates to the
project's task backlog, and the split holds from then on. The wiki carries the
intent and the reasoning behind it, and the backlog carries the work. A wiki
with no backlog beside it keeps both on that page until one exists.

## Entity Pages

One page per notable entity (person, org, product, model, place, anything
with identity). Include:

- Overview / what it is
- Key facts and dates
- Relationships to other entities (relative markdown links)

## Concept Pages

One page per idea, mechanism, or technique that's describable on its own.
Concept pages *describe* how something works; for *prescribing* how an
operator should act, use a procedure page instead. Include:

- Definition / explanation
- Current state of knowledge
- Open questions or debates
- Related concepts (relative markdown links)

## Comparison Pages

One page per side-by-side analysis that ends in a verdict. Include:

- What is being compared and why
- Dimensions of comparison (table format preferred)
- Verdict or synthesis

## Summary Pages

One page per topic-organized digest of multiple sources, re-found by browsing
the topic. Include:

- Topic and scope
- Key findings or claims, organized by sub-topic
- Open threads / unresolved questions

## Query Pages

One page per question-organized synthesis, filed back so future re-asks hit
the page instead of re-deriving. Use when the question shape itself is what
makes the answer valuable. Include:

- The question, verbatim, as the title
- The synthesized answer with cross-links to entity / concept / source pages
- Confidence and caveats

## Procedure Pages

One page per **procedural rule** the agent (or human operator) applies when
working in this domain (workflows, conventions, runbooks, build steps,
sourcing rules, review checklists, naming rules). Procedure pages capture
*how-to* knowledge and complement
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

Run this workflow when new information conflicts with existing content. It is the
single statement of the contradiction path, and the `contested` and `contradictions`
frontmatter fields and the lint report point back to it. Resolving a contradiction here
is what keeps a weak claim from silently hardening into accepted wiki fact.

1. Check the dates — newer sources generally supersede older ones
2. If genuinely contradictory, note both positions with dates and sources
3. Mark the contradiction in frontmatter: `contested: true` plus `contradictions: [page-name]`
4. Flag for user review in the lint report

## Lint

`$WIKI_SKILL/scripts/lint.py` walks every Markdown file under the type folders and always
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

An info-level finding you have reviewed and decided to keep goes on an
`Accepted finding:` bullet in this same section. The next run drops it from the
live report and the live counts and lists it under `ACKNOWLEDGED` instead, so a
settled decision stops asking to be re-justified. Each bullet names exactly one
finding, in whichever of the three forms fits it:

```text
- Accepted finding: size — concepts/model-landscape.md
- Accepted finding: quality — concepts/widget.md — confidence: low — corroborate or note why
- Accepted finding: md-style — procedures/deploy.md — 42 — fenced code block missing language identifier
```

The short two-field form covers `size`, `log`, `stale`, and `log-scope`, whose
messages carry a counter or a date that moves between runs. The path alone
identifies the finding there. Every other category takes the finding's exact
message as a third field, and slots its line number in ahead of that message as
a fourth-field form when the report shows one (`path.md:42`). Copy the message
from the report verbatim — the match is exact. Fields are separated by ` — `,
and the message runs to the end of the line, so a message carrying its own em
dash is quoted in full. Acceptance covers info findings alone — a blocking or
warn finding stays in the report whatever a bullet says. The example above sits
in a fenced block, so it is documentation; a live acceptance goes on an
unfenced bullet.
