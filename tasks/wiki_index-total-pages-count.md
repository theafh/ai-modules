---
description: Add a lint.py check that the "Total pages:" header in index.md matches the real page count, so the count stops drifting and being hand-recomputed.
scope: plugins/knowledge_management
created: 2026-05-28T20:06:45
updated: 2026-08-05T19:22:15
status: open
reported-by: Andreas Hoffmann
---

# Lint the `Total pages:` header in `index.md` against the real count

## Goal

The linter compares the `Total pages: N` header written in `index.md` against the actual number of wiki pages on disk and reports a finding when they disagree. The recurring drift (the header being incremented by hand during session wrap-ups and falling out of sync) is caught automatically, and authors stop recomputing the count manually with ad-hoc `grep`/`find | wc -l` commands.

## Context

`index.md` carries a human-maintained `Total pages: N` line. Nothing validates it. The existing index check, `check_index_completeness` in [skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py), only verifies that *each* page on disk is *referenced* somewhere in `index.md`; it never reads the `Total pages:` header or compares it to a count. As a result the header drifts — incremented per wrap-up without reconciling against ground truth, occasionally jumping by large deltas in a single edit — and the only way it gets corrected today is by an author manually counting (`grep -cE '^- \[' index.md`, `find wiki -name '*.md' | wc -l`) and editing the header, a ritual repeated across sessions.

The linter already has everything needed: `iter_wiki_pages(wiki)` yields exactly the set of pages that should be counted, and `check_index_completeness` already loads `index.md`'s text.

Files involved:

- [plugins/knowledge_management/skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) — `check_index_completeness` and the check registration in the main runner.
- [plugins/knowledge_management/skills/wiki/references/lint_checks.md](../plugins/knowledge_management/skills/wiki/references/lint_checks.md) — document the new check.
- [plugins/knowledge_management/skills/wiki/references/template_index.md](../plugins/knowledge_management/skills/wiki/references/template_index.md) — confirm the `Total pages:` line format the check parses.

## Approach

1. **Parse the header.** In `lint.py`, read the `Total pages: N` line from `index.md` with a tolerant regex (allow surrounding markdown, e.g. a bold `**Total pages:** N` form — check `template_index.md` for the exact shape and match it). If the line is absent, decide whether that is itself a finding (recommended: a low/info finding "index.md has no Total pages header") rather than silently skipping.
2. **Compute ground truth.** Count `len(list(iter_wiki_pages(wiki)))`. Confirm what `iter_wiki_pages` includes/excludes (special files like `SCHEMA.md`/`index.md`/`log.md` are not pages, and the walk also skips `raw/`, `_archive/`, and any directories a wiki lists on the SCHEMA `## Lint` section's `Page-check exclusions:` bullet) so the header convention and the count agree on what "a page" is; document the definition in `lint_checks.md`.
3. **Emit the finding at `info`.** Report both numbers ("index Total pages says N, found M pages on disk"), which surfaces the drift without ever driving the `auto_shaper_wiki` agent's `<relint_until_clean>` loop — matching how the linter already treats count and style nits ("surfaces, doesn't enforce"). `info` is the right level here, not `warn`: the recurring drift is a header hand-inflated during wrap-ups while every page is still listed and the header stays well-formed, and neither existing index move fixes that case. `<fix_page_missing_from_index>` recomputes the count only when a page is missing from the index, and `<fix_index_scaffold_drift>` only when the header is missing or malformed; a pure count drift triggers neither, so a `warn` would strand the agent's clean bar on exactly the case this check exists to catch. At `info` the finding drives no loop and imposes no ordering against [wiki_auto-shaper-internal-contradictions.md](wiki_auto-shaper-internal-contradictions.md)'s clean-bar rewrite, which carves out the contested warn only. Register the check in the main runner alongside `check_index_completeness`.
4. **Optional autofix hook.** If a later change gives the agent a move that recomputes the header on a pure count mismatch, this finding can rise to `warn` in that same change (a clearing move lands with the higher severity, per the family's severity-promotion pattern); until then it stays a report-only `info` finding.

## Acceptance

- A fixture wiki whose `index.md` header disagrees with the page count on disk produces the new finding naming both numbers.
- A fixture wiki whose header matches produces no finding.
- The page-count definition (what counts as a page vs a special file) is documented in `lint_checks.md` and matches `iter_wiki_pages`.
- `lint_checks.md` carries a matrix row for the new check and lists it in the **info** severity bucket; a wiki tripping only this finding still exits 0, so the agent's clean bar is never blocked by it.
- Script unit tests under `tests/wiki/` cover match, mismatch, and missing-header cases.
- `tests/wiki/run_all.sh` passes.
