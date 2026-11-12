---
description: Add a lint.py check that the "Total pages:" header in index.md matches the real page count, so the count stops drifting and being hand-recomputed.
scope: plugins/knowledge_management
created: 2026-05-28T18:06:45Z
updated: 2026-11-11T19:13:22Z
status: ready
reported-by: Andreas Hoffmann
---

# Lint the `Total pages:` header in `index.md` against the real count

## Goal

The linter compares the `Total pages: N` header written in `index.md` against the actual number of wiki pages on disk and reports a finding when they disagree. The recurring drift (the header being incremented by hand during session wrap-ups and falling out of sync) is caught automatically, and authors stop recomputing the count manually with ad-hoc `grep`/`find | wc -l` commands.

## Context

`index.md` carries a human-maintained `Total pages: N` line. Nothing validates it. The existing index check, `check_index_completeness` in [skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py), including that check's registration in the main runner, verifies membership in both directions: every page on disk is referenced somewhere in `index.md`, and every page `index.md` links exists on disk. It never reads the `Total pages:` header or compares it to a count. As a result the header drifts, incremented per wrap-up without reconciling against ground truth and occasionally jumping by large deltas in a single edit. The only way it gets corrected today is by an author manually counting (`grep -cE '^- \[' index.md`, `find wiki -name '*.md' | wc -l`) and editing the header, a ritual repeated across sessions.

The linter already has everything needed: `iter_wiki_pages(wiki)` yields exactly the set of pages that should be counted, and `check_index_completeness` already loads `index.md`'s text.

Files involved:

- [plugins/knowledge_management/skills/wiki/references/lint_checks.md](../plugins/knowledge_management/skills/wiki/references/lint_checks.md): document the new check.
- [plugins/knowledge_management/skills/wiki/references/template_index.md](../plugins/knowledge_management/skills/wiki/references/template_index.md): confirm the `Total pages:` line format the check parses.

## Approach

1. **Parse the header.** In `lint.py`, read the `Total pages: N` line from `index.md` with a tolerant regex (allow surrounding markdown, e.g. a bold `**Total pages:** N` form; check `template_index.md` for the exact shape and match it). When `index.md` is absent, return no issues and reuse `check_index_completeness`'s `if not index.is_file()` guard: that branch already reports the blocking `index.md missing` finding for the wiki, and the run continues to the remaining checks. An absent header emits an `info` finding, "index.md has no Total pages header", rather than a silent skip: no existing check reads the header, so skipping would leave that case uncaught, and `info` is the only severity this check's acceptance contract allows (Acceptance item 4 keeps the whole check in the info bucket with exit 0).
2. **Compute ground truth.** Count `len(list(iter_wiki_pages(wiki)))`. Confirm what `iter_wiki_pages` includes/excludes (special files like `SCHEMA.md`/`index.md`/`log.md` are not pages, and the walk also skips `raw/`, `_archive/`, and any directories a wiki lists on the SCHEMA `## Lint` section's `Page-check exclusions:` bullet) so the header convention and the count agree on what "a page" is; document the definition in `lint_checks.md`.
3. **Emit the finding at `info`.** Report both numbers ("index Total pages says N, found M pages on disk"), which surfaces the drift without ever driving the `auto_shaper_wiki` agent's `<relint_until_clean>` loop, matching how the linter already treats count and style nits ("surfaces, doesn't enforce"). `info` is the right level here, not `warn`: the recurring drift is a header hand-inflated during wrap-ups while every page is still listed and the header stays well-formed, and neither existing index move fixes that case. `<fix_page_missing_from_index>` recomputes the count only when a page is missing from the index, and `<fix_index_scaffold_drift>` only when the header is missing or malformed; a pure count drift triggers neither, so a `warn` would strand the agent's clean bar on exactly the case this check exists to catch. At `info` the finding drives no loop and imposes no ordering against [wiki_auto-shaper-internal-contradictions.md](archive/wiki_auto-shaper-internal-contradictions.md)'s clean-bar rewrite, which carves out the contested warn only. Register the check in the main runner alongside `check_index_completeness`.
4. **Optional autofix hook.** If a later change gives the agent a move that recomputes the header on a pure count mismatch, this finding can rise to `warn` in that same change (a clearing move lands with the higher severity, per the family's severity-promotion pattern); until then it stays a report-only `info` finding.
5. **Extend the `l3` harness scenario.** `l3_lint_no_index` in `tests/wiki/layer1/run.sh` currently discards lint output (`>/dev/null 2>&1`) and asserts only a non-zero exit, so it would pass on a `FileNotFoundError` traceback and never observes the finding. Capture the output with the existing `run_lint` helper (`run_lint "$target" --quiet`, splitting its `<exit>|<output>` return as sibling scenarios do), keep the non-zero exit assertion, and assert the blocking `structure` finding with `assert_lint_finding … blocking structure`, matching how `l4_lint_broken_link` asserts `blocking broken-link`.
6. **Keep the citation scenario's exact counts.** `l85_lint_citation_findings_are_info_only` in `tests/wiki/layer1/run.sh` stages four pages (`concepts/companion.md` plus a `summaries/`, a `queries/`, and a `comparisons/` page) with `add_index_entry_concept` / `add_index_entry_for` on a wiki whose `index.md` came from `template_index.md` carrying `Total pages: 0`, then asserts exactly three findings with `assert_eq "total findings" "$(lint_total "$out")" "3"` and `assert_live_severity_count "three info findings" "$out" info "3"`. The new check would count those four pages against the header's 0 and emit a fourth `info` finding, failing both assertions. After the scenario adds its pages, set its staged `index.md` `Total pages:` header to the number of pages the scenario staged, so the header matches the count on disk and the scenario keeps its three-finding contract. The check stays active on fixture wikis; the fixture header is what the repair fixes.

## Acceptance

- A fixture wiki whose `index.md` header disagrees with the page count on disk produces the new finding naming both numbers.
- A fixture wiki whose header matches produces no finding.
- The page-count definition (what counts as a page vs a special file) is documented in `lint_checks.md` and matches `iter_wiki_pages`.
- `lint_checks.md` carries a matrix row for the new check and lists it in the **info** severity bucket; a wiki tripping only this finding still exits 0, so the agent's clean bar is never blocked by it.
- Script unit tests under `tests/wiki/` cover match, mismatch, and missing-header cases, with the missing-header case asserting the `info` finding.
- A wiki with no `index.md` reports the existing blocking `index.md missing` finding and no traceback: `l3_lint_no_index` in `tests/wiki/layer1/run.sh` captures the lint output with the existing `run_lint` helper and asserts the `[blocking] structure` finding with `assert_lint_finding`, and the new check returns no issues on that input so the finding stays owned by `check_index_completeness`.
- `tests/wiki/run_all.sh` passes: the new check stays active on fixture wikis, and `l85_lint_citation_findings_are_info_only` still reports exactly three findings (three `info`, no warn, no blocking) with its fixture header matching its staged page count.
