# knowledge_management

A plugin for building, maintaining, and distilling a persistent, compounding knowledge base of interlinked plain markdown files.

## Skills

The wiki itself plus paired front ends that wrap two of its workflows behind single named entry points:

- **wiki**: the foundation. Build and maintain an interlinked markdown wiki by ingesting sources (URLs, articles, papers, PDFs, transcripts, meeting notes, internal notes, pastes), querying the wiki, linting and auditing, archiving, and reorganising. Page types are read from `SCHEMA.md` and provenance is anchored by inline standard-markdown links next to each claim, backed by a page-level `sources:` frontmatter inventory and an optional `## Derived from` section for external material the wiki doesn't own, plus body-only `sha256` drift detection on raw sources; discovery, init, lint, and the sha256 helper all ship as bundled scripts so the agent runs deterministic programs for the mechanical parts. Use when the user asks to create, build, ingest into, query, or maintain their wiki, knowledge base, or research notes.
- **wiki_import** and **wiki_wrapup**: triage-first ingest pair. `wiki_import` takes one named resource (URL, file, paper, PDF, transcript, meeting note, internal note, or paste); `wiki_wrapup` takes the current chat session. Both capture the source, diff each candidate against the existing wiki, and emit a triage report (new pages, extensions, contradictions with both excerpts and concrete reconciliation options) before any wiki-page write lands. Approved writes route back through the `wiki` skill, so the ingest logic stays in one place. Use when the user asks to import a specific resource, or to wrap up / close / harvest the current chat into the wiki.
- **wiki_fix**: one-shot wrapper around the `wiki_auto_shaper` agent (see below). Invokes the agent against the wiki of the current repository so it audits end to end and autonomously fixes every issue — structure, content, splits, links, tags, scaffold drift, and cross-page contradictions (surfaced via the contested-page protocol, not auto-resolved). Use when the user asks to fix, repair, lint, audit, or health-check their wiki without further interaction.

Two distillation skills that operate on text outside the wiki:

- **executive_summary**: distill documents, reports, and written content into structured executive-summary prose at 10–15% of the original length, preserving logic and reasoning chains rather than collapsing them into bullet-point keywords.
- **spr**: convert input text into a Sparse Priming Representation (SPR), a compact, markdown-structured set of non-overlapping, informationally dense priming statements designed for LLM-to-LLM knowledge transfer.

## Agents

- **wiki_auto_shaper**: the audit-and-fix engine that `wiki_fix` hands off to. Discovers the wiki of the current repository using the `wiki` skill's discovery logic, runs the linter, and autonomously fixes every issue found — frontmatter and schema violations, broken links, off-taxonomy tags, oversized or topic-mixing pages that need splitting, procedure pages leaking instance content, clear content violations of the page-type anatomy, and cross-page contradictions (surfaced via the contested-page protocol rather than auto-resolved). Two-phase: assess (lint + semantic audit) → fix loop → re-lint until clean.

## Background

The `wiki` skill is based on Andrej Karpathy's LLM Wiki pattern: <https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f>.

Karpathy treats a persistent markdown wiki — not the chat transcript — as the durable knowledge artefact. The human curates sources and directs analysis; the LLM reads each source, extracts the salient claims, and files them into entity pages, concept summaries, and cross-links. Unlike RAG, which re-derives understanding from raw chunks on every query, the wiki compiles knowledge once and compounds over time. Karpathy browses the result in Obsidian and lets the model handle the grunt work — summarizing, cross-referencing, filing, and bookkeeping — against a schema document that governs the workflow.

This skill keeps the compile-once-and-compound thesis but ports it to a tool-neutral, plain-markdown stack — every page is a `.md` file readable in any editor or CLI, with no Obsidian or third-party reader required. It adds a procedural layer alongside the declarative one: `procedures/` pages capture *how* an operator should act (workflows, conventions, runbooks), complementing the *what* and *why* of entity, concept, comparison, summary, and query pages. Discovery, init, lint, and the body-only sha256 helper ship as bundled scripts; the `wiki_auto_shaper` agent runs the assess → fix → verify loop autonomously; provenance is anchored by inline standard-markdown links plus a page-level `sources:` inventory, with `sha256` drift detection on raw sources; and the page-type enum is read from `SCHEMA.md`, so wikis extend the type set without touching the linter.
