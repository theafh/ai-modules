# knowledge_management

A plugin for building, maintaining, and distilling a persistent, compounding knowledge base of interlinked plain markdown files.

## Skills

- **wiki**: build and maintain a personal/team wiki by ingesting sources (URLs, articles, papers, PDFs, transcripts, pastes), querying the wiki, linting and auditing, archiving, and reorganising. Use when the user asks to create, build, ingest into, query, or maintain their wiki, knowledge base, or research notes.
- **executive_summary**: distill documents, reports, and written content into structured executive-summary prose at 10–15% of the original length, preserving logic and reasoning.
- **spr**: convert input text into a Sparse Priming Representation (SPR), a compact, markdown-structured set of non-overlapping, informationally dense priming statements for LLM-to-LLM knowledge transfer.

## Agents

- **wiki_auto_shaper**: discover the wiki of the current repository using the `wiki` skill's discovery logic, run the linter, and autonomously fix every issue found — frontmatter and schema violations, broken links, off-taxonomy tags, oversized or topic-mixing pages that need splitting, procedure pages leaking instance content, and clear content violations of the page-type anatomy. Two-phase: assess (lint + semantic audit) → fix loop → re-lint until clean.

## Background

The `wiki` skill is based on Andrej Karpathy's LLM Wiki pattern: <https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f>.

Karpathy treats a persistent markdown wiki — not the chat transcript — as the durable knowledge artefact. The human curates sources and directs analysis; the LLM reads each source, extracts the salient claims, and files them into entity pages, concept summaries, and cross-links. Unlike RAG, which re-derives understanding from raw chunks on every query, the wiki compiles knowledge once and compounds over time. Karpathy browses the result in Obsidian and lets the model handle the grunt work — summarizing, cross-referencing, filing, and bookkeeping — against a schema document that governs the workflow.

This skill keeps the compile-once-and-compound thesis but ports it to a tool-neutral, plain-markdown stack — every page is a `.md` file readable in any editor or CLI, with no Obsidian or third-party reader required. It adds a procedural layer alongside the declarative one: `procedures/` pages capture *how* an operator should act (workflows, conventions, runbooks), complementing the *what* and *why* of entity, concept, comparison, summary, and query pages. Discovery, init, and lint ship as bundled scripts; the `wiki_auto_shaper` agent runs the assess → fix → verify loop autonomously; provenance is anchored by footnotes and `sha256` drift detection on raw sources; and the page-type enum is read from `SCHEMA.md`, so wikis extend the type set without touching the linter.
