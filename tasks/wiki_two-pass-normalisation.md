---
description: Make the wiki_auto_shaper agent route displaced semantics to their proper channel before normalising structure, and surface both halves in the audit report.
scope: plugins/knowledge_management
created: 2026-05-28T19:25:24
updated: 2026-06-02T20:57:24
status: open
---

# Two-pass remediation: route displaced semantics before normalising structure

## Goal

When the `wiki_auto_shaper` agent normalises a structural element (heading vocabulary, page anatomy, frontmatter field, label) and the existing content carries semantics that don't fit the target structure, the agent must route the displaced semantics to their proper channel **before** applying the structural fix. Calling this "two-pass remediation" makes it citable in the audit report. The audit report must surface both halves of the fix, not silently swallow the routing step.

## Context

This is one of a family of **generalisable refinements** to the wiki skills + `wiki_auto_shaper` agent. The trigger was a concrete friction point during the 2026-05-26 audit of `wiki/todos/bet-assistant-updates.md` in the `ai-assets` repo, but the rule is stated globally so it applies to every user of the wiki skills, not just the originating case.

During that audit the agent normalised eight labels from "What the session showed" to "What the canon says" (a vocabulary fix), and then **jammed the displaced session date into the heading** as a parenthetical qualifier — producing the same overcompressed labels documented in [wiki_metadata-in-headings.md](wiki_metadata-in-headings.md).

The correct path: route the date+session metadata to `sources:` (creating a `raw/` sidecar if needed) **first**, then normalise the label with no leftover semantic baggage.

Skipping the routing step also produces:

- **Overcompressed labels** — vocabulary terms forced to carry extra semantics they were never meant to (the "What the canon says (2026-05-22 ...)" case above).
- **Headings with parenthetical attribution** — the structural element broken to hold metadata.
- **Frontmatter fields with embedded prose** — e.g., `scope: project xyz (Q3 only)`.
- **Section titles with embedded scope or mandate-level tags** — another shape of the same failure when scope/mandate metadata gets jammed into a title rather than routed to frontmatter.

Files involved:

- [plugins/knowledge_management/agents/wiki_auto_shaper.md](../plugins/knowledge_management/agents/wiki_auto_shaper.md) — `<remediate>` section and the audit report contract.

Related tasks:

- [wiki_metadata-in-headings.md](wiki_metadata-in-headings.md) — the heading-specific surface of the same failure.
- [wiki_provenance-via-raw-and-sources.md](wiki_provenance-via-raw-and-sources.md) — the routing destination when displaced semantics name a source.

## Approach

1. **`plugins/knowledge_management/agents/wiki_auto_shaper.md` `<remediate>` section** — add an explicit three-step rule named "two-pass remediation":
   1. **Identify displaced semantics.** Before changing the structure, name what semantic content the existing structure carries that won't fit the target. Examples: date/source in a heading, qualifier in a frontmatter key, scope tag in a section title, mandate level in a page name.
   2. **Route displaced semantics first.** Move the content to its proper structured channel — frontmatter, `sources:`, `raw/`, inline link, `log.md` — before applying the structural fix.
   3. **Then normalise.** Apply the structural fix with no leftover semantic baggage.
2. **Same file, audit-report contract** — when the agent performs a normalisation, the per-file change list must name both halves: the structural fix *and* any displaced-semantics routing it performed. Example phrasing: "label normalised + date/source routed to `sources:`". A normalisation with displaced semantics that were not routed must surface in the report rather than being silently completed.
3. Reference the new rule by name ("two-pass remediation") from any other section of the agent that triggers normalisation (label vocabulary, page anatomy, frontmatter shape).

## Acceptance

- The `<remediate>` section carries the named three-step rule.
- The audit-report contract requires naming both halves of every normalisation.
- Fixture with non-vocabulary labels and embedded attribution suffixes → after `wiki_fix`:
  - Labels match SCHEMA vocabulary, no parenthetical attribution remains.
  - Displaced metadata appears in `sources:` or `raw/`.
  - The audit report names both halves of the fix per file.
- `make lint` clean.
- `tests/wiki/run_all.sh --layer2` passes.
