---
name: wiki_wrapup
description: Wrap up the current chat session by mining it for durable knowledge, comparing the findings against the existing wiki, and surfacing both candidate additions and contradictions with concrete reconciliation suggestions. Use when the user asks to wrap up, close, or end a session; to capture, harvest, or persist what we discussed into the wiki; to ingest the session into the wiki; to reconcile the conversation with existing notes; or whenever a research or exploration chat is concluding and produced reusable knowledge worth keeping.
version: 1.1.0
author: Andreas F. Hoffmann
license: MIT
---

# wiki_wrapup

<wiki_wrapup>
  <role>Session-to-wiki reconciliation editor. Mine the active chat for durable knowledge, diff against the wiki, and triage the result before any write.</role>
  <orient_first_top>**Read `$WIKI/SCHEMA.md` once at the start of any session that activates this skill.** The schema declares the domain, page-type enum, tag taxonomy, and conventions every candidate must be classified against. The full orientation pass (SCHEMA + index + recent log) is covered by `<orient_first>` in `<policy>` below; this top-line note exists so the SCHEMA read is never skipped on a "quick" wrap-up.</orient_first_top>
  <objective>Identify what the session produced that does not yet live in the wiki, surface conflicts between session content and wiki content, and propose reconciliations the user can accept page by page. Defer all wiki structure, discovery, orientation, ingest, and lint behavior to the `wiki` skill.</objective>
  <policy>
    <resolve_first>Resolve `$WIKI` through the `wiki` skill's discovery flow before reading the session. Honor exit-2 ambiguity by presenting candidates and asking the user.</resolve_first>
    <orient_first>Read `SCHEMA.md`, `index.md`, and the last 20–30 entries of `log.md` before diffing, so the diff runs against an understood corpus.</orient_first>
    <mine_session>Extract durable claims, decisions, definitions, conventions, comparisons, workflows, and named entities. Skip abandoned hypotheses, transient back-and-forth, and user-private ephemera.</mine_session>
    <classify>For each candidate, pick a page type from the `wiki` skill's enum and tag it NEW, EXTEND, CONFIRM, or CONFLICT against `$WIKI`.</classify>
    <surface_contradictions>For every CONFLICT, capture both excerpts verbatim, name the disagreement dimension (factual / definitional / scope / recency / source-quality), and offer two or three concrete reconciliation paths.</surface_contradictions>
    <propose_then_act>Emit the proposal and wait for user selections before any write. Skip CONFIRM entries from the proposal unless the user asked for a full inventory.</propose_then_act>
    <defer_writes>Route approved NEW and EXTEND items through the `wiki` skill's Ingest flow. Route approved CONFLICT items through its contested-page protocol (`contested: true`, `contradictions:` frontmatter, both positions recorded with dates and sources).</defer_writes>
    <session_only>Source material is the visible session only. Skip claims the session did not establish.</session_only>
  </policy>
  <steps>
    <step>Run `discover_wiki.sh` and resolve `$WIKI`. On exit 2, present candidates in walk order and stop until the user picks.</step>
    <step>Read `SCHEMA.md`, `index.md`, and roughly the last 350 lines of `log.md`.</step>
    <step>Walk the session top to bottom. Build a list of durable items, each with title, suggested page type, target slug, and source-message reference.</step>
    <step>Search `$WIKI` for each item. Tag NEW, EXTEND, CONFIRM, or CONFLICT. For CONFLICT items, capture both excerpts.</step>
    <step>Emit one report under three H2 headings: `## New pages`, `## Extensions to existing pages`, `## Contradictions to reconcile`.</step>
    <step>On approval, route each item through the `wiki` skill's matching flow, run `python3 scripts/lint.py`, and append a single `## [YYYY-MM-DD] session-wrapup | N new, N extended, N contested` entry to `log.md` listing only files actually changed.</step>
  </steps>
  <output_contract>
    <proposal_format>Three H2 sections. Each entry: title, suggested type, target path, source-message reference. Contradictions also carry wiki excerpt, session excerpt, disagreement dimension, and ≥2 reconciliation options.</proposal_format>
    <no_writes_before_approval>Skip every wiki write during the proposal phase.</no_writes_before_approval>
    <log_entry>One dated session-wrapup entry that lists only files actually created or updated.</log_entry>
    <validation>Every candidate carries type and target; every CONFLICT carries both excerpts and ≥2 reconciliation options; no wiki file is modified before approval; the log entry matches actual file changes.</validation>
  </output_contract>
</wiki_wrapup>
