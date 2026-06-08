---
name: wiki
description: Activate this skill whenever the user mentions their wiki, knowledge base, or research notes in any way — including queries that compare, contrast, reference, analyze, or discuss wiki content rather than ask to edit it. Build and maintain a persistent, compounding knowledge base of interlinked plain markdown files. Use when the user asks to create, build, start, or initialize a wiki or knowledge base; add, create, or write wiki pages; query, compare, contrast, reference, or analyze an existing wiki to answer a research or domain question; archive or reorganize wiki pages; or whenever the user names the wiki, the knowledge base, or their notes in the current request even as a passing reference.
version: 1.16.0
author: Andreas F. Hoffmann
license: MIT
---

# Wiki

<wiki>

<role>
This LLM-Wiki is managed by the `wiki` skill created by Andreas F. Hoffmann from the `knowledge_management` plugin in [theafh AI-repo](https://github.com/theafh/ai-modules).

Unlike traditional RAG (which rediscovers knowledge from scratch per query),
the wiki compiles knowledge once and keeps it current. Cross-references are
already there. Contradictions have already been flagged. Synthesis reflects
everything ingested.

**Division of labor:** the human curates sources and directs analysis. The
agent summarizes, cross-references, files, and maintains consistency.
</role>

<orient_first_top>
**Read `$WIKI/SCHEMA.md` once at the start of any session that activates this
skill.** The schema declares the domain, the page-type enum, the tag taxonomy,
and the conventions every subsequent action must honor — reading it first
prevents wrong-type pages, off-taxonomy tags, and duplicate or misfiled work.
The full orientation pass (SCHEMA + index + recent log) is covered in
`<resuming_an_existing_wiki>`; this top-line note exists so the SCHEMA read is
never skipped, even on quick queries.
</orient_first_top>

<when_to_activate>
Use this skill when the user:

- Asks to create, build, or start a wiki or knowledge base.
- Asks to ingest, add, or process a source into their wiki.
- Asks a question that an existing wiki at the discovered location could answer.
- Asks to lint, audit, fix, health-check, clean up, or auto-repair their wiki — delegate the work to the `wiki_auto_shaper` agent (see `<lint_and_audit>`).
- References their wiki, knowledge base, or "notes" in a research context.
- Asks to capture procedural knowledge — workflows, conventions, runbooks — alongside the wiki's subject pages.
</when_to_activate>

<architecture>
Three layers carry the wiki:

```text
wiki/
├── SCHEMA.md           # Conventions, structure rules, domain config
├── index.md            # Sectioned content catalog with one-line summaries
├── log.md              # Chronological action log (append-only, rotated yearly)
├── raw/                # Layer 1: Immutable source material
│   ├── articles/       # Externally-published articles, web clippings
│   ├── papers/         # PDFs, arxiv papers
│   ├── meetings/       # Meeting notes, interviews, spoken-word transcripts (podcasts, talks)
│   ├── notes/          # Internal memos, discussion writeups, ad-hoc observations, internal docs not published externally
│   └── assets/         # Images, diagrams referenced by sources
├── entities/           # Layer 2: Entity pages (people, orgs, products, models)
├── concepts/           # Layer 2: Concept/topic pages
├── comparisons/        # Layer 2: Side-by-side analyses
├── queries/            # Layer 2: Filed query results worth keeping
├── summaries/          # Layer 2: Standalone overview / digest pages
└── procedures/         # Layer 2: Procedure / workflow / how-to pages
```

**Layer 1 — Raw Sources.** Immutable. The agent reads but never modifies these.
**Layer 2 — The Wiki.** Agent-owned markdown files. Created, updated, and
cross-referenced by the agent. Page types split into *declarative* (what / why)
and *procedural* (how) — see `<page_types>` below.
**Layer 3 — The Schema.** `SCHEMA.md` defines structure, conventions, and tag
taxonomy. The linter reads its `## Frontmatter` yaml block to learn the
page-type enum, so wikis can declare additional types there without modifying
the linter.

<folder_layout>
**The folder tree is the type axis only.** Every page lives directly at
`<pluralized-type>/<slug>.md` — flat, one layer deep. No thematic prefix
(`themes/ai/concepts/foo.md` is wrong), no sub-folder nesting inside a type
folder (`concepts/ai/foo.md` is wrong), no bare files at the wiki root.
Thematic scope belongs in `tags:` and `type:`, not in folder names — tags have
an enumerated taxonomy in SCHEMA.md and don't drift the way emergent theme
folders do. The linter's `structure` check enforces this with **blocking**
severity on misfiled pages (with a concrete move suggestion) and **warn**
when an expected type folder is missing on disk. Because the wiki's primary
consumer is an LLM with tools — which greps and follows links rather than
browsing — visual folder shelving adds no real value and trades it for
filing-drift risk.
</folder_layout>
</architecture>

<page_types>
Each page type answers a different *shape* of question. Pick by the entry
point you (or a future operator) will re-find the page from.

| Type | Answers | When to use |
| --- | --- | --- |
| **entity** | "Who/what *is* X?" | A single named person, org, product, model, place — something with identity. |
| **concept** | "What does X *mean*, and why?" | An idea, mechanism, or technique that's describable on its own. |
| **comparison** | "How does X *compare to* Y?" | Side-by-side with dimensions and a verdict. |
| **summary** | "What's the *overview* of topic X?" | Topic-organized digest. Re-found by browsing the topic. |
| **query** | "What's the answer to *my specific question*?" | Question-organized synthesis. Re-found by re-asking. |
| **procedure** | "*How* should X be done?" | An evergreen rule, convention, or workflow. The page holds the *rule*; the instance that prompted it lives elsewhere. |

<declarative_vs_procedural>
**Declarative vs procedural — the load-bearing split.** Entity, concept,
comparison, summary, and query capture *what is true* and *why* (subject
knowledge). `procedures/` captures *how to act* and *how things should be
organized* (operational knowledge — workflows, conventions, runbooks, build
steps, sourcing rules, review checklists, naming rules). A wiki without
procedure pages is a research notebook; a wiki without the declarative types
is just a runbook collection. Most projects need both.
</declarative_vs_procedural>

<summary_vs_query>
**summary vs query.** Same content, different framing. Topic-organized →
summary. Question-organized → query. When both work, prefer **summary** —
broader entry surface. File as **query** only when the question shape itself
is what makes the answer valuable.
</summary_vs_query>

<procedure_vs_concept>
**procedure vs concept.** Both page types can answer "how"
questions, but they answer different ones:

- A **concept** answers "how does X work?" or "what is X?" — the
  reader walks away understanding a feature, mechanism, or design
  choice the project implements. Concept pages can be deeply
  technical, can discuss how the system was built and why it was
  designed a certain way, and can carry rules that constrain
  authors. Those rules describe *properties* of the system
  ("errors must live in a closed set", "module folders contain
  `main.mdl`") — they are facts about how the project is built,
  not actions a contributor performs.
- A **procedure** answers "how do I do X?" or "what do I do when
  Y?" — the reader walks away with the sequence of actions needed
  to accomplish a specific task. Procedure pages are action lists:
  open this file, add this variant, implement these methods, run
  this test.

"How transformers attend" (how does X work → concept) vs "How to
add a new training run" (how do I do X → procedure). Both contain
"how". The first describes the system; the second prescribes an
action sequence.

The trap: a page about how the system works can wear imperative
voice and operator-facing scaffolding — trigger lists, "must"
bullets, pitfalls — and still be a concept. Authorial rules that
describe system properties belong on concept pages even when they
constrain author behavior. A procedure page is the one that lists
the actual steps a contributor takes (open file X, add variant Y,
run command Z). If you are not writing those steps, you are not
writing a procedure.

Test before you file. Write the question the page answers. "How
does X work?" or "What is X?" → concept. "How do I do X?" or
"What do I do when Y?" → procedure. If the answer to "how does
this page help me?" is "I now understand how the system works",
that is a concept; if the answer is "I now know the steps to
take", that is a procedure.
</procedure_vs_concept>

<page_anatomy>
**Page anatomy.** Once the type is picked, write the sections in this order:

| Type | Sections (in order) |
| --- | --- |
| **entity** | Overview · Key facts and dates · Relationships to other entities |
| **concept** | Definition / explanation · Current state of knowledge · Open questions or debates · Related concepts |
| **comparison** | What is being compared and why · Dimensions (table preferred) · Verdict / synthesis |
| **summary** | Topic and scope · Key findings by sub-topic · Open threads |
| **query** | Question (verbatim, as the page title) · Synthesized answer with cross-links · Confidence and caveats |
| **procedure** | One-paragraph rule summary · When this applies (the trigger) · The rule · Pitfalls / edge cases (optional, rule-shaped only) · See Also |

Cross-links go in every section that references another wiki page. Source
attribution lives in the `sources:` frontmatter — a list of
`raw/<kind>/<slug>.md` paths the lint validates against disk. The frontmatter
is the single source of truth; pages do not carry a separate body "Sources"
section, and per-claim attribution uses inline standard-markdown links rather
than footnote markers (see `<write_or_update_pages>`). External material the
page was distilled from but that stays outside `raw/` — e.g. doctrine in
another repo — goes into an optional `## Derived from` body section at the
page bottom; the renamed heading does not match the linter's deprecated
`## Sources` regex, so it does not collide with the structured `sources:`
channel.
</page_anatomy>

</page_types>

<tools>
Three bundled scripts handle discovery, init, and lint. **Always run
`discover_wiki.sh` first** — never resolve the wiki path with your own
inline Python or shell logic; the script is the single source of truth
for walk-up semantics, and bypassing it is what causes silent upstream
adoptions.

```bash
if output=$(scripts/discover_wiki.sh); then
    WIKI="$output"                                    # auto-resolved
else
    rc=$?
    case $rc in
        2) candidates="$output" ;;                    # ambiguous → ASK USER
        *) exit "$rc" ;;
    esac
    # On exit 2, follow <resolving_the_wiki_location> below before
    # touching any wiki file. Do not pick a candidate yourself.
fi
[[ -d "$WIKI" ]] || scripts/init_wiki.sh "$WIKI"    # scaffold if missing
python3 scripts/lint.py                              # health-check
```

<discover_wiki>
`discover_wiki.sh` recognises a directory as a wiki when its basename contains
"wiki" (case-insensitive) **and** at least two of `SCHEMA.md` / `index.md` /
`log.md` exist directly inside it **and** it carries no `.no_wiki`. (A fresh
wiki has all three markers, so the 2-of-3 rule still resolves one that lost a
marker; a directory merely named `wiki` without markers is not adopted.)

It resolves in this order:

1. **CWD short-circuit** — if the current working directory is itself a
   recognised wiki, print it and stop, before any walk-up. This covers
   standing inside a wiki, including a topic-named one like `ml-wiki/`.
2. **Walk up** level by level from CWD toward `$HOME`. At each level:
   - **`<level>/.no_wiki`** present → opted out; skip and continue up.
   - a **child directory recognised as a wiki** (lexically first wins) →
     record as the existing wiki and STOP walking (the search never crosses
     an existing wiki). A second matching sibling at the same level is not
     surfaced.
   - **neither** → record as an "available" creation candidate and continue up.

The script auto-resolves on stdout (exit 0) when it can:

- CWD is itself a wiki (short-circuit), or the closest non-opted-out level
  holds a recognised wiki → print that path.
- Every level visited up through `$HOME` is opted out via `.no_wiki` → print
  `$HOME/wiki` (the explicit "use the global wiki" chain).

Otherwise the script exits 2 and lists every candidate in walk order on
stdout, one per line, prefixed with its kind:

```text
AVAILABLE:/Users/foo/projects/myproject/src
AVAILABLE:/Users/foo/projects/myproject
AVAILABLE:/Users/foo/projects
EXISTING:/Users/foo/wiki        # only as the last entry, if found
```

When CWD is not at or under `$HOME`, walk-up is disabled and the script
falls back to the pre-walk-up behavior (a recognised wiki child of CWD,
`./.no_wiki`, or ask).

`.no_wiki` is the explicit opt-out and overrides the predicate: drop an empty
file by that name in any directory you do not want a local wiki for, and the
walk skips that level. Place it at an existing `<wiki-path>/.no_wiki` to retire
that wiki dir without deleting it — discovery then declines to adopt it.
</discover_wiki>

<init_wiki>
`init_wiki.sh` materializes `SCHEMA.md`, `index.md`, `log.md`, and the
standard directory tree from canonical templates in
`references/template_schema.md`, `template_index.md`, `template_log.md`. It
refuses to overwrite an established wiki. To customize the schema beyond the
placeholders, read `references/template_schema.md` for the full annotated
template (domain, tag taxonomy, page-type sections, update policy).
</init_wiki>

<lint>
`lint.py` reads the page-type enum from `SCHEMA.md`'s `## Frontmatter` yaml
block — wikis can extend the type set in their schema without touching the
script. See `<lint_and_audit>` below for the iteration loop;
`references/lint_checks.md` has the full check matrix. The
`wiki_auto_shaper` agent wraps `lint.py` with a complete
assess → fix → verify loop in an isolated context — spawn it when the user
asks for a broad audit, lint, fix, health-check, clean-up, or auto-repair
pass over the wiki.
</lint>

<fallback_without_scripts>
Without access to the scripts, perform discovery inline with the same rule: a
directory is a wiki when its basename contains "wiki" (case-insensitive) and
at least two of `SCHEMA.md` / `index.md` / `log.md` are present and it carries
no `.no_wiki`. If CWD is itself a wiki, use it. Otherwise walk up from CWD
toward `$HOME`: at each level treat `<level>/.no_wiki` as "skip", the first
child directory recognised as a wiki (lexical order) as a hit (and stop
walking), anything else as a creation candidate. Auto-resolve only when the
closest non-opted-out level holds a recognised wiki or every level up through
`$HOME` is opted out (use `$HOME/wiki`). Otherwise follow the explicit workflow
in `<resolving_the_wiki_location>` — never silently route to an upstream wiki.
</fallback_without_scripts>
</tools>

<resolving_the_wiki_location>
This is **the** discovery flow. **Every** wiki operation — ingest, query,
update, archive, lint, audit, init — runs it before touching any file in a
wiki. The rule applies regardless of how the user phrased their request
("update the wiki", "add a page", "lint", etc.); the operation does not
begin until this resolves.

<the_hard_rule>
**The hard rule.** When `discover_wiki.sh` exits 2, you MUST present the
candidates and ask the user, **unless `<adopt_when_user_named_the_path>`
applies**. Do **not** silently adopt an upstream `EXISTING:` candidate
when CWD is an unresolved `AVAILABLE:` level — the user may want a local
wiki for this directory, and silently writing to a wiki one or more
levels above the current project is a confidentiality and scoping
mistake. Exit 2 is the script telling you the location is **ambiguous**,
not a recommendation.
</the_hard_rule>

<adopt_when_user_named_the_path>
**Carve-out to `<the_hard_rule>`.** When the user's current request
explicitly names one of the `AVAILABLE:` or `EXISTING:` paths returned
by exit 2, adopt that path without prompting and **report the adoption
in one line** so the auto-choice is observable to the user, e.g.

> `Using $WIKI=/path/to/wiki (per your message).`

The user can correct in the next turn if the match was wrong — silence
is the failure mode this surface report exists to prevent. Two bounds
keep this safe:

- **Only adopt a path the script surfaced.** If the user named a path
  that is not on the exit-2 candidate list, fall back to the full
  `<the_flow>` — never invent or extrapolate a wiki location.
- **Only when the user named exactly one candidate in the current
  request.** If the user named none, or named more than one, present
  all candidates and ask.
</adopt_when_user_named_the_path>

<the_flow>

<run_discovery>
**Run `scripts/discover_wiki.sh`.**

- **Exit 0** → the script printed a single resolved path on stdout.
  Adopt it as `$WIKI`. If the path does not yet exist on disk, init it
  with `scripts/init_wiki.sh "$WIKI"` before proceeding.
- **Exit 2** → stdout is the candidate list (one `AVAILABLE:<path>` or
  `EXISTING:<path>` per line, in walk order from CWD upward). Continue
  with `<present_candidates>`. Do not pick a candidate yourself.
</run_discovery>

<present_candidates>
**Present every candidate to the user, in walk order**, with the kind
spelled out so the choice is unambiguous:

- `AVAILABLE` — no wiki at that level yet; selecting it creates one
  there via `init_wiki.sh`.
- `EXISTING` — a wiki already lives at that level; selecting it adopts
  that wiki for the current operation.

Ask: **"Which path should host the wiki for this operation?"** Wait
for the user's answer.
</present_candidates>

<offer_no_wiki_markers>
**Offer `.no_wiki` markers** for the unchosen `AVAILABLE` candidates
between CWD (inclusive) and the chosen path (exclusive) — the levels
the user walked over to reach their pick. Ask once, covering all of
them in a single yes/no:

> "Drop a `.no_wiki` opt-out marker in `<path-1>`, `<path-2>`, …
> so future walks from those subtrees skip straight past?"

On yes, create an empty `.no_wiki` file at each path. On no, leave
them untouched. Levels above the chosen path are not offered markers —
the walk-up will short-circuit at the chosen wiki anyway.
</offer_no_wiki_markers>

<proceed_with_operation>
**Only now** scaffold (if the chosen path needs it via
`init_wiki.sh`) and proceed with the operation against `$WIKI`.
</proceed_with_operation>

</the_flow>

<common_case>
**Common case worth calling out.** CWD has no wiki and no `.no_wiki`,
but a parent directory does. The script reports
`AVAILABLE:<CWD>` followed by `EXISTING:<parent>/wiki` and exits 2. The
default response is **to ask** — silently routing to the upstream is the
mistake `<the_hard_rule>` exists to prevent. The user may want to
(a) create a wiki right here, (b) drop a `.no_wiki` here and let the
upstream wiki own this subtree from now on, or (c) adopt the upstream
wiki for this session without a marker. They pick. The single
exception is `<adopt_when_user_named_the_path>` — when the user's
current request already named one of the candidates, adopt it and
report the adoption in one line instead of asking.
</common_case>

</resolving_the_wiki_location>

<resuming_an_existing_wiki>
When the user has an existing wiki, **always orient yourself before doing
anything**:

1. **Read `SCHEMA.md`** — understand the domain, conventions, and tag taxonomy.
2. **Read `index.md`** — learn what pages exist and their summaries.
3. **Scan recent `log.md`** — read the last 20–30 entries with
   `tail -n 350 "$WIKI/log.md"` (cap each entry at roughly 20 lines; tune the
   tail by entry length). The log can grow to 500 entries before rotation; a
   full read wastes context.

Only after orientation should you ingest, query, or lint. Skipping this causes
duplicate pages, missed cross-references, schema-contradiction, and repeated
work.

For large wikis (100+ pages), also run a quick recursive search (`rg` /
`grep -r`) for the topic at hand before creating anything new.
</resuming_an_existing_wiki>

<initializing_a_new_wiki>
When the user asks to create or start a wiki, `<resolving_the_wiki_location>`
already covers steps 1–3 (run discovery, present candidates, offer
`.no_wiki` markers in unchosen levels). The init-specific steps follow once
`$WIKI` is chosen:

1. **Run `init_wiki.sh "$WIKI"`** against the chosen path to scaffold
   `SCHEMA.md`, `index.md`, `log.md`, and the directory tree.
2. **Customize the schema.** Ask the user what domain the wiki covers —
   be specific. The freshly initialized `SCHEMA.md` has placeholder text
   in the **Domain** and **Tag Taxonomy** sections. Read
   `references/template_schema.md` for what each section should contain.
   Define 10–20 starting tags before any pages are written, since the
   linter flags off-taxonomy tags.
3. **Confirm the wiki is ready** and suggest first sources to ingest.
</initializing_a_new_wiki>

<core_operations>

<ingest>
When the user provides a source (URL, file, paste), integrate it into the wiki:

<capture_raw_source>
**Capture the raw source:**

- URL of an externally-published article → fetch, convert to markdown, save to `raw/articles/`.
- PDF / arxiv paper → extract text, save to `raw/papers/`.
- Meeting note, interview, spoken-word transcript (podcast, talk) → save to `raw/meetings/`.
- Internal memo, discussion writeup, ad-hoc observation, internal doc not published externally → save to `raw/notes/`.
- Pasted text → save to the appropriate `raw/` subdirectory by kind, not by source format.
- For edge cases (article that embeds a transcript, transcript of a private meeting, paste of unknown provenance, etc.) consult `references/raw_taxonomy.md` — the canonical reference for bucket meanings and classification heuristics.
- Name files descriptively: `raw/articles/transformer-architecture-2024.md`.
- Add raw frontmatter (`source_url`, `ingested`, `sha256` of the body —
  body-only). Compute and write the hash with
  `python3 scripts/compute_sha256.py raw/<kind>/<slug>.md` — never invent
  the value by hand. On re-ingest of the same URL: run the same command,
  skip if it reports `ok`, flag drift if it reports `update`.
- **Keep cross-references out of the raw body.** A relative `.md`
  link from one raw file to another is ingester synthesis, not source
  content (originals cite by URL, not by ingester-picked slugs).
  File the cross-reference on the wiki page that cites both sources
  instead.
</capture_raw_source>

<discuss_takeaways>
**Discuss takeaways** with the user — what's interesting, what matters
for the domain. (Skip in automated/cron contexts.)
</discuss_takeaways>

<check_what_already_exists>
**Check what already exists** — search `index.md` and run a recursive
search to find existing pages for mentioned entities/concepts. The
difference between a growing wiki and a pile of duplicates.
</check_what_already_exists>

<write_or_update_pages>
**Write or update wiki pages:**

- **Page thresholds** — apply the right action for what you found:
  - **Create** a new page when an entity/concept appears in 2+ sources OR is central to one source.
  - **Add** to an existing page when content is already covered there.
  - **Skip** passing mentions, minor details, or material outside the domain.
  - **Split** a page that exceeds ~200 lines into sub-topics with cross-links.
  - **Archive** a page whose content is fully superseded — see `<archive>`.
- **Update Policy** — when new content conflicts with what's already on a page:
  1. Check the dates — newer sources generally supersede older ones.
  2. If genuinely contradictory, record both positions with their dates and sources on the page.
  3. Mark the contradiction in frontmatter: `contradictions: [other-page-slug]` and `contested: true`.
  4. Rely on lint to surface contested pages for user review — leave the resolution to the human.
- **Updating existing pages**: always bump the `updated` date.
- **Cross-reference**: every new/updated page links to ≥2 others.
- **Tags**: only from `SCHEMA.md`'s taxonomy. Add new tags to `SCHEMA.md` *before* using them on a page.
- **Provenance**: this is an LLM-first wiki, so attribution stays *next to* the claim it attributes — content that belongs together stays together. Claim-level attribution uses inline standard-markdown links: `Transformers replaced RNNs by 2019 ([Vaswani 2017](../raw/papers/attention-is-all-you-need.md))`. **No footnote markers** (`[^name]` / `[^name]: …`) and **no bottom-of-page "Sources" collection**: both split the claim from its evidence across the page, force the reader (human or LLM) to resolve markers separately, and duplicate what the frontmatter already encodes. The page-level `sources:` frontmatter is the canonical inventory; inline links pin specific claims to specific sources within that inventory, and the lint validates both against disk.
- **External derivation**: when a page is distilled from material that is **not** itself the subject of classification — doctrine in another repo, a codebase, a notebook, a SKILL.md the page summarizes — that material stays where it lives, and the page records the lineage in an optional `## Derived from` body section near the bottom of the page (bulleted list of external paths, URLs, or descriptors with whatever standing commentary applies, e.g. "no parallel repo at the time of writing; re-anchor when one exists"). The renamed heading is deliberately distinct from `## Sources` so the linter does not flag it as the deprecated body-Sources collection. Use `## Derived from` for "the page exists because *that* exists, but *that* is not raw material to ingest"; use `sources:` frontmatter for "this page draws on `raw/<kind>/<slug>.md` material the wiki owns". A page may have either, both, or neither.
- **Confidence**: opinion-heavy / fast-moving / single-source claims → `confidence: medium` or `low`. Reserve `high` for multi-source support.
</write_or_update_pages>

<update_navigation>
**Update navigation:**

- Add new pages to `index.md` under the correct section, alphabetically.
  Update "Total pages" + "Last updated".
- Append to `log.md`: `## [YYYY-MM-DD] ingest | Source Title`. List only
  files actually created or updated in this ingest. Skip files that were
  inspected, considered, or deliberately left unchanged, and do not
  narrate decisions about what *not* to do. Aim for roughly 20 lines per
  entry — if it grows past that, the entry is logging non-changes or
  prose that belongs on a wiki page instead.
</update_navigation>

<run_linter_and_iterate>
**Run the linter and iterate** — `python3 scripts/lint.py`. Fix every
blocking finding before declaring complete. This is the narrow
post-ingest check; for broad audits across the whole wiki, spawn the
`wiki_auto_shaper` agent instead. See `<lint_and_audit>` below.
</run_linter_and_iterate>

<report_what_changed>
**Report what changed** to the user — list only files actually created or
updated, matching what the log entry contains.
</report_what_changed>

<bulk_ingest>
**Bulk ingest** (multiple sources at once): batch the work — read all sources
first, identify all entities/concepts in one pass, check existing pages once
(not N times), write in one pass, update `index.md` once, single batch log
entry. Bulk ingests are the most likely operation to introduce structural
issues, so always lint to clean.
</bulk_ingest>

</ingest>

<capture_procedure>
When the user asks to record a workflow rule, convention, or runbook — or you
notice an operational pattern worth keeping — file it as a **procedure page**.
The page holds the *evergreen rule*; the worked example that prompted it
lives elsewhere. The default failure mode here is over-indexing on the current
example: a procedure page should still read as a rule six months from now on a
different task, with none of today's specifics in it.

<protocol>
Run every step in order:

<name_the_rule>
**Name the rule.** State the policy in 1–3 sentences using the form
"When [trigger], do [action], because [reason]." Keep the trigger and
action operator-neutral; "after every ingest that touches 5+ entities" is a
trigger, "the user just asked X" is not. Confirm the page reads as steps
for an operator to follow — pages that read as facts about how a
mechanism works belong in `concepts/`, even when worded as "rules".
</name_the_rule>

<strip_the_instance>
**Strip the instance.** Replace every proper noun, file path, person's
name, date, error message, command output, and task-specific value with a
category placeholder, or delete it. Read the page back. If it still reads
as a rule, the rule is the carrier; if the page collapses without the
stripped specifics, the example was the carrier and the rule still needs
to be written.
</strip_the_instance>

<hoist_non_rule_content>
**Hoist non-rule content to its proper home:**

- Source-specific anecdote → sidecar in `raw/<kind>/<slug>.md`.
- Mechanism explanation ("why this works") → the relevant `concepts/`
  page.
- Generic war-story without a reusable rule → discard. Not every
  experience earns a page.
</hoist_non_rule_content>

<bound_the_page>
**Bound the page.** Keep atomic procedure pages 30–80 lines. Hub pages
that chain atomics stay 30–60 lines and link out rather than restating
the underlying rules. Past the bound, hoist worked content per
`<hoist_non_rule_content>` or split into two atomic pages.
</bound_the_page>

</protocol>

<generality_tests>
A procedure page that survives all three tests is a keeper:

- **Strip-the-name test.** Replace every proper noun, path, and date with
  `X`. Read the page back. The rule still reads as a rule.
- **Future-operator test.** A different operator, six months from now, on
  a different task in the same domain, recognizes this trigger and applies
  this action.
- **Reusability test.** The trigger fires more than once. One-off
  circumstances belong on the source sidecar where they happened, not in
  `procedures/`.
</generality_tests>

<update_navigation_for_procedure>
**Update navigation:** add the new procedure page to `index.md` under the
procedures section, alphabetically. Update "Total pages" + "Last updated".
</update_navigation_for_procedure>

<reference>
**Reference:** `references/template_schema.md` carries the page anatomy
(sections, atomic vs. hub split, hoist destinations).
</reference>

</capture_procedure>

<query>
When the user asks a question about the wiki's domain:

1. **Read `index.md`** to identify relevant pages.
2. **For wikis with 100+ pages**, also run a recursive search across all
   `.md` files for key terms — the index alone may miss relevant content.
3. **Read the relevant pages.**
4. **Synthesize an answer** with citations: "Based on
   [page-a](concepts/page-a.md) and [page-b](entities/page-b.md)…"
5. **File valuable answers back** if the answer would be painful to re-derive
   (multi-source synthesis, structured comparison, novel reasoning). Pick the
   type by entry point: `comparisons/` for X-vs-Y, `summaries/` for
   topic-organized digests, `queries/` for question-organized answers (see
   `<page_types>`). Skip trivial lookups.
6. **Update `log.md`** with the query and whether it was filed.
</query>

<archive>
When content is fully superseded or the domain scope changes:

1. Create `_archive/` if it doesn't exist; move the page there preserving its
   path (e.g., `_archive/entities/old-page.md`).
2. Remove from `index.md`.
3. Update inbound links — replace with plain text + "(archived)".
4. Log the archive action.
5. Run `python3 scripts/lint.py` to catch any inbound link you missed.
</archive>

<lint_and_audit>
Two paths, picked by scope.

<broad_audits>
**Broad audits — spawn the `wiki_auto_shaper` agent.** When the user asks
to lint, audit, fix, health-check, clean up, or auto-repair the wiki — or
the wiki has accumulated drift across many pages — delegate to the
`wiki_auto_shaper` agent. The agent runs a complete
assess → fix → verify loop in an isolated context: runs `lint.py`,
audits the prose for issues the linter cannot see (topic mixing,
type/anatomy mismatch, procedure-page instance leakage, content violations
of the page-type anatomy), fixes every blocking and warn finding, splits
or relocates pages where the schema demands it, re-lints until the wiki is
clean, appends the audit entry to `log.md`, and reports back a per-file
change list. Keep that work in the agent rather than running the iteration
loop inline — the fix loop on a real wiki touches dozens of files and
displaces conversation context.
</broad_audits>

<narrow_inline_checks>
**Narrow inline checks — run `lint.py` directly.** After a single ingest,
a single archive, a schema edit, or a small batch update, run the linter
in-flow and fix what it surfaces:

```bash
python3 scripts/lint.py              # auto-discover ./wiki (or ~/wiki when ./.no_wiki present)
python3 scripts/lint.py /custom/path # explicit override
python3 scripts/lint.py --quiet      # blocking + warn only
```

Findings come in three buckets:

- **blocking** — broken links, missing/malformed frontmatter, missing
  `index.md`, missing or unparseable `SCHEMA.md` (no extractable type enum).
  Exits 1; must fix.
- **warn** — orphans, contested pages, source drift, off-taxonomy tags,
  invalid enum/date values, pages missing from the index, verbatim-boilerplate
  mismatches (e.g., the SCHEMA.md prelude or log.md preamble drifting from
  the canonical templates in `references/`).
- **info** — markdown style nits, oversized pages, low-confidence
  single-source pages, unused taxonomy tags, log over 500 entries.

Full check matrix: `references/lint_checks.md`.
</narrow_inline_checks>

<inline_iteration_loop>
**Inline iteration loop.** When the lint scope is narrow (one ingest, one
archive), run, fix the highest-severity findings, re-run. Repeat until the
script exits 0 or only acceptable info-level findings remain. Append the
outcome to `log.md`:

```text
## [YYYY-MM-DD] lint | N blocking, N warn, N info
```

If a check is wrong for the situation (e.g., a deliberately oversized
synthesis page), don't silence by editing the script — note the rationale on
the page or in `SCHEMA.md` and accept the info-level finding. The script
surfaces, doesn't enforce.
</inline_iteration_loop>

</lint_and_audit>

</core_operations>

<operational_discipline>

<searching>
```bash
rg "transformer" "$WIKI" -g "*.md"            # by content
fd -e md . "$WIKI"                            # by filename
rg "tags:.*alignment" "$WIKI" -g "*.md"       # by tag
tail -n 350 "$WIKI/log.md"                    # ~last 20 log entries
```
</searching>

<appending_to_log>
"Append-only" means newest at the *bottom* of the file. The Edit tool's
`old_string` matching makes it easy to anchor on a header and insert
*before* it, producing inverted order. Avoid that:

- **Anchor on the previous entry's last body line**, never on a
  `## [YYYY-MM-DD]` header. New content (blank line + new header + body)
  goes *after* the anchor.
- **Cluster ordering matches file ordering.** When one workflow produces
  several entries (ingest → sidecar update → cite), write them earliest-first
  within the cluster — same direction as the whole-file rule. Resist
  reverse-chronological "outcome first" narrative ordering.
- **Verify after every log edit:**

  ```bash
  grep -n '^## \[' "$WIKI/log.md" | tail -5
  ```

  The new entry's line number must be the largest. If not, fix before
  continuing.
</appending_to_log>

<file_handling_discipline>
Three rules keep tool use stable on long wiki sessions. Each addresses a
failure mode observed in real session traces.

<re_read_after_mutation>
**Re-Read each file you plan to Edit or Write after any operation that may
have modified wiki files.** Mutations that invalidate the harness's
"file-has-been-read" state include `git mv`, `mv`, `sed -i`, the linter when
run in auto-fix mode, helper scripts under `skills/wiki/scripts/`
(`compute_sha256.py`, `init_wiki.sh`, `lint.py` with side effects), a
subagent that performed edits during this session, and any external command
that touches the working tree. A stale Read causes the next `Edit` or
`Write` to fail with `<tool_use_error>File has not been read yet. Read it
first before writing to it.</tool_use_error>` and burns 3–5 turns per
occurrence on retries.

The pattern that triggers this most often: rename a page with `git mv`, then
update inbound links across other pages. The inbound-link Edits fail on
stale Reads. Re-Read each file you are about to update *after* the `git mv`,
before the first Edit.
</re_read_after_mutation>

<too_large_to_read_in_one_shot>
**When `Read` fails with `File content (N tokens) exceeds maximum allowed
tokens (25000)`, do not retry the same call.** The file is too large for a
single read and the same call will fail the same way. Switch strategy
instead:

- `Bash wc -l <path>` to size the file, then `Read` with `offset` and
  `limit` to walk it in chunks.
- `Bash grep -n <pattern> <path>` to locate the section you need, then
  `Read` only that range.

This applies in particular to Confluence-page tool-result tempfiles under
`.../tool-results/mcp-claude_ai_Atlassian-getConfluencePage-*.txt` and to
large raw sources (long transcripts, dense PDFs converted to markdown). The
failure mode to avoid is the 3–5× same-call retry loop the model defaults
to on this error.
</too_large_to_read_in_one_shot>

<list_before_manipulating_unfamiliar_paths>
**Before manipulating a wiki path you have not recently confirmed — rename,
move, Read of a new location, Write of a new file — list the parent
directory once.** A single `ls <parent>` or
`fd -e md . <parent> -d 1` is enough. This catches stale path
assumptions (a slug the model remembers from earlier that was already
renamed, a directory it expects to exist that does not, a `raw/<kind>/`
bucket that was retired) before they turn into `No such file or directory`,
`fatal: bad source`, or a Write that lands in the wrong place.
</list_before_manipulating_unfamiliar_paths>

</file_handling_discipline>

</operational_discipline>

<pitfalls>
Quick-scan reminders. See the named section for full guidance.

<resolve_before_writing>
**Resolve before writing** — `discover_wiki.sh` exit 2 means ambiguous, not "use the upstream". Always present candidates and ask the user, even when an `EXISTING:` parent wiki shows up in the list. Silent upstream adoption is a confidentiality and scoping mistake. *(see `<resolving_the_wiki_location>`)*
</resolve_before_writing>

<orient_first>
**Orient first** — read SCHEMA + index + recent log before any operation. *(see `<resuming_an_existing_wiki>`)*
</orient_first>

<raw_is_read_only>
**`raw/` is read-only** — corrections live in wiki pages, not in the source.
</raw_is_read_only>

<cross_references_are_layer_2>
**Cross-references are layer 2, not raw** — synthesis links between sources live on the wiki page that cites both, never inside a raw body. *(see `<capture_raw_source>` in `<ingest>`)*
</cross_references_are_layer_2>

<update_navigation_reminder>
**Update navigation** — `index.md` and `log.md` lag → wiki degrades. *(see `<update_navigation>` in `<ingest>`)*
</update_navigation_reminder>

<log_only_what_changed>
**Log only what changed** — log entries list files actually created or updated; never narrate inspected-but-unchanged files or "did not edit" decisions. *(see `<update_navigation>` in `<ingest>`)*
</log_only_what_changed>

<page_thresholds>
**Page thresholds** — passing mentions don't earn a page. *(`template_schema.md`)*
</page_thresholds>

<cross_link_or_vanish>
**Cross-link or vanish** — every page links to ≥2 others.
</cross_link_or_vanish>

<frontmatter_is_required>
**Frontmatter is required** — enables search, filtering, staleness detection.
</frontmatter_is_required>

<tags_from_taxonomy_only>
**Tags from taxonomy only** — add new tags to SCHEMA first.
</tags_from_taxonomy_only>

<pages_stay_scannable>
**Pages stay scannable** — split at >200 lines; deep dives go to dedicated pages.
</pages_stay_scannable>

<generalize_procedure_pages>
**Generalize procedure pages** — name the rule, strip the instance, hoist worked content to `raw/` sidecars or concept pages. The page reads as a rule on a different task next month, or it isn't a procedure. *(see `<capture_procedure>`)*
</generalize_procedure_pages>

<procedure_or_concept>
**Procedure or concept?** — file pages an operator reads as steps to follow under `procedures/`; file pages a reader reads as facts about how something works under `concepts/`. Wording the body as "rules govern X" does not turn a description into a procedure. *(see `<page_types>` and `<capture_procedure>`)*
</procedure_or_concept>

<confirm_scope>
**Confirm scope** — ingests touching 10+ existing pages need user OK first.
</confirm_scope>

<rotate_log_at_500>
**Rotate the log at 500 entries** — `log.md` → `log-YYYY.md`.
</rotate_log_at_500>

<contradictions_are_explicit>
**Contradictions are explicit** — record both with dates, mark in frontmatter, flag for review.
</contradictions_are_explicit>

</pitfalls>

</wiki>
