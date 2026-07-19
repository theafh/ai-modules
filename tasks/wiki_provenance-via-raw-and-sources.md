---
description: Force wiki content derived from non-canonical raw artifacts (sessions, pastes, meetings) into a `raw/` sidecar + frontmatter `sources:`, not body-prose narration.
scope: plugins/knowledge_management
created: 2026-05-28T19:24:54
updated: 2026-07-04T14:43:36
status: open
reported-by: Andreas Hoffmann
---

# Route non-canonical provenance through `raw/` + `sources:`, not body prose

## Goal

Any wiki content derived from an artifact outside `wiki/` and outside canonical upstream documentation is saved as a `raw/<kind>/<slug>.md` sidecar carrying the raw-frontmatter origin contract, and referenced via `sources:` in the consuming page's frontmatter. Body prose stops narrating "this came from X" — readers route through `sources:`, and per-claim attribution uses inline links to the same raw sidecar where finer granularity matters.

## Context

This is one of a family of **generalisable refinements** to the wiki skills + `auto_shaper_wiki` agent. The trigger was a concrete friction point surfaced while auditing a real wiki, but the rule is stated globally so it applies to every user of the wiki skills, not just the originating case. During that audit a page derived content from a chat-session transcript, and the auto-shaper narrated the provenance in body prose ("during an authoring session, the user enforced…") instead of writing a sidecar and pointing at it from `sources:`.

Much of the write-side convention has since shipped; this task adds the missing capture trigger and prohibition on top of it rather than restating what exists:

- The ingest workflow in [skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) already routes explicitly provided sources into `raw/` by kind — pasted text included — and defers edge cases to `references/raw_taxonomy.md` as the canonical classification reference.
- The SCHEMA template's **Provenance** convention states that attribution belongs next to the claim and `sources:` is the canonical inventory; the agent enforces it through the `provenance_violation` finding and the `<fix_provenance_violation>` move.
- The SCHEMA template's `## Derived from` section is the unstructured channel for durable external material the wiki points at but does not own or classify (a doctrine file in another repo, a codebase, a notebook). The agent's `<fix_external_source_pointer>` move migrates external pointers there and explicitly declines to capture external files into `raw/` during an audit pass, deferring capture to `wiki_import`'s triage-first protocol.

The remaining gap, and this task's subject: an ad-hoc artifact arriving **mid-conversation** — a paste, a chat-session transcript, a meeting note, screenshot OCR, a voice memo, internal scratch — informs a page without any capture rule firing, and no prose forbids narrating that provenance in the page body. Channel boundary, decided: an artifact whose content informs a page and that the wiki must be able to re-read (ephemeral or machine-local material) is captured into `raw/<kind>/<slug>.md`; durable external material not itself being classified stays a `## Derived from` pointer.

A second subtle failure: when extracting raw text containing markdown-sensitive characters (HTML-like tags, backticks, headings), authors and the agent currently default to blockquotes. Blockquotes break on inline HTML and trip `markdownlint MD033 no-inline-html` and similar false positives. Fenced text blocks with a dynamically sized fence avoid that *and* are **semantically more honest for verbatim content** — a fenced block declares "this is raw text, not markdown to render", which is exactly what a `raw/` excerpt is. Pick the smallest fence count (>=3 backticks) longer than any backtick run already inside the content.

Files involved:

- [plugins/knowledge_management/skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) — authoring contract and ingest workflow.
- [plugins/knowledge_management/skills/wiki_import/SKILL.md](../plugins/knowledge_management/skills/wiki_import/SKILL.md) — the ad-hoc / implicit-import path.
- [plugins/knowledge_management/agents/auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md) — `<remediate>` section.
- [plugins/knowledge_management/skills/wiki/references/template_schema.md](../plugins/knowledge_management/skills/wiki/references/template_schema.md) — the **Provenance** convention block.

Related task: [wiki_raw-kind-rubric-and-out-of-repo-paths.md](archive/wiki_raw-kind-rubric-and-out-of-repo-paths.md) — introduces the documented `source_path:` field these sidecars use for machine-local origins; implement it first or together with this one.

## Approach

1. **`plugins/knowledge_management/skills/wiki/SKILL.md`** — add an explicit "non-canonical raw artifact ingestion" rule: any session, paste, meeting note, transcript, screenshot OCR, voice memo, or internal scratch artifact that informs a wiki page
   - lands in `raw/<kind>/<slug>.md`, classified per `references/raw_taxonomy.md`, with the SCHEMA template's raw-frontmatter contract (`source_url:` for published origins, `source_path:` for local ones, `ingested:`, body `sha256:` via `compute_sha256.py`);
   - is referenced from the consuming page's frontmatter via `sources:`;
   - carries enough excerpted content in the sidecar body to be useful without the original file;
   - is never narrated in the consuming page's body prose.

   State the `## Derived from` boundary from Context beside the rule so the two channels never compete.
2. **`plugins/knowledge_management/skills/wiki_import/SKILL.md`** — broaden the trigger guidance to the implicit case: a wiki edit that *uses* a non-canonical artifact mid-conversation routes through the same capture, not only explicit import invocations.
3. **`plugins/knowledge_management/agents/auto_shaper_wiki.md` `<remediate>` section** — add a guard consistent with the `<fix_external_source_pointer>` posture: when a fix would otherwise add provenance prose to a body, halt; re-point attribution at the sidecar when the source is already captured, and surface an uncaptured artifact for `wiki_import` routing in the report instead of creating sidecars mid-audit. The per-file change report names the routing either way.
4. **`template_schema.md`** — extend the **Provenance** convention with the capture rule and the `## Derived from` boundary so every wiki's `SCHEMA.md` carries it and the agent reads it at `<read_schema>`.
5. **All four locations above** — when extracting raw text that may contain markdown-sensitive characters, default to **fenced text blocks with a dynamically sized fence** (not blockquotes). Document the rule: pick the smallest backtick fence count (>=3) longer than any backtick run already inside the content.

## Acceptance

- The four files above carry the capture rule, the narration prohibition, and the `## Derived from` boundary; the **Provenance** convention in `template_schema.md` states them for downstream wikis.
- Fixture wiki edit that ingests a paste mid-conversation:
  - The source lives in `raw/<kind>/<slug>.md` with the raw-frontmatter contract (origin field, `ingested:`, `sha256:`).
  - The consuming page's frontmatter has `sources:` referencing it.
  - No body paragraph narrates provenance.
  - Any HTML-like tokens in the raw text do not trip `markdownlint MD033`.
- Auto-shaper fixture: a page narrating an uncaptured mid-conversation source → the remediation pass adds no provenance prose and surfaces the artifact for `wiki_import` routing in the per-file report.
- `tests/wiki/run_all.sh --layer2` passes.
