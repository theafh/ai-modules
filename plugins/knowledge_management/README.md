# knowledge_management

A plugin for building, maintaining, and distilling a persistent, compounding knowledge base of interlinked plain markdown files.

## Skills

- **wiki**: build and maintain a personal/team wiki by ingesting sources (URLs, articles, papers, PDFs, transcripts, pastes), querying the wiki, linting and auditing, archiving, and reorganising. Use when the user asks to create, build, ingest into, query, or maintain their wiki, knowledge base, or research notes.
- **executive_summary**: distill documents, reports, and written content into structured executive-summary prose at 10–15% of the original length, preserving logic and reasoning.
- **spr**: convert input text into a Sparse Priming Representation (SPR), a compact, markdown-structured set of non-overlapping, informationally dense priming statements for LLM-to-LLM knowledge transfer.

## Agents

- **wiki_audit**: discover the wiki of the current repository using the `wiki` skill's discovery logic, run the linter, and autonomously fix every issue found — frontmatter and schema violations, broken links, off-taxonomy tags, oversized or topic-mixing pages that need splitting, procedure pages leaking instance content, and clear content violations of the page-type anatomy. Two-phase: assess (lint + semantic audit) → fix loop → re-lint until clean.
