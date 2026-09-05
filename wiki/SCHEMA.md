# Wiki Schema

This LLM-Wiki is managed by the `wiki` skill created by Andreas F. Hoffmann from the `knowledge_management` plugin in [theafh AI-repo](https://github.com/theafh/ai-modules).

## Domain

This wiki is the project memory of **ai-modules**, the repository that defines and
ships reusable AI assistant components: skills, agents, hooks, output styles, and
the deployment machinery that installs them into agent harnesses.

**What it is for.** It is memory for the LLM coding agents that work in this
repository, and it ships inside the repository so every clone carries it. It holds
what an agent has learned about the repo and its elements, what those elements are
and how they work, the decisions that were argued and settled, what came out of
working sessions with the maintainer, and the extensions that are intended but not
yet task-scope. It is meant to grow into the source of truth the other systems read
from, so that a task gets created out of what is written here and a guardrail rule
gets stated from the reasoning kept here.

**What that obliges.** Memory that is not maintained becomes a second, wrong
account of the project, which is worse than no account at all. A page is therefore
kept true rather than merely kept: updated when the thing it describes changes,
reconciled when two pages disagree, cleared when its content is superseded,
refreshed when a claim ages past the date it was verified, and kept aligned with
both what exists today and what is planned next.

**The division against the other document sets.** The wiki holds the meta
knowledge and the specific-purpose containers hold the specifics. A rule that must
constrain an agent while it executes belongs in a guardrail document or a shipped
skill. A unit of work belongs in the task backlog. What belongs here is the
knowledge behind both: why a rule exists, what evidence supports it, which
alternatives were rejected, and how the pieces fit together. Overlap between the
sets is expected and fine; the same rule stated twice and left to drift is not.

**Its second body of knowledge.** Beside the repository's own workings sits the
**harness research**: verified, dated facts about how Anthropic Claude Code, OpenAI
Codex, SST OpenCode, Google Antigravity, Cursor, and GitHub Copilot in VS Code
discover artefacts, parse frontmatter, name tools, run hooks, and carry standing
instructions. That material decays on a schedule nobody here controls, so every
claim about a harness carries the date it was verified and the source it came from.
A page that says nothing about when it was checked is a page to re-check.

**Who reads this.** The consumer is an LLM coding agent, this wiki's own operator
included. That is a different audience from the repo-root guardrail documents,
which constrain an agent while it executes a task, and from the shipped skills,
which fire on a trigger and spend context every time they do. The wiki is read on
purpose, by an agent that went looking. It holds the evidence, the derivation, and
the rejected alternatives that a rule in a skill compresses away.

**What stays out.** Three things. Anything an agent needs while working in a
repository other than this one, because this wiki travels nowhere else; that
belongs in the shipped skill or its `references/` directory, and whether the
knowledge has to travel is the dividing test. Machine-private detail, because this
repository is public: which install path one workstation uses, what a local path
looks like, or what any individual person does is not wiki content, and a page
discussing a choice states what options exist rather than which one is in use.
And any state the repository already holds authoritatively, because git, the
backlog, and the manifests answer those questions on demand while a copy written
here is wrong by the next commit. That covers measurements that move, such as line
counts, file sizes, and token estimates; the number, names, or lifecycle status of
task files; the version of an artefact this repository ships; and the date on which
a change landed here. Write the property, the decision, or the reasoning instead.
Where the backlog owns follow-up work, point at it as work the backlog carries,
without counting the files or reporting their status.

Two carve-outs keep that last class from eating what it exists to protect. A
version number stays where it marks a real feature boundary in an external
subject, on the page that owns that subject, so a vendor's release boundary earns
one and this repository's own plugin version does not. A date stays where it
records when a claim was checked against a subject this wiki cannot re-read from
the repository, whether a vendor's product or a tree that is never committed, which
is the verification stamp the harness research runs on. It also stays where it
fixes a decision in time rather than reporting a state.

## Conventions

- **Folder layout is the type axis only.** Every page lives directly at
  `<pluralized-type>/<slug>.md`, flat and one layer deep (`concepts/transformer.md`,
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
  runs excepted, because each records its outcome as a process record)
- **Provenance:** this is an LLM-first wiki, so attribution belongs *next to*
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

- **Derived from:** some pages exist because external material exists that is
  **not** itself the subject of classification, so it does not get captured into
  `raw/<kind>/<slug>.md`. Examples are a doctrine file in another repo, a
  codebase the page distills, or a notebook the analysis was extracted from.
  That lineage lives in an optional bottom-of-page
  `## Derived from` section (bulleted list of external paths, URLs, or
  descriptors with whatever standing commentary applies). The heading is
  deliberately distinct from `## Sources` so the linter does not flag it as
  the deprecated body-Sources section. `sources:` frontmatter remains the
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

`confidence` rates the **evidence**, not how stable the subject is. Write `high` when the
claims rest on observed reality (a build inspected, source read, code measured), on something
the user stated as fact, or on two or more independent sources that agree. Write `medium` for
a single documented source, or for a first synthesis the user has not yet validated. Write
`low` for inference, and for reasoning from an absence of evidence. Rate a page by its
weakest load-bearing claim: one unverified claim that a design decision leans on caps the
page however well sourced the rest of it is, and the page says which claim did the capping.
A fast-moving subject is handled by the verification date, never by discounting confidence.

**Custom domain-specific fields.** Add a field beyond the canonical set only when existing
fields can't express what you need (e.g., `status: draft | reviewed | published`). Declare
it in the `## Frontmatter` block above with its value set, and add a short `### field_name`
subsection below explaining it. The linter validates declared custom fields against their
declared values and flags undeclared keys on pages. Default to the canonical fields and invent
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
from the wiki root. It may point outside the wiki directory (for example `../shared/spec.md`) but
must stay inside the repo, and it is never an absolute or `~`-prefixed path, since a path that
leaves the repo or names a machine-specific prefix resolves only on the machine that wrote it and
dangles on every clone. Reach for it when the ingested source is a file the repo already tracks;
the linter blocks an absolute or repo-escaping `source_path:` and a relative one that does not
resolve on disk. (A wiki that is not in a repository is local-only and ships nowhere, so this rule
does not apply to it, because its paths only ever resolve on the one machine that holds them.)

A local file that lives **outside the repository**, such as a chat-session transcript, a local note, or a
working file under a home directory with no public URL, takes no path at all. Excerpt enough of
its content into the sidecar body to stand on its own, and note its locality in prose, for example
"Local file on the author's workstation; relevant content excerpted below." A machine-local
absolute path would only add a pointer that breaks everywhere else, so the excerpt is the
authoritative copy and the sidecar carries neither `source_url:` nor `source_path:`.

**Reconciling a mislabeled or legacy sidecar.** A sidecar written before the two-field split, or
one that mis-filed its origin, reconciles onto this contract by a single test: *is the corrected
state deterministically recoverable from the values present, without inventing or discarding
provenance?* When it is, the move is deterministic and lossless, and applies automatically:

- A `file://` URL or a bare path in `source_url:` that names an in-repo target becomes a
  `source_path:`, a relative path from the wiki root that may point outside the wiki directory
  via `../`. The `source_url:` is then dropped.
- An absolute or `~`-prefixed `source_path:` that resolves to an in-repo file normalizes to its
  wiki-root-relative equivalent, the same file, portably spelled.
- A remote URL sitting in `source_path:` becomes `source_url:`.
- Two fields naming the *same* origin collapse to the one field whose form fits, dropping the
  duplicate.

When the values do not settle it, a human decides. Reconciliation stops and the case is surfaced
rather than guessed:

- Two fields naming *different* plausible origins: choosing one discards provenance, so the user picks.
- A value that fits no field and whose removal would strand the source (an out-of-repo `file://`
  or absolute path with no stand-alone body excerpt) drops to a body excerpt plus a prose locality
  note only once a human confirms it.

These cases illustrate the recoverable-without-inventing-or-discarding test; they are not a closed list.

The `sha256:` lets a future re-ingest of the same source skip processing when content is unchanged,
and flag drift when it has changed. Compute over the body only (everything after the closing
`---`), not the frontmatter itself. Use `python3 scripts/compute_sha256.py raw/<kind>/<slug>.md`
to write or refresh the field. The script handles the body-boundary detail correctly and
keeps the rest of the frontmatter intact. Run it without arguments to refresh every raw file at
once (it walks the discovered wiki's `raw/` tree).

## Tag Taxonomy

- Harnesses: claude, codex, opencode, antigravity, cursor, copilot
- Artefacts: skill, agent, hook, plugin, output-style
- Mechanisms: discovery, frontmatter, system-prompt, deployment, versioning
- Meta: portability, verification-gap, experiment, authoring, repo-structure

Two of these tags carry more weight than their names suggest.

`verification-gap` marks a page that states something the author could not confirm,
or confirmed only by observation on one machine. Search this tag to find the work
that is owed before a claim can be relied on.

`portability` marks a page whose subject is how one artefact behaves across more
than one harness, as opposed to a page about a single harness. It is the entry
point for cross-harness questions.

Rule: every tag on a page must appear in this taxonomy. If a new tag is needed,
add it here first, then use it. This prevents tag sprawl.

## Page Thresholds

- **Create a page** when an entity/concept appears in 2+ sources OR is central to one source
- **Add to existing page** when a source mentions something already covered
- **Skip page creation** for passing mentions, minor details, or things outside the domain
- **Split a page** when it exceeds ~200 lines, then break into sub-topics with cross-links
- **Archive a page** when its content is fully superseded, then move to `_archive/` and remove from index

## Page Types: Pick by Question

Each type answers a different shape of question. The first five capture
*what is true* and *why* (declarative); the sixth captures *how to act*
(procedural).

| Type | Answers |
| --- | --- |
| **entity** | "Who/what *is* X?" A named person, org, product, model, place. |
| **concept** | "What does X *mean*, and why?" An idea or mechanism. |
| **comparison** | "How does X *compare to* Y?" Side-by-side with verdict. |
| **summary** | "What's the *overview* of topic X?" Topic-organized digest. |
| **query** | "What's the answer to *my specific question*?" Question-organized. |
| **procedure** | "*How* should X be done?" Rule, convention, or workflow. |

When **summary** and **query** both feel possible, prefer summary for the broader
entry surface. When **procedure** and **concept** feel possible, ask whether
the page *describes* (concept) or *prescribes* (procedure). Wording a
description as "rules govern X" leaves it descriptive and keeps it in
`concepts/`.

## Entity Pages

Answers "who/what *is* X?" with one page per notable entity (person, org,
product, model, place, anything with identity). Include:

- Overview / what it is
- Key facts and dates
- Relationships to other entities (relative markdown links)

## Concept Pages

Answers "what does X *mean*, and why?" with one page per idea, mechanism, or
technique that's describable on its own. Concept pages *describe* how
something works; for *prescribing* how an operator should act, use a
procedure page instead. Include:

- Definition / explanation
- Current state of knowledge
- Open questions or debates
- Related concepts (relative markdown links)

## Comparison Pages

Answers "how does X *compare to* Y?" with side-by-side analyses that reach a
verdict. Include:

- What is being compared and why
- Dimensions of comparison (table format preferred)
- Verdict or synthesis

## Summary Pages

Answers "what's the *overview* of topic X?" with a topic-organized digest of
multiple sources, re-found by browsing the topic. Include:

- Topic and scope
- Key findings or claims, organized by sub-topic
- Open threads / unresolved questions

## Query Pages

Answers "what's the answer to *my specific question*?" with a
question-organized synthesis filed back so future re-asks hit the page
instead of re-deriving. Use when the question shape itself is what makes
the answer valuable. Include:

- The question, verbatim, as the title
- The synthesized answer with cross-links to entity / concept / source pages
- Confidence and caveats

## Procedure Pages

Answers "*how* should X be done?" with one page per **procedural rule** the
agent (or human operator) applies when working in this domain (workflows,
conventions, runbooks, build steps, sourcing rules, review checklists,
naming rules). Procedure pages capture *how-to* knowledge and complement
the *what/why* knowledge in entity, concept, and comparison pages. They
are first-class wiki citizens with the same frontmatter, lint, and tag
and index discipline as content pages.

A procedure page reads as steps an operator follows. Pages that read as
facts about how a mechanism works, even when worded as "rules govern X",
stay descriptive and file as `concept`.

Page anatomy:

- **Title** at H1; one-paragraph summary directly below stating the rule and its scope.
- **When this applies**: the trigger. What is the operator about to do that pulls this page in?
- **The rule**: the evergreen content. Tight, self-contained, independent of any specific worked example.
- **Pitfalls / edge cases** (optional): short, rule-shaped only. Not a place for "and once we did X" narrative.
- **See Also**: links to related procedure pages and any worked-example sources where the rule was instantiated.

**Atomic vs. hub.** Atomic procedure pages answer one question (e.g.,
"how precise should my citation be?"). Hub pages chain three or more
atomic rules into a multi-step workflow and link out to the atomics;
their body is a numbered list of "now read X, then read Y, then …",
not a re-statement of the underlying rules.

**Where worked examples live.** Procedure pages hold the rule. Worked
examples and anecdotes live where they were generated:

- Source-specific worked examples live on the source sidecar in `raw/<kind>/<slug>.md`.
- Mechanism-explanation worked examples live on the relevant `concepts/` page.

If commentary starts accumulating on a procedure page, hoist it. See the
**Capture Procedure** protocol in `SKILL.md` for the strip-the-instance
workflow and the three generality tests.

## Update Policy

When new information conflicts with existing content:

1. Check the dates, since newer sources generally supersede older ones
2. If genuinely contradictory, note both positions with dates and sources
3. Mark the contradiction in frontmatter: `contradictions: [page-name]`
4. Flag for user review in the lint report

## Lint

`scripts/lint.py` walks every Markdown file under the type folders and always
skips the `raw/` and `_archive/` trees. A vault that also holds non-page
folders, such as synced notes, generated artifacts, or imported working files, names
them here so the page rules (frontmatter, links, structure, orphans) stay off
files that were never meant to be wiki pages:

```text
- Page-check exclusions: notes, generated
```

List the directory names directly under the wiki root, comma-separated, on one
`Page-check exclusions:` bullet. The names are additive to the always-skipped
`raw/` and `_archive/`, not a replacement. Omit the bullet when the vault holds
only pages. The default skips the two standard trees and nothing else. The
linter reads this bullet only outside fenced code blocks, so the example above
is documentation rather than a live setting.
