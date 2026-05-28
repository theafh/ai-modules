---
description: Stop the wiki_auto_shaper agent (and wiki authoring contract) from inserting page-convention prose and lint-sanction prose into wiki page bodies.
scope: plugins/knowledge_management
created: 2026-05-28T19:24:26
updated: 2026-05-28T20:07:08
status: open
---

# Forbid meta-prose in wiki page bodies

## Goal

Wiki page bodies carry only load-bearing knowledge — the entries, facts, and content the page is about. Page conventions belong in `wiki/SCHEMA.md`; lint sanctions belong in `wiki/log.md` (audit entries) or `SCHEMA.md`. After this task lands, the auto-shaper and the wiki authoring contract refuse to insert page-summary paragraphs that redefine page conventions, lint-sanction prose, or restatements of `SCHEMA.md` policies into ordinary page bodies.

## Context

This is one of a family of **generalisable refinements** to the wiki skills + `wiki_auto_shaper` agent. The trigger was a concrete friction point during the 2026-05-26 audit of `wiki/todos/bet-assistant-updates.md` in the `ai-assets` repo, but the rule is stated globally so it applies to every user of the wiki skills, not just the originating case.

During that remediation the `wiki_auto_shaper` agent inserted two unwanted paragraphs that had to be stripped by hand:

- A page-summary paragraph defining "canon" ("Canon for an entry is…", "Each entry records…").
- A "Page size note" sanction paragraph explaining that the backlog naturally grows past the 200-line lint threshold.

The behaviour is currently licensed by the line at [wiki_auto_shaper.md:944-946](../plugins/knowledge_management/agents/wiki_auto_shaper.md) — "note the rationale on the page's body **or** in `SCHEMA.md`" — the "or page body" path gets picked because it sits closest to the lint finding. Nothing elsewhere in the agent or in [skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) forbids inserting page-convention prose during remediation.

Carve-out: `SCHEMA.md`, `index.md`, and synthesis pages (`type: synthesis`) may carry organising prose, because that *is* their load-bearing content.

Cross-references:

- `ai-assets` memory `feedback_no_meta_in_wiki_body.md`.
- `ai-assets` repo `wiki/todos/bet-assistant-updates.md` before/after diff.
- `ai-assets` repo `wiki/log.md` 2026-05-26 audit entry.

Related tasks: [wiki_page-type-growth-and-anatomy.md](wiki_page-type-growth-and-anatomy.md) (the lint-sanction-routing edit overlaps with edit #4 here).

## Approach

1. **`plugins/knowledge_management/agents/wiki_auto_shaper.md`** — at the line currently containing "note the rationale on the page's body or in `SCHEMA.md`" (around line 944-946 at the time of writing; locate by phrase, not by line number), drop "on the page's body or". Sanctioned-finding rationale routes to `SCHEMA.md` or `log.md` only.
2. **Same file, `<remediate>` section** — add an explicit prohibition: when rewriting a page body, do not insert page-convention definitions, entry-anatomy explanations, canon-kind clauses, or lint-sanction prose. Lead with one short sentence naming what the page is for; stop there. Carve out `type: schema | index | synthesis` pages.
3. **`plugins/knowledge_management/skills/wiki/SKILL.md`** — mirror the same prohibition in the authoring contract so authors invoking the skill directly inherit the rule.
4. **Target-wiki `SCHEMA.md` template** (search the wiki skill bundle for the SCHEMA template the agent writes when bootstrapping a wiki; likely under `plugins/knowledge_management/skills/wiki/`) — add the normative clause so each ingested wiki's `SCHEMA.md` carries the rule that the agent reads at `<read_schema>`.
5. **`plugins/knowledge_management/skills/wiki/scripts/lint.py`** — add an info-level heuristic flagging:
   - Lead paragraphs longer than two sentences on non-`type: schema|index|synthesis` pages.
   - Phrases anywhere in the body matching: `Each entry records`, `Canon for an entry`, `Page size note`, `is sanctioned`, `is self-trimming`, `info-level finding`, `200-line lint threshold`, `graduate off`.

Bump the skill, agent, and plugin versions per the repo's one-bump-per-session rule at commit time, not while iterating.

## Acceptance

- The four prose-touching files above carry the new prohibition; the licensing "or page body" wording is gone.
- `lint.py` reports the new info-level findings on a fixture page containing any of the listed phrases.
- Fixture wiki containing an oversized todo page → after `wiki_fix`, no new meta-prose paragraph in the page body, sanction rationale only in the audit log.
- `tests/wiki/run_all.sh --layer2` passes with no regression.
- `make lint` clean on all edited files.
