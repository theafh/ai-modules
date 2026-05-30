---
description: Force wiki content derived from non-canonical raw artifacts (sessions, pastes, meetings) into a `raw/` sidecar + frontmatter `sources:`, not body-prose narration.
scope: plugins/knowledge_management
created: 2026-05-28T19:24:54
updated: 2026-05-31T01:27:00
status: open
---

# Route non-canonical provenance through `raw/` + `sources:`, not body prose

## Goal

Any wiki content derived from an artifact outside `wiki/` and outside canonical upstream documentation must be saved as a `raw/<kind>/<slug>.md` sidecar (with `source_path:` or `source_url:` and `ingested:` date in its frontmatter) and referenced via `sources:` in the consuming page's frontmatter. Body prose stops narrating "this came from X" — readers route through `sources:`. Per-claim attribution uses inline links to the same raw sidecar where finer granularity matters.

## Context

This is one of a family of **generalisable refinements** to the wiki skills + `wiki_auto_shaper` agent. The trigger was a concrete friction point during the 2026-05-26 audit of `wiki/todos/bet-assistant-updates.md` in the `ai-assets` repo, but the rule is stated globally so it applies to every user of the wiki skills, not just the originating case.

During that audit the wiki page derived content from a chat-session transcript (a non-canonical raw artifact); the auto-shaper narrated the provenance in body prose ("during a 2026-05-22 authoring session, the user enforced…") instead of writing a `raw/<kind>/<slug>.md` sidecar and pointing at it from `sources:`.

The convention already exists for in-repo mirrors (e.g., `raw/notes/repo-claude-md.md`) but is **not consistently applied** to ad-hoc raw artifacts that arrive mid-conversation: pastes, chat session transcripts, meeting notes, screenshot OCR, voice memos, internal scratch.

A second subtle failure: when extracting raw text containing markdown-sensitive characters (HTML-like tags, backticks, headings), authors and the agent currently default to blockquotes. Blockquotes break on inline HTML and trip `markdownlint MD033 no-inline-html` and similar false positives. Fenced text blocks with a dynamically sized fence avoid that *and* are **semantically more honest for verbatim content** — a fenced block declares "this is raw text, not markdown to render", which is exactly what a `raw/` excerpt is. Pick the smallest fence count (>=3 backticks) longer than any backtick run already inside the content.

Files involved:

- [plugins/knowledge_management/skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) — authoring contract.
- [plugins/knowledge_management/skills/wiki_import/SKILL.md](../plugins/knowledge_management/skills/wiki_import/SKILL.md) — the ad-hoc / implicit-import path.
- [plugins/knowledge_management/agents/wiki_auto_shaper.md](../plugins/knowledge_management/agents/wiki_auto_shaper.md) — `<remediate>` section.
- Target-wiki `SCHEMA.md` template inside the wiki skill bundle.

Related tasks: [wiki_raw-kind-rubric-and-out-of-repo-paths.md](wiki_raw-kind-rubric-and-out-of-repo-paths.md) (the kind-picking rubric this task assumes).

## Approach

1. **`plugins/knowledge_management/skills/wiki/SKILL.md`** — add an explicit "non-canonical raw artifact ingestion" rule. State that any session, paste, meeting note, transcript, screenshot OCR, voice memo, or internal scratch artifact that informs a wiki page must:
   - Land in `raw/<kind>/<slug>.md` with frontmatter carrying `source_path:` or `source_url:` and `ingested:` (ISO date).
   - Be referenced from the consuming page's frontmatter via `sources:`.
   - Carry enough excerpted content in the sidecar body to be useful without the original file.
   - Never be narrated in the consuming page's body prose.
2. **`plugins/knowledge_management/skills/wiki_import/SKILL.md`** — confirm it covers the ad-hoc case where a wiki edit *implicitly* uses a non-canonical artifact mid-conversation (not just explicit import calls). If it currently scopes itself to explicit invocation only, broaden the description and trigger guidance so the agent reaches for it when ingesting incidental artifacts mid-conversation.
3. **`plugins/knowledge_management/agents/wiki_auto_shaper.md` `<remediate>` section** — add a guard: when remediation would otherwise add provenance prose to a body, halt and instead create or extend the `raw/` sidecar and update `sources:`. The audit report must surface the routing.
4. **Target-wiki `SCHEMA.md` template** (the file the wiki skill writes when bootstrapping a wiki) — add the same rule so it lands in every ingested wiki's `SCHEMA.md` and the agent reads it at `<read_schema>`.
5. **All four locations above + wiki_import** — when extracting raw text that may contain markdown-sensitive characters, default to **fenced text blocks with a dynamically sized fence** (not blockquotes). Document the rule: pick the smallest backtick fence count (>=3) longer than any backtick run already inside the content.

## Acceptance

- The four files above carry the rule; the wiki SCHEMA template carries the same rule for downstream wikis.
- Fixture wiki edit that ingests a paste mid-conversation:
  - The source lives in `raw/<kind>/<slug>.md`.
  - The consuming page's frontmatter has `sources:` referencing it.
  - No body paragraph narrates provenance.
  - Any HTML-like tokens in the raw text do not trip `markdownlint MD033`.
- `make lint` clean.
- `tests/wiki/run_all.sh --layer2` passes.
