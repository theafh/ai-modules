---
description: Add a lint.py check that surfaces citation-consistency issues on synthesis pages. It flags sources: never cited inline, inline raw missing from sources:, and zero inline links.
scope: plugins/knowledge_management
created: 2026-06-18T00:36:41
updated: 2026-09-05T21:26:04
status: ready
reported-by: Andreas Hoffmann
---

# Add a synthesis-page citation-consistency lint check

## Goal

Give the wiki linter a deterministic check that surfaces when a synthesis page's two provenance channels disagree. For pages whose `type` is a synthesis type (`summary`, `query`, `comparison`), compare the page's `sources:` frontmatter inventory against the inline markdown links in its body that resolve under `raw/`, and surface:

- a `sources:` entry that no inline link references, declared-but-unpinned ("decorative") provenance;
- an inline `raw/` citation absent from `sources:`, pinned-but-undeclared;
- as a coarse backstop, a synthesis page that carries zero local `.md` inline links, synthesis grounded in nothing visible (Approach owns the empty-`extract_md_links(strip_code(…))` definition).

All three surface at `info` and never block, honoring the wiki's "lint surfaces, doesn't enforce" stance. Info across the board, including the zero-links backstop, is deliberate: `auto_shaper_wiki`'s `<lint_clean>` still treats non-contested warns as stranding (the contested-`quality` carve-out is the only warn exception), this task ships no agent fix move for these findings (see Approach Out of scope), and inserting a citation is a judgment call the agent's remediation contract surfaces rather than auto-applies. A warn would strand every audit between that bar and citation-stuffing. The check verifies citation **presence and channel consistency only**. It deliberately does not verify **grounding** (whether a cited source actually supports a paraphrased claim), which stays a human/agent-review concern (see Approach Out of scope).

## Context

The wiki's provenance model already states the contract this check enforces: the `sources:` frontmatter is the canonical inventory, and inline standard-markdown links pin specific claims to specific raw sources. The rule lives in `plugins/knowledge_management/skills/wiki/SKILL.md` under the `<write_or_update_pages>` **Provenance** bullet ("cited *next to* the claim it supports, through an inline standard-markdown link" … "page-level `sources:` frontmatter, the canonical inventory").

No current check verifies the two channels agree. In `plugins/knowledge_management/skills/wiki/scripts/lint.py` the three `sources:`-consuming checks each read a different facet: `check_stale_content` (cited-source `ingested` dates), `check_source_paths_exist` (each `sources:` entry resolves on disk, blocking), and `check_quality_signals` (the `sources:` list length, for the single-source heuristic). None compares the declared inventory against the inline links, so a synthesis page can carry a `sources:` entry it never cites, or cite a raw file it never declared, and pass clean.

The primitives this check needs already exist in the same file:

- `extract_md_links` returns resolved `.md` link targets for a page body (it already drops images, footnotes, external URLs, and non-`.md` targets). Every live link walk in this file (`check_links_and_orphans`, index completeness) calls `extract_md_links(strip_code(body), …)` so fenced and inline documentation examples are never treated as citations; the new check uses that same preprocessing. Raw sources are `raw/<kind>/<slug>.md`, so inline citations into `raw/` end in `.md`, survive that filter, and resolve as ordinary targets. Classify one as a citation by testing that its wiki-root-relative path begins with `raw/`.
- `parse_frontmatter` yields the page `type` and the `sources` list; `iter_wiki_pages` yields the content pages (it already excludes `raw/`, `_archive/`, and the root); `check_type_location` shows the per-page `type` read pattern.
- The `sources:` list stores wiki-root-relative `raw/<kind>/<slug>.md` strings, the same form the resolved inline target reduces to, so the comparison is exact set arithmetic, with no fuzzy matching.

Why only synthesis types: `query`/`summary`/`comparison` are the pages that synthesize across sources, so a missing or inconsistent citation there is the "synthesizes without citing" failure mode the check targets. The check must **not** demand that raw links exist, because a `query` page legitimately cites other wiki pages (an inline link into `concepts/` or `entities/` rather than into `raw/`) whose own raw grounding sits on those pages. It only flags disagreement between what is *declared* and what is *linked to raw*, which leaves a legitimately page-citing page that omits `sources:` unflagged (same empty inventory as an empty list if one appears). Shipped Provenance and `REQUIRED_FRONTMATTER` leave the key off when there are no captured sources; sibling `sources:`-consuming checks already normalize with `fm.get("sources") or []`.

Remediation is not built here. Because the `auto_shaper_wiki` agent runs `lint.py` inside its assess→fix→verify loop, the new finding flows to the agent automatically; an implementer adds no remediation logic to the linter. Info-level finding **suppression** is likewise out of scope. That mechanism is owned by [wiki_lint-accepted-info-suppression.md](archive/wiki_lint-accepted-info-suppression.md); this task adds no per-finding acknowledge handling.

[wiki_auto-shaper-internal-contradictions.md](archive/wiki_auto-shaper-internal-contradictions.md) already finished: it rewrote `<lint_clean>` with the contested-page warn carve-out. The carve-out stays contested-only; Goal owns why these three findings therefore stay `info`.

