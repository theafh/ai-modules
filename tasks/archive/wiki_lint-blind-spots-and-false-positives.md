---
description: Fix seven wiki linter defects: block-list frontmatter bypass, fenced-link false blockings, live example taxonomy, index blind spots, bad drift hint, absolute links, unchecked raw frontmatter.
scope: plugins/knowledge_management
created: 2026-07-19T18:51:20
updated: 2026-07-21T13:11:07
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Harden the wiki linter: close validation bypasses and false positives

## Goal

The wiki linter enforces what it documents and flags only real violations. Seven defects, each verified on a scratch wiki built with the bundled `init_wiki.sh`, currently break that contract in [skills/wiki/scripts/lint.py](../../plugins/knowledge_management/skills/wiki/scripts/lint.py): standard YAML block lists silently disable tag and source validation (including blocking checks), example links inside code fences produce blocking findings, a freshly initialized wiki validates tags against the template's placeholder example taxonomy, the index check misses both unlisted and dangling entries, the source-drift warning emits a fix command that fails as given, machine-local absolute body links pass, and raw sidecars missing their required frontmatter are never flagged. After this task, each of those produces the correct finding (or stops producing a false one), proven by fixtures.

## Context

All seven defects live in or around `lint.py`; the file paths below are the full edit surface.

1. **Block-list frontmatter bypasses validation.** `parse_frontmatter` (docstring: "Handles the subset the wiki uses") parses only inline `[a, b]` lists and skips indented lines, so a block-style `tags:`/`sources:` list parses as an empty string. Every consumer follows the `fm.get("tags") or []` pattern and silently validates nothing. Verified: a page with a block-list `tags:` containing an off-taxonomy tag and a block-list `sources:` containing a missing path plus an absolute path produced zero tag or source findings — the `broken-source` check that is otherwise blocking never fired.
2. **The broken-link check reads code fences and inline code.** `check_links_and_orphans` has no fence or inline-code handling, while `check_footnote_syntax`, `check_wikilink_syntax`, and `check_sources_section` all skip both (comment: "Skipped inside fenced code blocks and inline code"). Verified: an example link inside a fenced block and one inside backticks each produced a blocking `broken-link` finding. Inbound-link counting for the orphan check shares the blindness. Consequence beyond noise: the `auto_shaper_wiki` agent must clear blocking findings, and its `fix_broken_md_link` move would rewrite or delete documentation examples.
3. **The template's example taxonomy is live config.** The "Example for AI/ML:" bullets in [references/template_schema.md](../../plugins/knowledge_management/skills/wiki/references/template_schema.md) are unfenced, and `load_taxonomy` / `check_taxonomy_style` scan the Tag Taxonomy section without fence handling. Verified: a fresh wiki lints with 17 "defined in taxonomy but unused" findings for the example tags, meaning an uncustomized wiki validates tags against placeholder AI/ML tags and the "no Tag Taxonomy section" warn can never fire. The same hazard was deliberately engineered away for the `Page-check exclusions:` example — that one is fenced and `load_excluded_roots` skips fences ("never read as live config").
4. **Index membership is substring-matched and never checked in the dangling direction.** `check_index_completeness` passes when `page.name` appears anywhere in the index text, and nothing validates index entries against disk (`index.md` sits outside the page walk, so `check_links_and_orphans` never sees it). Verified both ways: an unlisted `alignment.md` produced no warn because `misalignment.md` was listed, and a listed-but-deleted page produced no finding at all. The `<archive>` workflow in [skills/wiki/SKILL.md](../../plugins/knowledge_management/skills/wiki/SKILL.md) claims "Run `python3 scripts/lint.py` to catch any inbound link you missed", yet the index — the one guaranteed inbound reference — is exactly what lint cannot see.
5. **The drift warning's fix command fails as emitted.** `check_source_drift` interpolates the file's basename, so the message reads `run 'python3 scripts/compute_sha256.py <basename>'`. Verified: running that from the wiki root exits 2 with "path does not exist". [references/lint_checks.md](../../plugins/knowledge_management/skills/wiki/references/lint_checks.md) says the message "names the script directly so an agent can act without reinventing the body-hash logic" — the automation affordance it exists for is broken.
6. **Absolute body links pass when they resolve locally.** `extract_md_links` joins and checks existence only, so a link with an absolute target passes on the author's machine and dangles on every clone. Verified. The frontmatter channels were hardened against exactly this — `broken-source` and `raw-source-path` block absolute paths "regardless of whether it happens to exist locally" — by [wiki_lint-local-path-portability.md](wiki_lint-local-path-portability.md); read it for the portability rationale this extends to the body-link channel.
7. **Raw frontmatter presence is unchecked.** The schema template's `### raw/ Frontmatter` section says "Raw sources ALSO get a small frontmatter block", and the agent carries a `<fix_raw_source_frontmatter_missing>` move — but no lint check flags a raw `.md` missing `ingested` or `sha256`; the drift check skips any file without a `sha256` field. Drift detection is silently inert on precisely the files that skipped hashing, and the common narrow post-ingest lint never surfaces the omission.

