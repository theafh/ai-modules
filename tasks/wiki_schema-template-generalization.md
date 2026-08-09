---
description: Make the shipped wiki SCHEMA template domain-neutral and instruction-shaped: resolve its provenance contradiction, cut redundancy, fix script paths, add freshness and fact-ownership rules.
scope: plugins/knowledge_management/skills/wiki/references
created: 2026-08-09T14:02:01
updated: 2026-08-09T16:20:00
status: open
reported-by: Andreas Hoffmann
---

# Generalize the shipped wiki SCHEMA template for any domain and for existing-wiki migration

## Goal

The schema template the `wiki` skill ships reads as one correct, domain-neutral,
instruction-shaped document serving both delivery paths: a fresh wiki scaffolded by
`init_wiki.sh`, and an existing wiki brought onto the current contract. After this task
it carries no self-contradicting rule, no example identifier borrowed from a domain the
wiki does not cover, no path that resolves nowhere, and no rule stated twice; its rule
bullets read as instructions rather than as descriptions of a state; and it states three
conventions it currently leaves each wiki to invent, namely how a page records when a
claim was last checked, which page owns a fact several pages touch, and where a decision
record and planned work belong. Existing wikis converge as pages pass through audit and
repair, with no forced migration sweep.

## Context

### What the artefact is and how it reaches a wiki

[template_schema.md](../plugins/knowledge_management/skills/wiki/references/template_schema.md)
is the canonical schema shipped with the `wiki` skill, and two shipped mechanics decide
how much of it an owner ever revisits. `init_wiki.sh` copies it to `SCHEMA.md`
unchanged (locate by the comment phrase `SCHEMA.md is copied verbatim`), then its
closing hint names two things to customize, the domain and the tag taxonomy, so
everything else lands as shipped. `lint.py` then locks exactly one region against the
template through `VERBATIM_SLOTS`, the slot labelled
``SCHEMA.md prelude (H1 plus paragraphs above first `##`)``, warning when a wiki's copy
differs. So the region the linter defends is the attribution paragraph, while every
domain-flavoured example sits unguarded and unmentioned. Defects 2 and 8 below turn on
those two mechanics.

The defects below come from reading the template against those mechanics and against one
wiki generated from it. That wiki is evidence a defect reproduces in practice, never a
target to copy: the standing repo charter's DOES NOT boundary keeps generated output from
standing as the source of truth for shipped behaviour. Justify every change by what a
schema for an arbitrary domain needs.

### The defects, each anchored to a verbatim string in the template

1. **The provenance rule contradicts itself on placement.** The bullet opening
   `- **Provenance:** this is an LLM-first wiki` requires attribution `next to` the
   claim, states `not collected at the bottom of the page`, and adds
   `Pages do not carry a body "Sources" section`. The next bullet, opening
   `- **Derived from:** some pages exist because external material exists`,
   prescribes a bottom-of-page section. The first forbids the placement the second
   requires. The intended split is by object, a captured source versus uncaptured
   external lineage, while the prose states it as a rule about the page.
2. **A conditional 60-line block ships unconditionally.** The `### raw/ Frontmatter`
   subsection, from `Raw sources ALSO get a small frontmatter block so re-ingests can detect drift:`
   through its `sha256:` paragraph, is required reading for a wiki that ingests
   external sources and inert for one that does not. It arrives in full either way and
   is paid for on every read. The `REQUIRED_FRONTMATTER` tuple in `lint.py` is the same
   problem in miniature: `sources` is mandatory on every page, so a wiki capturing
   nothing into `raw/` satisfies the contract only with an empty list everywhere.
3. **The type table and the six per-type sections restate each other.** The
   `## Page Types: Pick by Question` table gives one line per type, and each of
   `## Entity Pages` through `## Procedure Pages` reopens with that same question almost
   verbatim. The include-lists carry the value; the repeated question does not.
4. **The contradiction workflow is stated three times.** The `contested: true` comment in
   the frontmatter block, the sentence beginning
   ``Lint surfaces `contested: true` and `confidence: low` pages for review``, and the whole
   `## Update Policy` section each cover it.
5. **The tag rule is stated twice, once inside a placeholder that gets deleted.** The
   bracket `[Define 10–20 top-level tags for the domain. Add new tags here BEFORE using them.]`
   carries a rule the standing bullet
   `Rule: every tag on a page must appear in this taxonomy.` also carries, and the
   placeholder goes on customization, so the rule survives by luck.