Related work: [wiki_provenance-via-raw-and-sources.md](wiki_provenance-via-raw-and-sources.md) owns mid-conversation `wiki_import` capture into `raw/` + `sources:` (and `wiki_fix` routing for uncaptured narration); it does not define the provenance convention. What counts as a source for this check is the shipped **Provenance** contract already cited above in this section.

## Approach

1. Add a check function to `plugins/knowledge_management/skills/wiki/scripts/lint.py` (e.g. `check_synthesis_citation`) and invoke it from `main()` beside the other page-walk checks (e.g. after `check_sources_section`) so a bare `python3 scripts/lint.py` runs it. For each page from `iter_wiki_pages` whose `type` is in the synthesis set:
   - read the inventory with `fm.get("sources") or []` into a set of wiki-root-relative strings (absent key and empty list are the same empty inventory);
   - run `extract_md_links(strip_code(body), page)` once (matching `check_links_and_orphans` and the index completeness walk), reduce each resolved target to its wiki-root-relative path, and collect those beginning with `raw/` into an inline-citation set;
   - append `Issue(SEV_INFO, "citation", page, …)` when that same call returns no results, the zero local `.md` inline-links backstop (empty `extract_md_links` after `strip_code`; images, footnotes, external URLs, and non-`.md` targets stay dropped by the primitive and do not clear the backstop);
   - append `Issue(SEV_INFO, "citation", page, …)` for each `sources:` entry absent from the inline-citation set (declared, never pinned);
   - append `Issue(SEV_INFO, "citation", page, …)` for each inline `raw/` citation absent from `sources:` (pinned, never declared).
2. Construct all three findings with `SEV_INFO` so they leave the exit code untouched (a wiki tripping only these still exits 0). Do not add a check registry or a key→severity map. `main()` already drives checks by direct calls, and severity is set on each `Issue`.
3. Document the check: add a row to `plugins/knowledge_management/skills/wiki/references/lint_checks.md`; rewrite that file’s `## Severity buckets` **info** bullet in place so it names the three new citation-consistency findings (declared-but-never-cited, cited-but-undeclared, zero-inline-links); and name the check in the lint severity-bucket lists in `SKILL.md` under `<narrow_inline_checks>`. State plainly in both files that the check verifies citation *presence and consistency*, not *grounding*, and word any author-facing guidance as "cite where the claim is grounded" rather than "add a citation to clear the check," so the rule pushes toward grounding instead of citation-stuffing.
4. The synthesis-type gate is the locked set `{summary, query, comparison}`. Exclude `concept` because those pages describe a mechanism and may legitimately carry `confidence` instead of per-claim raw citation.

**Out of scope:**

- **Grounding verification**: whether a cited source actually supports a paraphrased claim. Grounding stays human/agent review; this task verifies citation presence and channel consistency only.
- **A named `auto_shaper_wiki` remediation move** for the new finding (add the missing inline link, prune a decorative `sources:` entry, or flag for human), and any severity promotion of these findings (including raising the zero-links finding to `warn`). Rejected here until a sibling owner task exists; no such owner is filed.

## Acceptance

- A new check function exists in `plugins/knowledge_management/skills/wiki/scripts/lint.py` and is invoked as a direct call from `main()` (no check registry or key→severity map) so `python3 scripts/lint.py` runs it.
- Staged fixture pages prove each branch:
  - a synthesis page with a `sources:` entry no inline link references → emits the `info` finding with category `"citation"` whose message includes "declared but never cited inline" and names that source;
  - a synthesis page with an inline `raw/…` link absent from `sources:` → emits the `info` finding with category `"citation"` whose message includes "cited inline but missing from `sources:`";
  - a synthesis page with zero local `.md` inline links (`extract_md_links(strip_code(body), page)` empty per Approach) → emits the zero-links `info` finding with category `"citation"`;
  - a synthesis page whose `sources:` entries each have a matching inline raw link and whose inline raw links are all declared → emits none of the new findings (true negative);
  - a `query` page that omits `sources:` and cites only other wiki pages → emits none of the new findings (guards the page-citing false positive; treat an empty `sources:` list as the same empty inventory if the fixture mentions it);
  - a synthesis page that lists in `sources:` the same `raw/…` path that appears only inside a fenced or inline code example, and that also carries at least one live non-raw `.md` inline link in prose → emits the declared-but-never-cited `info` finding with category `"citation"` for that `sources:` entry (the example path is absent from the inline-citation set), emits none of the pinned-but-undeclared finding for that example path, and does not emit the zero-links finding (proves `strip_code` preprocessing).
- The check’s synthesis-type gate is the set constant `{summary, query, comparison}` per Approach (“The synthesis-type gate is the locked set.”), so each of those three types is in-scope and every other page `type` is out-of-scope for the new findings.
- A wiki that trips only these new findings still exits 0 (all `info`, never warn or blocking).
- `plugins/knowledge_management/skills/wiki/references/lint_checks.md` carries a row for the new check and its `## Severity buckets` **info** bullet names the three citation-consistency findings; the `SKILL.md` `<narrow_inline_checks>` severity-bucket lists name the check; the row and those lists state the presence-not-grounding limitation and word author-facing guidance as "cite where the claim is grounded" rather than "add a citation to clear the check."
- The wiki script-test harness under `tests/wiki/` passes with the six fixtures above added.