Coordination with live siblings: [wiki_index-total-pages-count.md](../wiki_index-total-pages-count.md) co-edits `check_index_completeness` (it adds the `Total pages:` header comparison; this task fixes membership matching) — coordinate if both land near each other. [wiki_synthesis-citation-consistency-lint.md](../wiki_synthesis-citation-consistency-lint.md) builds its citation sets on `parse_frontmatter` and `extract_md_links`; landing this task first spares that check the same block-list and code-fence blind spots.

## Approach

One minimal fix per defect, in `lint.py` unless named otherwise:

1. Extend `parse_frontmatter` to parse block-style lists of scalars (a key with an empty value followed by indented `- item` lines), matching the loader-leniency precedent `load_taxonomy` sets ("robustness here matters more than style enforcement"). Additionally, emit a `frontmatter` warn when a required list-valued field (`tags`, `sources`) is present but parses to an empty value while the raw block shows indented content — the belt for whatever the parser still cannot read.
2. Add fence and inline-code skipping to the link extraction used by `check_links_and_orphans`, for both broken-link emission and inbound counting, reusing the `FENCE_RE` + `INLINE_CODE_RE` pattern of the three checks that already do this.
3. Two halves, both needed: wrap the "Example for AI/ML:" block in `template_schema.md` in a fenced code block (mirroring the fenced `Page-check exclusions:` example), and make `load_taxonomy` plus `check_taxonomy_style` fence-safe like `load_excluded_roots`. Resulting fresh-wiki behavior: an uncustomized taxonomy parses as absent, so the existing "no Tag Taxonomy section" warn fires until the owner defines tags — a signal instead of silent wrong validation.
4. Rework `check_index_completeness` to parse the index's markdown link targets (or match with path boundaries) instead of raw substring containment, and add the dangling direction: every index entry's target must resolve on disk (warn, consistent with the `index` bucket). Rewrite the `<archive>` workflow sentence in `SKILL.md` so its lint-safety-net claim matches what lint then actually covers.
5. Emit the wiki-relative path (`raw/<kind>/<slug>.md`) in the `check_source_drift` message so the quoted command works from the wiki root.
6. Flag absolute or `~`-prefixed body link targets as blocking in the link check, citing the same rationale as `broken-source`; relative resolving links stay untouched.
7. Add a check that raw `.md` files outside `raw/assets/` carry `ingested` and `sha256` (warn — mechanically fixable via `compute_sha256.py`; the origin field stays optional because a sidecar for an out-of-repo local source legitimately carries neither `source_url` nor `source_path`).

Update the affected rows in `references/lint_checks.md` in place for every changed or added check (links, index, drift, taxonomy loading, the new raw-frontmatter check) so the matrix keeps matching the script.

**Out of scope:**

- No general-purpose YAML parser or new dependency; the parser stays stdlib-minimal and grows only block-style scalar lists.
- Severity re-bucketing of existing checks beyond the items named above.
- Citation-channel consistency between `sources:` and inline links — owned by [wiki_synthesis-citation-consistency-lint.md](../wiki_synthesis-citation-consistency-lint.md).
- `Total pages:` header validation — owned by [wiki_index-total-pages-count.md](../wiki_index-total-pages-count.md).

## Acceptance

Each item is proven on staged fixtures under the wiki test harness (`tests/wiki/`):

1. A page with block-style `tags:` including an off-taxonomy tag yields the same `tag` warn as its inline-list twin; block-style `sources:` with a missing path and with an absolute path yields the same blocking `broken-source` findings as inline form.
   - A page whose `tags:` (or `sources:`) has an empty value followed by indented content the scalar-list extension does not read — a nested mapping such as an indented `domain: ai` line rather than `- item` lines — still parses that field to empty and yields the `frontmatter` warn.
2. A page with a broken example link inside a fenced block and one inside inline code yields no `broken-link` finding; a genuinely broken link outside code still blocks; a page whose only inbound link sits inside a fence is reported as an orphan.
3. A wiki freshly materialized by `init_wiki.sh` yields zero unused-tag findings for the template example tags and fires the "no Tag Taxonomy" warn until tags are defined; a customized taxonomy parses exactly as before.
4. An unlisted page whose filename is a substring of a listed filename yields the "not referenced in index.md" warn; an index entry pointing at a nonexistent page yields the new dangling-entry finding; the rewritten `<archive>` sentence in `SKILL.md` no longer claims coverage lint does not provide, and `rg "catch any inbound link you missed"` confirms the old wording is superseded.
5. The drift warn on a fixture names the wiki-relative path, and running the exact quoted command from the fixture wiki root exits 0 and refreshes the hash.
6. A body link with an absolute target that resolves on the fixture machine yields a blocking finding; the same link rewritten relative passes.
7. A raw `.md` without `ingested`/`sha256` outside `raw/assets/` yields the new finding; after `compute_sha256.py` plus an `ingested` stamp it passes; an `.md` under `raw/assets/` stays exempt.
8. Every changed or added check has its row rewritten in `lint_checks.md`, with no stale duplicate description remaining.
9. Script unit tests under `tests/wiki/` cover the fixtures above and `tests/wiki/run_all.sh` passes.
