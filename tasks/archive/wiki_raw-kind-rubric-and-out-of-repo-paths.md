---
description: Introduce documented `source_path:` semantics for out-of-repo local raw sources in the SCHEMA template and ingest guidance; the `raw/<kind>/` rubric already shipped in raw_taxonomy.md.
scope: plugins/knowledge_management
created: 2026-05-28T19:25:04
updated: 2026-07-19T17:02:38
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Introduce `source_path:` for out-of-repo local raw sources (kind rubric already shipped)

**Superseded (2026-07-19):** the out-of-repo affordance this task shipped — an absolute or `~`-prefixed `source_path:` for a file outside the repo — was reverted by [wiki_lint-local-path-portability.md](wiki_lint-local-path-portability.md) (Option A). `source_path:` is now repo-relative only (a wiki not in a repo is local-only and unconstrained), and an out-of-repo local file is captured by a body excerpt plus a prose locality note with no stored path. The documented `source_path:` field, the "Local file on the author's workstation" locality marker, the ingest guidance, and the `raw/<kind>/` rubric all shipped and stand; only the out-of-repo path form was reversed. That sibling task owns the final `source_path:` semantics — the Goal / Approach / Acceptance below describe the original, now-superseded design and are kept as history.

## Goal

Raw sidecars gain a documented way to point at a local file that lives outside the repository: a `source_path:` frontmatter field whose semantics cover in-repo mirrors (repo-relative) and out-of-repo local files (absolute or `~`-prefixed), with a portability caveat and the rule that the sidecar body must excerpt enough content to stand alone. Different authors then represent local sources consistently instead of inventing the field ad hoc.

## Context

This task originally carried two halves. The first half — a `raw/<kind>/` selection rubric — has shipped: `references/raw_taxonomy.md` in the wiki skill bundle defines the bucket table, ordered classification heuristics (a transcript routes to `raw/meetings/`, a paste classifies by body shape), and edge-case disambiguations, and both the wiki skill's ingest step and `wiki_import` name it as the canonical reference. Only the second half remains, and its premise needs correcting: `source_path:` is documented nowhere in the plugin. The SCHEMA template's `### raw/ Frontmatter` subsection defines exactly `source_url:`, `ingested:`, and `sha256:`; the `source_path:` convention existed only in the originating downstream wiki, which used an absolute `~`-prefixed path for a chat-session transcript because no documented field fit. A local file outside the repo (for example a session log under the user's home directory) still fits neither `source_url:` nor any other documented field.

Files involved:

- [template_schema.md](../../plugins/knowledge_management/skills/wiki/references/template_schema.md) — the `### raw/ Frontmatter` subsection where the field and its semantics land.
- [SKILL.md](../../plugins/knowledge_management/skills/wiki/SKILL.md) — the ingest workflow's raw-capture guidance, so authors know when to reach for `source_path:` instead of `source_url:`.

Related tasks: [wiki_provenance-via-raw-and-sources.md](../wiki_provenance-via-raw-and-sources.md) (consumes this field for mid-conversation machine-local artifacts) and [wiki_file-access-for-edits-and-sources.md](wiki_file-access-for-edits-and-sources.md) (documents how such paths are opened). Implement this task first or together with those.

## Approach

1. **`### raw/ Frontmatter` in the SCHEMA template** — add `source_path:` beside `source_url:` with these semantics: a repo-relative path for in-repo mirrors, an absolute or `~`-prefixed path for local files outside the repo. Document the use case (session transcripts, local notes) and the caveat that out-of-repo paths are non-portable across machines, so the sidecar body must carry enough excerpted content to be useful without the original file.
2. **Host note** — in the SCHEMA template's `### raw/ Frontmatter` subsection, beside the excerpt-must-stand-alone rule, recommend that out-of-repo sources mark their locality in the sidecar body, for example "Local file on the author's workstation; relevant content excerpted below."
3. **Ingest guidance in SKILL.md** — one sentence in the raw-capture guidance: use `source_url:` for externally published sources and `source_path:` for local files; a sidecar carries at least one of the two.
4. Leave the linter unchanged: `check_source_paths_exist` validates page-level `sources:` entries, not raw-sidecar origin fields, and an out-of-repo `source_path:` is expected to be unresolvable on other machines — an existence check would misfire by design.

**Out of scope:** end-to-end Layer 2 harness verification of this convention — a `wiki_import` chat-session scenario that produces a `raw/meetings/` sidecar carrying `source_path:` — lands directly in the wiki test suite (`tests/wiki/`), not as a deliverable of this documentation task.

## Acceptance

- The SCHEMA template's `### raw/ Frontmatter` subsection documents `source_path:` with the repo-relative, absolute, and `~`-prefixed forms, its use case (session transcripts, local notes), the portability caveat, and the excerpt-must-stand-alone rule.
- The same `### raw/ Frontmatter` subsection carries the locality-marker recommendation from Approach's **Host note** step — an out-of-repo source marks its locality in the sidecar body — verifiable by the example phrase "Local file on the author's workstation" appearing in the subsection.
- The SKILL.md ingest raw-capture guidance states when to use `source_path:` versus `source_url:`, and that a raw sidecar carries at least one of the two.
