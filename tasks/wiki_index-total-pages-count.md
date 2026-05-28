---
description: Add a lint.py check that the "Total pages:" header in index.md matches the real page count, so the count stops drifting and being hand-recomputed.
scope: plugins/knowledge_management
created: 2026-05-28T20:06:45
updated: 2026-05-28T20:07:08
status: open
---

# Lint the `Total pages:` header in `index.md` against the real count

## Goal

The linter compares the `Total pages: N` header written in `index.md` against the actual number of wiki pages on disk and reports a finding when they disagree. The recurring drift (the header being incremented by hand during session wrap-ups and falling out of sync) is caught automatically, and authors stop recomputing the count manually with ad-hoc `grep`/`find | wc -l` commands.

## Context

`index.md` carries a human-maintained `Total pages: N` line. Nothing validates it. The existing index check, `check_index_completeness` in [skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) (around line 695), only verifies that *each* page on disk is *referenced* somewhere in `index.md`; it never reads the `Total pages:` header or compares it to a count. As a result the header drifts — incremented per wrap-up without reconciling against ground truth, occasionally jumping by large deltas in a single edit — and the only way it gets corrected today is by an author manually counting (`grep -cE '^- \[' index.md`, `find wiki -name '*.md' | wc -l`) and editing the header, a ritual repeated across sessions.

The linter already has everything needed: `iter_wiki_pages(wiki)` yields exactly the set of pages that should be counted, and `check_index_completeness` already loads `index.md`'s text.

Files involved:

- [plugins/knowledge_management/skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) — `check_index_completeness` (~695) and the check registration in the main runner (~1242).
- [plugins/knowledge_management/skills/wiki/references/lint_checks.md](../plugins/knowledge_management/skills/wiki/references/lint_checks.md) — document the new check.
- [plugins/knowledge_management/skills/wiki/references/template_index.md](../plugins/knowledge_management/skills/wiki/references/template_index.md) — confirm the `Total pages:` line format the check parses.

## Approach

1. **Parse the header.** In `lint.py`, read the `Total pages: N` line from `index.md` with a tolerant regex (allow surrounding markdown, e.g. a bold `**Total pages:** N` form — check `template_index.md` for the exact shape and match it). If the line is absent, decide whether that is itself a finding (recommended: a low/info finding "index.md has no Total pages header") rather than silently skipping.
2. **Compute ground truth.** Count `len(list(iter_wiki_pages(wiki)))`. Confirm what `iter_wiki_pages` includes/excludes (special files like `SCHEMA.md`/`index.md`/`log.md` should not be counted as pages) so the header convention and the count agree on what "a page" is; document the definition in `lint_checks.md`.
3. **Emit the finding.** On mismatch, report which severity fits the project's tolerance. A `warn`-level finding with both numbers ("index Total pages says N, found M pages on disk") is appropriate — it surfaces the drift without blocking a mid-edit state. Register the check in the main runner alongside `check_index_completeness`.
4. **Optional autofix hook.** If the linter grows an autofix path elsewhere, this is a safe candidate (rewrite the header to the computed count); otherwise leave it as a report-only finding.

Bump the skill and plugin versions per the one-bump-per-commit rule at commit time.

## Acceptance

- A fixture wiki whose `index.md` header disagrees with the page count on disk produces the new finding naming both numbers.
- A fixture wiki whose header matches produces no finding.
- The page-count definition (what counts as a page vs a special file) is documented in `lint_checks.md` and matches `iter_wiki_pages`.
- Script unit tests under `tests/wiki/` cover match, mismatch, and missing-header cases.
- `make lint` clean; `tests/wiki/run_all.sh` passes.
