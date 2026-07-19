---
name: wiki_import
description: Import a single external resource (URL, file, paper, PDF, transcript, meeting note, internal note, paste) into the wiki with a user-reviewable triage step before any wiki page is written. Use when the user points at such a resource and asks to ingest, import, integrate, digest, absorb, review-before-adding, or propose-then-add it into their wiki; when they want a triage step on a single source rather than a straight ingest; or whenever a named source should be brought in with a propose-then-act front end.
version: 1.2.2
author: Andreas F. Hoffmann
license: MIT
---

# wiki_import

<wiki_import>
  <role>Resource-to-wiki reconciliation editor. Capture the resource the user pointed to as raw source, mine the captured raw for durable knowledge, diff against the wiki, and triage the result before any wiki-page write.</role>
  <orient_first_top>**Read `$WIKI/SCHEMA.md` once at the start of any session that activates this skill.** The schema declares the domain, page-type enum, tag taxonomy, and conventions every classification and write must honor. The full orientation pass (SCHEMA + index + last ~350 lines of log) is covered by `<orient_first>` in `<policy>` below; this top-line note exists so the SCHEMA read is never skipped on a "quick" import.</orient_first_top>
  <objective>Pull a single named external resource into the wiki end to end: persist the raw, classify each candidate by page type and relation to existing content, surface conflicts between the resource and existing wiki pages, and propose reconciliations the user can accept page by page. Defer all wiki structure, discovery, orientation, raw capture, ingest, and lint behavior to the `wiki` skill.</objective>
  <policy>
    <resolve_first>Resolve `$WIKI` through the `wiki` skill's discovery flow before reading the resource. Honor exit-2 ambiguity by presenting candidates and asking the user.</resolve_first>
    <orient_first>Read `SCHEMA.md`, `index.md`, and roughly the last 350 lines of `log.md` before diffing, so the diff runs against an understood corpus and domain.</orient_first>
    <confirm_resource>Confirm the resource pointer (URL, file path, paste, PDF, transcript, meeting note, internal note) and its kind with the user before fetching. For a URL to an externally-published article, confirm the target slug under `raw/articles/`; for a PDF or paper, under `raw/papers/`; for a meeting note, interview, or spoken-word transcript, under `raw/meetings/`; for an internal memo, discussion writeup, ad-hoc observation, or internal doc not published externally, under `raw/notes/`; for a paste, the appropriate `raw/` subdirectory by kind. For edge cases (article that embeds a transcript, transcript of a private meeting, paste of unknown provenance, file that fits two buckets equally), consult `$WIKI_SKILL/references/raw_taxonomy.md` — the canonical reference for bucket meanings and classification heuristics.</confirm_resource>
    <capture_raw>Route the resource through the `wiki` skill's Ingest §1 — fetch and convert (URL), extract (PDF), or file (paste, meeting, note) — into `raw/<kind>/<slug>.md` with the required frontmatter (`ingested`, body-only `sha256`, plus `source_url` for an externally-published source or a relative in-repo `source_path`; a local file outside the repo takes no path — excerpt it into the body and note its locality). Write the sha256 with `python3 $WIKI_SKILL/scripts/compute_sha256.py raw/<kind>/<slug>.md` — never invent the value by hand. On re-ingest of the same source: rerun the same command, skip if it reports `ok`, flag drift if it reports `update`.</capture_raw>
    <mine_resource>Read the captured raw end to end. Extract durable claims, decisions, definitions, conventions, comparisons, workflows, and named entities. Skip passing mentions, minor details, and material outside the wiki's stated domain in `SCHEMA.md`.</mine_resource>
    <classify>For each candidate, pick a page type from the `wiki` skill's enum and tag it NEW, EXTEND, CONFIRM, or CONFLICT against `$WIKI`. Honor the page-threshold rules from the `wiki` skill — a passing mention does not earn a page.</classify>
    <surface_contradictions>For every CONFLICT, capture both excerpts verbatim, name the disagreement dimension (factual / definitional / scope / recency / source-quality), and offer two or three concrete reconciliation paths.</surface_contradictions>
    <propose_then_act>Emit the proposal and wait for user selections before any wiki-page write. The raw capture in step 4 stays — only the entity, concept, comparison, summary, query, and procedure writes wait.</propose_then_act>
    <defer_writes>Route approved NEW and EXTEND items through the `wiki` skill's Ingest flow (steps 3–6). Route approved CONFLICT items through its contested-page protocol (`contested: true`, `contradictions:` frontmatter, both positions recorded with dates and sources).</defer_writes>
    <single_resource>Source material for the proposal is the captured raw only. Skip claims the resource did not establish, even when they are true in the broader domain.</single_resource>
    <too_large_to_read_in_one_shot>When `Read` fails with `File content (N tokens) exceeds maximum allowed tokens (25000)`, do not retry the same call — the same call fails the same way. Switch strategy: run `Bash wc -l <path>` to size the file, then `Read` with `offset` and `limit` to walk it in chunks, or run `Bash grep -n <pattern> <path>` to find the section you need and `Read` only that range. This applies in particular to Confluence-page tool-result tempfiles under `.../tool-results/mcp-claude_ai_Atlassian-getConfluencePage-*.txt` and to long transcripts or dense papers — sources that routinely exceed the 25k-token Read limit. The failure mode to avoid is the 3–5× same-call retry loop the model defaults to on this error.</too_large_to_read_in_one_shot>
    <list_before_unfamiliar_path>Before writing into a `raw/<kind>/` bucket you have not recently confirmed on disk, list the parent directory once (`ls "$WIKI/raw/<kind>/"`). This catches a retired or renamed bucket before the Write lands in the wrong place.</list_before_unfamiliar_path>
  </policy>
  <steps>
    <step>Confirm the resource pointer and its kind. If the user supplied only "this link" or "that paper", request the URL or path explicitly before continuing.</step>
    <step>Run `discover_wiki.sh` and resolve `$WIKI`. On exit 2, present candidates in walk order and stop until the user picks.</step>
    <step>Read `SCHEMA.md`, `index.md`, and roughly the last 350 lines of `log.md`.</step>
    <step>Capture the resource into `raw/<kind>/<slug>.md` per the `wiki` skill's Ingest §1 (frontmatter, body-only sha256 via `python3 $WIKI_SKILL/scripts/compute_sha256.py`, drift check on re-ingest).</step>
    <step>Read the captured raw end to end. Build a list of durable items, each with title, suggested page type, target slug, and an excerpt anchor into the captured raw.</step>
    <step>Search `$WIKI` for each item (index plus recursive grep for 100+-page wikis). Tag NEW, EXTEND, CONFIRM, or CONFLICT. For CONFLICT items, capture both excerpts verbatim.</step>
    <step>Emit one report under three H2 headings: `## New pages`, `## Extensions to existing pages`, `## Contradictions to reconcile`. Skip CONFIRM entries unless the user asked for a full inventory.</step>
    <step>On approval, route each item through the `wiki` skill's matching flow, run `python3 scripts/lint.py`, and append a single `## [YYYY-MM-DD] import | Source Title — N new, N extended, N contested` entry to `log.md` listing only files actually created or updated.</step>
  </steps>
  <output_contract>
    <proposal_format>Three H2 sections. Each entry: title, suggested type, target path, excerpt anchor into the captured raw. Contradictions also carry wiki excerpt, raw excerpt, disagreement dimension, and ≥2 reconciliation options.</proposal_format>
    <no_wiki_page_writes_before_approval>Skip every entity, concept, comparison, summary, query, and procedure write during the proposal phase. The raw capture is the only write that lands before approval.</no_wiki_page_writes_before_approval>
    <log_entry>One dated import entry that lists only files actually created or updated (raw plus wiki pages). Skip files inspected, considered, or deliberately left unchanged.</log_entry>
    <validation>Every candidate carries type and target; every CONFLICT carries both excerpts and ≥2 reconciliation options; no wiki page is modified before approval; the log entry matches actual file changes.</validation>
  </output_contract>
</wiki_import>
