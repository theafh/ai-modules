---
description: Add a lint.py check that surfaces citation-consistency issues on synthesis pages — sources: entries never cited inline, and inline raw citations missing from sources:.
scope: plugins/knowledge_management
created: 2026-06-18T00:36:41
updated: 2026-06-18T00:36:41
status: open
reported-by: Andreas Hoffmann
---

# Add a synthesis-page citation-consistency lint check

## Goal

Give the wiki linter a deterministic check that surfaces when a synthesis page's two provenance channels disagree. For pages whose `type` is a synthesis type (`summary`, `query`, `comparison`), compare the page's `sources:` frontmatter inventory against the inline markdown links in its body that resolve under `raw/`, and surface:

- a `sources:` entry that no inline link references — declared-but-unpinned ("decorative") provenance;
- an inline `raw/` citation absent from `sources:` — pinned-but-undeclared;
- as a coarse backstop, a synthesis page that carries zero inline links of any kind — synthesis grounded in nothing visible.

All three surface at `info`/`warn` and never block, honoring the wiki's "lint surfaces, doesn't enforce" stance. The check verifies citation **presence and channel consistency only** — it deliberately does not verify **grounding** (whether a cited source actually supports a paraphrased claim), which stays a human/agent-review concern (see Approach non-goals).

## Context

The wiki's provenance model already states the contract this check enforces: the `sources:` frontmatter is the canonical inventory, and inline standard-markdown links pin specific claims to specific raw sources. The rule lives in `plugins/knowledge_management/skills/wiki/SKILL.md` under the `<write_or_update_pages>` **Provenance** bullet ("attribution stays *next to* the claim … The page-level `sources:` frontmatter is the canonical inventory; inline links pin specific claims to specific sources").

No current check verifies the two channels agree. In `plugins/knowledge_management/skills/wiki/scripts/lint.py` the three `sources:`-consuming checks each read a different facet: `check_stale_content` (cited-source `ingested` dates), `check_source_paths_exist` (each `sources:` entry resolves on disk, blocking), and `check_quality_signals` (the `sources:` list length, for the single-source heuristic). None compares the declared inventory against the inline links, so a synthesis page can carry a `sources:` entry it never cites, or cite a raw file it never declared, and pass clean.

The primitives this check needs already exist in the same file:

- `extract_md_links` returns resolved `.md` link targets for a page body (it already drops images, footnotes, external URLs, and non-`.md` targets). Raw sources are `raw/<kind>/<slug>.md`, so inline citations into `raw/` end in `.md`, survive that filter, and resolve as ordinary targets — classify one as a citation by testing that its wiki-root-relative path begins with `raw/`.
- `parse_frontmatter` yields the page `type` and the `sources` list; `iter_wiki_pages` yields the content pages (it already excludes `raw/`, `_archive/`, and the root); `check_type_location` shows the per-page `type` read pattern.
- The `sources:` list stores wiki-root-relative `raw/<kind>/<slug>.md` strings — the same form the resolved inline target reduces to — so the comparison is exact set arithmetic, with no fuzzy matching.

Why only synthesis types: `query`/`summary`/`comparison` are the pages that synthesize across sources, so a missing or inconsistent citation there is the "synthesizes without citing" failure mode the check targets. The check must **not** demand that raw links exist, because a `query` page legitimately cites other wiki pages — an inline link into `concepts/` or `entities/` rather than into `raw/` — whose own raw grounding sits on those pages. It only flags disagreement between what is *declared* and what is *linked to raw*, which leaves a legitimately page-citing page with an empty `sources:` unflagged.

Remediation is not built here. Because the `wiki_auto_shaper` agent runs `lint.py` inside its assess→fix→verify loop, the new finding flows to the agent automatically; an implementer adds no remediation logic to the linter. Info-level finding **suppression** is likewise out of scope — that mechanism is owned by [wiki_lint-accepted-info-suppression.md](wiki_lint-accepted-info-suppression.md); this task adds no per-finding acknowledge handling.

Related work: [wiki_provenance-via-raw-and-sources.md](wiki_provenance-via-raw-and-sources.md) defines the `raw/` + `sources:` provenance convention whose consistency this check enforces; read it for the semantics of what counts as a source.

## Approach

1. Add a check function to `plugins/knowledge_management/skills/wiki/scripts/lint.py` (e.g. `check_synthesis_citation`) and register it in the linter's check registry so a bare `python3 scripts/lint.py` runs it. For each page from `iter_wiki_pages` whose `type` is in the synthesis set:
   - read `sources:` into a set of wiki-root-relative strings;
   - run `extract_md_links` on the body, reduce each resolved target to its wiki-root-relative path, and collect those beginning with `raw/` into an inline-citation set; track separately whether the body has **any** inline link;
   - emit `warn` (finding key e.g. `citation`) when the body has zero inline links of any kind;
   - emit `info` for each `sources:` entry absent from the inline-citation set (declared, never pinned);
   - emit `info` for each inline `raw/` citation absent from `sources:` (pinned, never declared).
2. Slot the new finding key into the linter's severity buckets so the three findings report at `info`/`warn` and leave the exit code untouched (a wiki tripping only these still exits 0).
3. Document the check: add a row to `plugins/knowledge_management/skills/wiki/references/lint_checks.md`, and name the check in the lint severity-bucket lists in `SKILL.md` under `<narrow_inline_checks>`. State plainly in both that the check verifies citation *presence and consistency*, not *grounding*, and word any author-facing guidance as "cite where the claim is grounded" rather than "add a citation to clear the check," so the rule pushes toward grounding instead of citation-stuffing.
4. **Open decision:** whether `concept` joins the synthesis set. Default: exclude it — `concept` pages describe a mechanism and may legitimately carry `confidence` instead of per-claim raw citation — and start with `{summary, query, comparison}`. An implementer may add `concept` if a fixture shows under-cited concept pages slipping through.

Non-goals / follow-ups (kept out to keep this task atomic):

- **Grounding verification** (does the source support the claim). The wiki paraphrases and links whole files, so surface matching false-alarms on good paraphrase and entailment needs an LLM — which, pushed into skill rules, invites fabrication. Grounding stays human/agent review.
- **A named `wiki_auto_shaper` remediation move** for the new finding (add the missing inline link, prune a decorative `sources:` entry, or flag for human) — a worthwhile follow-up analogous to the agent's existing orphan-page fix move, filed separately rather than folded in.

## Acceptance

- A new check function exists in `plugins/knowledge_management/skills/wiki/scripts/lint.py`, registered so `python3 scripts/lint.py` runs it.
- Staged fixture pages prove each branch:
  - a synthesis page with a `sources:` entry no inline link references → emits the `info` "declared but never cited inline" finding naming that source;
  - a synthesis page with an inline `raw/…` link absent from `sources:` → emits the `info` "cited inline but missing from `sources:`" finding;
  - a synthesis page with zero inline links → emits the `warn` finding;
  - a synthesis page whose `sources:` entries each have a matching inline raw link and whose inline raw links are all declared → emits none of the new findings (true negative);
  - a `query` page with empty `sources:` that cites only other wiki pages → emits none of the new findings (guards the page-citing false positive).
- A wiki that trips only these new findings still exits 0 (they are `info`/`warn`, never blocking).
- `plugins/knowledge_management/skills/wiki/references/lint_checks.md` carries a row for the new check, and the `SKILL.md` `<narrow_inline_checks>` severity-bucket lists name it; both state the presence-not-grounding limitation.
- The wiki script-test harness under `tests/wiki/` passes with the five fixtures above added.