6. **Domain-specific example identifiers sit inside domain-neutral rules.** The
   folder-layout bullet illustrates with `concepts/transformer.md` and
   `entities/openai.md`; the cross-link bullet uses a link whose target is
   `../concepts/transformer.md`; the provenance fence carries a claim opening
   `Transformers replaced RNNs for most sequence tasks by 2019`. Nothing instructs an
   operator to localize them, so a wiki on any other subject ships instructions
   illustrated from machine learning.
7. **Two script paths resolve nowhere.** The invocation
   `python3 scripts/compute_sha256.py raw/<kind>/<slug>.md` and the sentence opening
   `` `scripts/lint.py` walks every Markdown file under the type folders `` are read from
   the wiki root, where no `scripts/` directory exists, so both are correct only for an
   in-place checkout. The wiki front-end skills already state this hazard for bare
   `scripts/...` invocations.
8. **The attribution paragraph is enforced rather than offered.** The paragraph opening
   ``This LLM-Wiki is managed by the `wiki` skill created by`` is the sole content of the
   region `VERBATIM_SLOTS` defends, so an owner who removes it draws a warning telling
   them to restore it. Shipping it is intended; compelling it is not. Nothing else reads
   the `extract_h1_prelude` helper for `SCHEMA.md`, while the second slot uses that same
   helper to guard `log.md`'s conventions blockquote, which is load-bearing format
   documentation and keeps its lock.
9. **Rule bullets mix three moods, and the un-enforced ones read as description.**
   Descriptive present carries some rules (`Every page lives directly at`,
   `Every wiki page starts with YAML frontmatter`), modal obligation others
   (``Every new page must be added to `index.md` ``), the imperative the rest
   (`List the directory names directly under the wiki root`). A rule phrased as a
   description reads as an observation an agent may note rather than an instruction it
   must apply, which is what happened to the inline-citation convention in the
   generated wiki: linted rules were followed and this un-linted descriptive one was
   not.
10. **Two negatives restate their own positive.** The folder-layout bullet's
    `No thematic prefix folders, no sub-folders inside a type folder, no pages at the wiki root.`
    adds nothing once the positive says pages live flat and one layer deep at
    `<pluralized-type>/<slug>.md`, and the filename bullet's `no spaces` adds nothing once
    the positive names hyphens as the separator. Every other negative in the file is
    load-bearing and stays.

### The three conventions the template leaves each wiki to invent

<!-- markdownlint-disable MD029 -->

11. **No freshness convention.** `created` and `updated` record when the page was
    written, and nothing records when a claim was last checked against the world. Any
    wiki tracking a moving external subject needs that; the generated wiki invented an
    unlinted prose paragraph per page to supply it.
12. **No fact-ownership rule.** The page-type model invites one fact onto several
    pages: a comparison compares what entities describe, and a concept explains a
    mechanism entities list. Nothing says which page owns a fact and which points at
    the owner, so independently worded copies drift. This is the highest-value
    addition, because it generates drift rather than untidiness.
13. **No stated home for a decision record or for planned work.** The declared types
    cover what is true, how things compare, and how to act. A record of a decision
    argued and settled, and a plan for work not yet done, fit none cleanly, and a
    repository with a task backlog has a competing home for the second.

    Both halves have a settled answer the template must state, so implement these
    rather than re-deriving them. **A decision record files under the declarative
    type that fits what it explains** — `concept` for the reasoning behind a single
    mechanism, `comparison` for a choice argued between alternatives — and no
    decision-record type is added, because a new type fragments the schema for
    pages the describe-versus-prescribe test already places. **Planned work that is
    not yet a unit of work belongs on the page whose subject it extends**, in that
    page's open-questions or open-threads section, and graduates to the task
    backlog once it becomes one; the wiki carries the intent and the reasoning
    behind it, the backlog carries the work. State both in the template as rules in
    their own right. Confirm each against the current template text first and skip
    whichever already reads that way.

### Files involved

- [template_schema.md](../plugins/knowledge_management/skills/wiki/references/template_schema.md)
  — the primary and largest edit surface.
- [lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) —
  `REQUIRED_FRONTMATTER` for defect 2, `VERBATIM_SLOTS` for defect 8.
- [SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) — every authoring-contract
  rule this task rewords, so the two tell one story.
- [lint_checks.md](../plugins/knowledge_management/skills/wiki/references/lint_checks.md)
  — documented behaviour of any check this task changes.
- [auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md) — its
  `<configurable_zones>` classification, so a reworded canonical region is not read as drift.

### Related tasks and the coordination boundary

Five live tasks own passages in this same file, and this task leaves each alone:

