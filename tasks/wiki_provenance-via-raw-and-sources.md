---
description: Make `wiki_import` capture implicit mid-conversation sources into a `raw/` sidecar + `sources:` instead of body-prose narration, and have `wiki_fix` route uncaptured ones to `wiki_import`.
scope: plugins/knowledge_management
created: 2026-05-28T19:24:54
updated: 2026-09-05T21:26:04
status: open
reported-by: Andreas Hoffmann
---

# Capture mid-conversation sources through `wiki_import`, not page-body narration

## Goal

An ad-hoc source that informs a wiki page mid-conversation, whether a paste, a chat-session transcript, a meeting note, screenshot OCR, a voice memo, or internal scratch, is captured through the `wiki_import` path into a `raw/<kind>/<slug>.md` sidecar carrying the raw-frontmatter origin contract, and referenced via `sources:` in the consuming page's frontmatter. The wiki authoring contract forbids narrating that provenance in body prose: readers route through `sources:`, and per-claim attribution uses inline links to the same sidecar. `wiki_import` fires on this implicit mid-conversation case, not only on an explicit "import this" invocation; and when `wiki_fix`'s auto-shaper finds a page that narrated an uncaptured source, it surfaces that source for `wiki_import` to capture rather than importing it itself.

## Context

This is one of a family of **generalisable refinements** to the wiki skills + `auto_shaper_wiki` agent. The trigger was a concrete friction point surfaced while auditing a real wiki, but the rule is stated globally so it applies to every user of the wiki skills, not just the originating case. During that audit a page derived content from a chat-session transcript, and the auto-shaper narrated the provenance in body prose ("during an authoring session, the user enforced…") instead of writing a sidecar and pointing at it from `sources:`.

Much of the write-side convention has since shipped; this task adds the missing capture trigger and prohibition on top of it rather than restating what exists:

- The ingest workflow in [skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) already routes explicitly provided sources into `raw/` by kind, pasted text included, and defers edge cases to `references/raw_taxonomy.md` as the canonical classification reference.
- The SCHEMA template's **Provenance** convention states that attribution belongs next to the claim and `sources:` is the canonical inventory; the agent enforces it through the `provenance_violation` finding and the `<fix_provenance_violation>` move.
- The SCHEMA template's `## Derived from` section is the unstructured channel for durable external material the wiki points at but does not own or classify (a doctrine file in another repo, a codebase, a notebook). The agent's `<fix_external_source_pointer>` move migrates external pointers there and explicitly declines to capture external files into `raw/` during an audit pass, deferring capture to `wiki_import`'s triage-first protocol.

The remaining gap, and this task's subject: an ad-hoc artifact arriving **mid-conversation**, whether a paste, a chat-session transcript, a meeting note, screenshot OCR, a voice memo, or internal scratch, informs a page without any capture rule firing, and no prose forbids narrating that provenance in the page body. Channel boundary, decided: an artifact whose content informs a page and that the wiki must be able to re-read (ephemeral or machine-local material) is captured into `raw/<kind>/<slug>.md`; durable external material not itself being classified stays a `## Derived from` pointer.

The decided split on which skill owns the fix:

- **`wiki_import`** is the capture front end. Today its trigger fires only when the user points at a named resource; broaden it to also fire on the implicit mid-conversation case, so a paste that informs a page routes through the same triage-first capture (`raw/` sidecar + `sources:`) instead of being narrated. This task's primary edit target.
- **`wiki_wrapup`** already mines the active session at session-end and routes session-derived material through the base `wiki` skill's Ingest flow (`raw/` + `sources:`), so the session-end case is largely covered; it inherits the new no-narration rule automatically because it defers authoring behaviour to the base skill.
- **`wiki_fix` / `auto_shaper_wiki`** audits and repairs an existing wiki and **does not import mid-audit by design**. It defers capture to `wiki_import`'s triage-first protocol. Its role for an uncaptured source is *detect and route*: when a page body narrates a source with no sidecar, re-point attribution to the sidecar if one exists, otherwise surface the uncaptured artifact for `wiki_import` routing in the per-file report; it never creates the sidecar itself. This corrects the intuition that `wiki_fix` should perform the import.

A second subtle failure: when extracting raw text containing markdown-sensitive characters (HTML-like tags, backticks, headings), authors and the agent currently default to blockquotes. Blockquotes break on inline HTML and trip `markdownlint MD033 no-inline-html` and similar false positives. Fenced text blocks with a dynamically sized fence avoid that *and* are **semantically more honest for verbatim content**: a fenced block declares "this is raw text, not markdown to render", which is exactly what a `raw/` excerpt is. Pick the smallest fence count (>=3 backticks) longer than any backtick run already inside the content.

