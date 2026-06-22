# knowledge_management

A plugin for building, maintaining, and distilling a knowledge base of interlinked plain-Markdown files. It persists and compounds as you use it.

## Skills

The wiki itself, plus paired front ends that wrap two of its workflows behind single named entry points:

- **wiki**: the foundation. Build and maintain an interlinked Markdown wiki: ingest sources (URLs, articles, papers, PDFs, transcripts, meeting notes, internal notes, pastes), then query, lint, audit, archive, and reorganise. Page types are read from `SCHEMA.md`. Each claim is backed by an inline standard-Markdown link to its source; the page-level `sources:` frontmatter is the full inventory; an optional `## Derived from` section covers external material the wiki doesn't own; and a body-only `sha256` hash detects when a raw source has drifted. Discovery, init, lint, and the sha256 helper all ship as bundled scripts, so the agent runs fixed programs for the mechanical parts. Use it when the user asks to create, build, ingest into, query, or maintain a wiki, knowledge base, or research notes.
- **wiki_import** and **wiki_wrapup**: a triage-first ingest pair. `wiki_import` takes one named resource (URL, file, paper, PDF, transcript, meeting note, internal note, or paste); `wiki_wrapup` takes the current chat session. Both capture the source, compare each candidate against the existing wiki, and produce a triage report (new pages, extensions, and contradictions, each with excerpts and concrete options to reconcile them) before any page is written. Approved writes go back through the `wiki` skill, so the ingest logic stays in one place. Use them when the user asks to import a specific resource, or to wrap up, close, or harvest the current chat into the wiki.
- **wiki_fix**: a one-shot wrapper around the `auto_shaper_wiki` agent (see below). It runs the agent against the current repository's wiki to audit it end to end and fix every issue on its own: structure, content, splits, links, tags, and scaffold drift. Cross-page contradictions it does not auto-resolve; it surfaces them through the contested-page protocol. Use it when the user asks to fix, repair, lint, audit, or health-check their wiki without further interaction.

Two distillation skills that work on text outside the wiki:

- **executive_summary**: condense documents, reports, and written content into structured executive-summary prose at 10–15% of the original length, preserving logic and reasoning chains rather than collapsing them into bullet-point keywords.
- **spr**: convert text into a Sparse Priming Representation (SPR): a compact, Markdown-structured set of dense, non-overlapping priming statements built for passing knowledge from one LLM to another.

## Agents

- **auto_shaper_wiki**: the audit-and-fix engine that `wiki_fix` hands off to. It finds the current repository's wiki using the `wiki` skill's discovery logic, runs the linter, and fixes every issue on its own: frontmatter and schema violations, broken links, off-taxonomy tags, oversized or topic-mixing pages that need splitting, procedure pages that leak instance content, and content that breaks its page type's structure. Cross-page contradictions it surfaces through the contested-page protocol rather than auto-resolving. It works in two phases: assess (lint plus a semantic audit), then a fix loop, then re-lint until clean.

## Background

The `wiki` skill is based on Andrej Karpathy's LLM Wiki pattern: <https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f>.

Karpathy treats a persistent Markdown wiki, not the chat transcript, as the lasting knowledge artefact. The human picks the sources and directs the analysis; the LLM reads each source, pulls out the key claims, and files them into entity pages, concept summaries, and cross-links. Unlike RAG, which rebuilds its understanding from raw chunks on every query, the wiki compiles knowledge once and compounds over time. Karpathy browses the result in Obsidian and lets the model do the grunt work (summarizing, cross-referencing, filing, and bookkeeping), guided by a schema document.

This skill keeps the compile-once-and-compound idea but moves it to a tool-neutral, plain-Markdown stack. Every page is a `.md` file you can open in any editor or terminal, with no Obsidian or third-party reader required. It adds a procedural layer alongside the declarative one: `procedures/` pages capture *how* an operator should act (workflows, conventions, runbooks), alongside the *what* and *why* of entity, concept, comparison, summary, and query pages. A few mechanics make it run on its own:

- Discovery, init, lint, and the body-only sha256 helper ship as bundled scripts.
- The `auto_shaper_wiki` agent runs the assess → fix → verify loop on its own.
- Each claim links to its source inline, the page-level `sources:` frontmatter is the inventory, and a `sha256` hash detects drift in raw sources.
- The page types are read from `SCHEMA.md`, so a wiki can add a type without changing the linter.

## Why it compounds

Beyond compiling knowledge once, the wiki grows into a mirror of how you see the project (your sense of what matters and how the pieces fit), written in a form an agent can read. The leverage is in who writes it and how it converges.

Telling an agent what knowledge is important does not transfer your meaning. Each time you say it, the agent reinterprets it from scratch, so it misunderstands you a little differently every time. Writing it down changes that. The agent writes what it learns into the wiki in its own words, and you correct or refine a page when you notice it read wrong. Page by page, session by session, the two of you converge, until the agent attaches the same meaning to your knowledge that you do.

The result is a working copy of what you hold true about the project, written by the agent, but reflecting your intent. Every later task then starts from shared meaning instead of a fresh guess.