- [wiki_provenance-via-raw-and-sources.md](wiki_provenance-via-raw-and-sources.md)
  owns the capture rule and the channel boundary inside the **Provenance** block
  (which material lands in `raw/` versus `## Derived from`). This task owns only the
  placement contradiction in defect 1. Both edit the same two bullets, so whichever
  lands second rewrites over the first rather than appending a second statement.
- [wiki_page-type-growth-and-anatomy.md](wiki_page-type-growth-and-anatomy.md) owns
  the `**Split a page**` threshold bullet and the custom-type anatomy guidance.
- [wiki_lint-accepted-info-suppression.md](wiki_lint-accepted-info-suppression.md)
  owns the accepted-finding mechanism.
- [wiki_non-english-languages-ascii-slugs.md](wiki_non-english-languages-ascii-slugs.md)
  rewrites the `File names:` bullet for ASCII slugs and already names its English-only
  example as part of its gap, so both the `no spaces` trim in defect 10 and that bullet's
  example belong to it. Defect 6 covers only the folder-layout, cross-link, and
  provenance-fence examples.
- [wiki_synthesis-citation-consistency-lint.md](wiki_synthesis-citation-consistency-lint.md)
  compares `sources:` against inline links, so making the field optional in defect 2
  gives that check an absent-field case to handle.

The archived [wiki_lint-blind-spots-and-false-positives.md](archive/wiki_lint-blind-spots-and-false-positives.md)
already fenced the `Example for AI/ML:` taxonomy block so it stops parsing as live config,
so defect 6 is the remaining unfenced set elsewhere in the file.

## Approach

Rewrite each affected passage in place to its target form. The template stays one file
with in-file declaration bullets, matching the pattern the `## Lint` section already
establishes, rather than becoming fragments the init script assembles.

1. **Provenance placement.** Restate the two bullets as one rule about two objects: cite
   a captured source inline next to the claim through a relative link into `raw/`, and
   record lineage for never-captured material in a bottom `## Derived from` section. Drop
   the phrases `not collected at the bottom of the page` and
   `Pages do not carry a body "Sources" section` in favour of a statement naming what
   each channel carries. Keep the `Footnote markers` prohibition verbatim.
2. **Conditional blocks.** Open `### raw/ Frontmatter` with a one-sentence
   applicability statement naming the wikis it governs. Drop `sources` from
   `REQUIRED_FRONTMATTER` to the optional set, document it in the frontmatter block as
   present when the page cites a captured source, and record the absent-field case in
   `lint_checks.md`.
3. **Type-section redundancy.** Keep the `## Page Types: Pick by Question` table as
   the single statement of each type's question, and open each per-type section with
   its include-list.
4. **Contradiction-workflow redundancy.** State the workflow once in `## Update Policy`,
   reducing the frontmatter comment and the lint sentence to pointers at it.
5. **Tag-rule redundancy.** Strip the rule from the bracketed placeholder, leaving it
   a pure slot marker, and keep the standing
   `Rule: every tag on a page must appear in this taxonomy.` bullet as the single
   statement.
6. **Domain-neutral examples.** Replace the folder-layout, cross-link, and
   provenance-fence identifiers with slug-shaped neutrals carrying the same shape
   without naming a subject, and add one instruction to localize every remaining
   example identifier during customization, so the neutral form is a floor rather than
   the end state.
7. **Script paths.** State both invocations as skill-relative and name how they
   resolve, consistent with the path-resolution rule the wiki front-end skills carry.
8. **Ship the attribution, stop enforcing it.** Keep the attribution paragraph in the
   shipped template so every wiki the skill creates carries it, and drop the `SCHEMA.md`
   entry from `VERBATIM_SLOTS` so an owner who reads it and would rather not keep it can
   delete it without a lint finding. Leave the `log.md` entry and the
   `extract_h1_prelude` helper in place, since that slot guards format documentation
   rather than credit.
9. **Mood pass.** Rewrite every rule bullet in the imperative, opening with an action
   verb and preserving each rule's exact requirement strength: an obligation stays an
   obligation, a recommendation stays a recommendation. Sharpen
   `Default to the canonical fields — invent custom ones sparingly` into a test an
   author can apply, naming the value set and the question no canonical field answers.
10. **Negative trims.** Cut the folder-layout bullet's three-clause negative, whose
    positive already implies it. Leave every load-bearing negative untouched: the
    `Footnote markers` prohibition names an exact banned form the positive cannot imply,
    and the raw-block absolute-path prohibitions mirror what the linter blocks.
11. **Freshness convention.** Add an optional frontmatter field recording the date a
    page's claims were last checked against their subject, declared beside `confidence`
    and `contested`, with the rule that a page drawing on a moving external subject
    carries it and a page without it is a page to re-check. Ship it as an optional
    signal with no new blocking check.