Files involved:

- [plugins/knowledge_management/skills/wiki_import/SKILL.md](../plugins/knowledge_management/skills/wiki_import/SKILL.md): the capture trigger; broadened to the implicit mid-conversation case (primary edit).
- [plugins/knowledge_management/skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md): authoring contract and ingest workflow; carries the capture rule and narration prohibition that `wiki_import` and `wiki_wrapup` inherit.
- [plugins/knowledge_management/agents/auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md): `<remediate>` section; the detect-and-route guard.
- [plugins/knowledge_management/skills/wiki/references/template_schema.md](../plugins/knowledge_management/skills/wiki/references/template_schema.md): the **Provenance** convention block.

Related task: [wiki_raw-kind-rubric-and-out-of-repo-paths.md](archive/wiki_raw-kind-rubric-and-out-of-repo-paths.md) (finished): introduced the documented `source_path:` field these sidecars use for in-repo machine-local origins; the convention is shipped (the `### raw/ Frontmatter` contract and the `raw-source-path` lint check carry it), so this task builds directly on it.

## Approach

1. **`plugins/knowledge_management/skills/wiki_import/SKILL.md`**: broaden the capture trigger to the implicit case. Today the `<capture_raw>` policy and the skill's `description` fire only when the user points at a named resource; extend them so a wiki edit that *uses* a non-canonical artifact mid-conversation (a paste, transcript, meeting note, screenshot OCR, voice memo, or internal scratch) routes through the same triage-first capture (`raw/<kind>/<slug>.md` sidecar + `sources:`), not only on an explicit import invocation. This is the task's primary edit.
2. **`plugins/knowledge_management/skills/wiki/SKILL.md`**: add the "non-canonical raw artifact ingestion" rule to the authoring contract, which `wiki_import` and `wiki_wrapup` both inherit. Any session, paste, meeting note, transcript, screenshot OCR, voice memo, or internal scratch artifact that informs a wiki page
   - lands in `raw/<kind>/<slug>.md`, classified per `references/raw_taxonomy.md`, with the SCHEMA template's raw-frontmatter contract (`source_url:` for published origins, `source_path:` for local ones, `ingested:`, body `sha256:` via `compute_sha256.py`);
   - is referenced from the consuming page's frontmatter via `sources:`;
   - carries enough excerpted content in the sidecar body to be useful without the original file;
   - is never narrated in the consuming page's body prose.

   State the `## Derived from` boundary from Context beside the rule so the two channels never compete.
3. **`plugins/knowledge_management/agents/auto_shaper_wiki.md` `<remediate>` section**: add a detect-and-route guard consistent with the `<fix_external_source_pointer>` posture, honoring the agent's standing rule that it never captures sources mid-audit. When a fix would otherwise add provenance prose to a body, halt; re-point attribution at the sidecar when the source is already captured, and surface an uncaptured artifact for `wiki_import` routing in the report instead of creating a sidecar itself. The per-file change report names the routing either way.
4. **`template_schema.md`**: extend the **Provenance** convention with the capture rule and the `## Derived from` boundary so every wiki's `SCHEMA.md` carries it and the agent reads it at `<read_schema>`.
5. **All four locations above**: when extracting raw text that may contain markdown-sensitive characters, default to **fenced text blocks with a dynamically sized fence** (not blockquotes). Document the rule: pick the smallest backtick fence count (>=3) longer than any backtick run already inside the content.

## Acceptance

- `wiki_import` fires on the implicit mid-conversation case: its trigger guidance and `description` cover a source used to inform a page mid-conversation, not only an explicit "import this" invocation.
- The four files above carry the capture rule, the narration prohibition, and the `## Derived from` boundary; the **Provenance** convention in `template_schema.md` states them for downstream wikis.
- Fixture wiki edit that ingests a paste mid-conversation:
  - The source lives in `raw/<kind>/<slug>.md` with the raw-frontmatter contract (origin field, `ingested:`, `sha256:`).
  - The consuming page's frontmatter has `sources:` referencing it.
  - No body paragraph narrates provenance.
  - Any HTML-like tokens in the raw text do not trip `markdownlint MD033`.
- Auto-shaper fixture: a page narrating an uncaptured mid-conversation source → the remediation pass adds no provenance prose, creates no sidecar itself, and surfaces the artifact for `wiki_import` routing in the per-file report.
- `tests/wiki/run_all.sh --layer2` passes.
