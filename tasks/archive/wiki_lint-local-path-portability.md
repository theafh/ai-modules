---
description: Fix the wiki linter's `sources:` absolute-path escape, and constrain raw-sidecar `source_path:` to a repo-relative form, capturing out-of-repo local files as prose.
scope: plugins/knowledge_management
created: 2026-07-19T14:09:18
updated: 2026-07-19T17:02:38
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Harden the wiki linter against non-portable local paths in provenance fields

## Goal

The wiki linter stops a machine-local absolute path from passing as durable provenance, so a wiki stays portable across machines and clones. The settled deliverable fixes `check_source_paths_exist` in the wiki skill's `scripts/lint.py` so a page's `sources:` entry that is absolute or escapes the `raw/` tree is rejected as a blocking finding, instead of silently resolving on the author's machine and breaking everywhere else. The raw-sidecar `source_path:` field is likewise constrained to a portable repo-relative form (option A, resolved and implemented): a `source_path:` may point outside the wiki directory but must stay inside the repository the wiki ships within, so an absolute, `~`-prefixed, or repo-escaping `source_path:` is rejected, while an out-of-repo local file is captured by a body excerpt plus a prose locality note with no stored path. A wiki that is not in a repository is local-only and ships nowhere, so its `source_path:` values face no portability constraint and the check is skipped there.

## Context

Wiki provenance runs in two hops with different portability guarantees. Hop 1, page to raw: a wiki page's `sources:` frontmatter lists `raw/<kind>/<slug>.md` paths, and `check_source_paths_exist` validates each resolves on disk at blocking severity. Hop 2, raw to origin: a raw sidecar records where its content came from via `source_url:` (external) or `source_path:` (local), and the linter never validates these because the per-page walk skips the `raw/` tree.

The hop-1 defect: `check_source_paths_exist` builds each target as `(wiki / src).resolve()`. Python's `pathlib` discards the left operand when the right side is absolute, so an absolute `sources:` entry bypasses the `wiki /` join, resolves against the real filesystem, and passes on the author's machine while breaking on every other clone. The documented contract is strict `raw/<kind>/<slug>.md` paths — repo-relative, resolved against the wiki root — so an absolute or `raw/`-escaping entry violates it and should block. The just-shipped `source_path:` convention, which legitimizes local-path thinking, raises the odds an author drops a machine-local absolute path here.

The `source_path:` convention shipped by [wiki_raw-kind-rubric-and-out-of-repo-paths.md](wiki_raw-kind-rubric-and-out-of-repo-paths.md) documents three forms in the SCHEMA template's `### raw/ Frontmatter` subsection: a repo-relative path for an in-repo mirror, and an absolute or `~`-prefixed path for a local file outside the repository. The out-of-repo forms are non-portable by design, mitigated only by the excerpt-must-stand-alone rule (the sidecar body carries enough content that the broken path is a non-load-bearing breadcrumb). This task revisits whether that breadcrumb earns its portability cost.

Files involved:

- [lint.py](../../plugins/knowledge_management/skills/wiki/scripts/lint.py) — `check_source_paths_exist` for the settled fix, plus a sibling `source_path:` check over `raw/` sidecars if the decision adds one.
- [template_schema.md](../../plugins/knowledge_management/skills/wiki/references/template_schema.md) — the `### raw/ Frontmatter` subsection; its `source_path:` semantics change only if the decision rejects the out-of-repo form.
- [SKILL.md](../../plugins/knowledge_management/skills/wiki/SKILL.md) and the `wiki_import` capture step — the ingest guidance, likewise decision-gated.

Related tasks that consume the `source_path:` semantics this task may change: [wiki_provenance-via-raw-and-sources.md](../wiki_provenance-via-raw-and-sources.md) and [wiki_file-access-for-edits-and-sources.md](wiki_file-access-for-edits-and-sources.md).

## Approach

The settled fix ships regardless of the open decision:

1. In `check_source_paths_exist`, reject a `sources:` entry that is absolute or resolves outside the wiki's `raw/` tree, as a blocking `broken-source`-class finding, and guard the join so an absolute entry can no longer override `wiki /`. Keep the on-disk existence check for the surviving repo-relative entries.
2. Cover the rejection with a staged fixture in the wiki skill's Layer 1 script tests: a page carrying an absolute `sources:` entry and one escaping `raw/`, alongside a valid repo-relative entry that still passes.

**Resolved — option A (implemented).** The user chose to constrain `source_path:` to the repo-relative form rather than keep the shipped out-of-repo affordance. The options weighed:

- **A (leading) — repo-relative only, capture out-of-repo sources by content.** Reject an absolute or `~`-prefixed `source_path:`. An in-repo mirror uses a repo-relative `source_path:`, now lint-validatable like `sources:`; a genuinely out-of-repo local file is captured by its body excerpt plus the host-note locality prose, with no machine-specific path stored. Every path in the wiki becomes portable, at the cost of revising the just-shipped `source_path:` docs and the WI-4 regression scenario that asserts the absolute form.
- **B — repo-relative only, mirror required.** Same rejection, but an out-of-repo source must be copied into the wiki's `raw/` tree to earn a repo-relative `source_path:`. Maximally portable and fully lint-validatable, but forces mirroring local files that may be large, private, or ephemeral.
- **C (as shipped) — keep allowing the out-of-repo absolute/`~` form.** Leave the convention and WI-4 as they are; the excerpt-stand-alone rule stays the only mitigation and the linter never validates `source_path:`. No work beyond the settled `sources:` fix.

What shipped for A: a new `check_source_path_portable` in `lint.py` rejects an absolute, `~`-prefixed, or repo-escaping raw-sidecar `source_path:` as blocking and requires a surviving relative one to resolve inside the repo (the git root holding the wiki); a wiki not inside a git repo is local-only, so the check is skipped there entirely; the `### raw/ Frontmatter` semantics and the wiki and `wiki_import` ingest guidance were rewritten in place to the repo-relative rule (a source may sit outside the wiki dir but must stay inside the repo) with out-of-repo capture by excerpt and prose; the `auto_shaper_wiki` raw-frontmatter checks were aligned so a prose-only out-of-repo sidecar is not flagged as drift; `references/lint_checks.md` was updated with the tightened `broken-source` rule and a new `raw-source-path` row; and the WI-4 Layer 2 scenario asserts an out-of-repo capture carries a prose locality note and no machine-local path.

## Acceptance

- A fixture wiki page whose `sources:` frontmatter carries an absolute path (for example `/tmp/foo.md`) is flagged blocking by `check_source_paths_exist`, while a repo-relative `raw/<kind>/<slug>.md` entry that resolves on disk still passes.
- A fixture `sources:` entry that escapes the `raw/` tree (for example `../outside.md` or `concepts/foo.md`) is flagged blocking.
- The wiki skill's Layer 1 script tests cover the new rejection and the whole existing suite stays green.
- The `source_path:` open decision is recorded resolved before any `source_path:` semantics change. On A or B, the `### raw/ Frontmatter` subsection no longer documents the out-of-repo absolute/`~` form, the wiki and `wiki_import` ingest guidance match, the WI-4 scenario asserts the chosen form, and `tests/wiki/run_all.sh --layer2` passes; on C, those artifacts stay unchanged.