12. **Fact-ownership rule.** Add a convention naming which page owns a fact several
    pages touch and requiring every other page to point at the owner rather than
    restate it. State it once, in the template or in the `SKILL.md` authoring contract,
    with the other pointing at that statement.
13. **Decision and planned-work routing.** State where a settled decision and a plan
    for undone work belong, covering both a standalone wiki and one beside a backlog.
14. **Migration path.** State that an existing wiki converges opportunistically as
    pages pass through audit and repair, with no migration sweep, matching the
    convergence precedent the task family already uses. Confirm the agent's
    `<configurable_zones>` classification still reads each reworded canonical region
    as canon rather than as drift.

**Out of scope:**

- The `**Split a page**` threshold and custom-type anatomy guidance, owned by
  [wiki_page-type-growth-and-anatomy.md](wiki_page-type-growth-and-anatomy.md).
- The per-finding accepted-lint mechanism, owned by
  [wiki_lint-accepted-info-suppression.md](wiki_lint-accepted-info-suppression.md).
- The raw-capture trigger and the `raw/` versus `## Derived from` channel boundary,
  owned by
  [wiki_provenance-via-raw-and-sources.md](wiki_provenance-via-raw-and-sources.md).
- The `File names:` bullet, owned by
  [wiki_non-english-languages-ascii-slugs.md](wiki_non-english-languages-ascii-slugs.md).
- A new machine-read declaration bullet in the `## Lint` section, since two live tasks
  already add bullets there; the conventions here ship as prose and as an optional
  frontmatter field instead.
- A lint check enforcing the fact-ownership rule, since detecting a restated fact across
  pages is a judgement the linter cannot make deterministically.

## Acceptance

- Searching the reworked template for `not collected at the bottom of the page` and
  for `Pages do not carry a body "Sources" section` returns nothing, and one rule
  states inline citation for captured sources beside `## Derived from` for uncaptured
  lineage.
- `### raw/ Frontmatter` opens with an applicability sentence naming which wikis it
  governs.
- `sources` is absent from the `REQUIRED_FRONTMATTER` tuple; a fixture page with no
  `sources:` key draws no blocking finding, while a fixture page whose `sources:`
  entry does not resolve on disk still does.
- Each per-type section from `## Entity Pages` through `## Procedure Pages` opens with
  its include-list, and the type question appears only in the
  `## Page Types: Pick by Question` table.
- `## Update Policy` carries the contradiction workflow, and the frontmatter comment
  and the lint sentence point at it rather than restating the steps.
- The tag-taxonomy placeholder bracket no longer carries the add-before-use rule, and
  the standing `Rule: every tag on a page must appear in this taxonomy.` bullet is its
  single statement.
- Searching the template for `transformer`, `openai`, `Vaswani`, and `RNNs` returns
  only hits inside the `File names:` bullet that
  [wiki_non-english-languages-ascii-slugs.md](wiki_non-english-languages-ascii-slugs.md)
  owns, and the template carries one instruction to localize remaining example
  identifiers during customization.
- Searching for `python3 scripts/compute_sha256.py` and for `` `scripts/lint.py` walks ``
  returns no bare wiki-root-relative form; both read as skill-relative with their
  resolution named.
- Every rule bullet in `## Conventions` opens with an action verb, and each changed
  bullet's requirement strength matches the passage it replaced, checked by quoting
  before and after side by side.
- The folder-layout bullet's `No thematic prefix folders` clause is gone, while the
  `Footnote markers` prohibition and the raw-block absolute-path prohibitions are
  unchanged.
- The frontmatter block declares the optional freshness field with its value shape; a
  fixture page carrying it lints clean and a fixture page omitting it lints clean.
- The fact-ownership rule appears once across the template and the `SKILL.md`
  authoring contract, with the other location pointing at that statement.
- The template states where a settled decision and a plan for undone work belong,
  including a wiki beside a task backlog.
- A wiki scaffolded fresh by `init_wiki.sh` from the reworked template, with domain and
  taxonomy filled in and nothing else touched, carries the attribution paragraph and
  lints with zero blocking and zero warn findings.
- A fixture wiki whose owner deleted the attribution paragraph from `SCHEMA.md` draws no
  `boilerplate` finding, while a fixture wiki whose `log.md` conventions blockquote was
  altered still draws one, proving the second slot kept its lock.
- A fixture wiki carrying the pre-rework `SCHEMA.md` draws no blocking finding after
  this change, proving existing wikis need no migration sweep.
- `tests/wiki/run_all.sh --layer2` passes.
