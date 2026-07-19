# Lint Check Matrix

Reference for `scripts/lint.py` — what each check catches and which severity bucket it lands in.

| Bucket | Checks |
| --- | --- |
| schema | `SCHEMA.md` present; the `## Frontmatter` section has a `yaml` block declaring `type: a \| b \| c`. The linter loads the page-type enum and derives the corresponding page directories (`<type>s`, with `-y → -ies` pluralization) from this declaration. **Blocking** when the enum cannot be extracted — type-dependent checks are skipped until the schema is fixed. |
| boilerplate | Verbatim equality of "must-stay-verbatim" regions against the canonical templates in `references/`. Each `VerbatimSlot` pairs a wiki file with a template and an extractor — the default extractor returns everything above the first `##` heading, covering the SCHEMA.md prelude (H1 + attribution paragraph) and the log.md preamble (H1 + conventions blockquote). Add another slot to enforce additional regions. **Warn** on any mismatch — the lint output is the structural source of truth for these slots, independent of agent diligence. |
| structure | flat `<type>s/<slug>.md` layout enforced. Every expected type folder declared in SCHEMA.md's `type:` enum must exist on disk (**warn** when missing) and every page must live directly at `<pluralized-type>/<slug>.md` — no thematic prefix, no sub-folder nesting inside the type folder, no bare files at the wiki root. **Blocking** for misfiled pages; the message includes the suggested move target. Thematic scope belongs in `tags:` and `type:`, not folder names. |
| frontmatter | required fields (`title`, `created`, `updated`, `type`, `tags`, `sources`); `type` validated against the schema-loaded enum; `confidence` enum; YYYY-MM-DD date format |
| custom fields | custom (non-canonical) frontmatter keys validated against their `field: a \| b \| c` declaration in `SCHEMA.md`'s `## Frontmatter`; pages using undeclared custom keys are flagged; declared-but-unused custom fields surface as info |
| links | broken markdown links to `.md` files; orphan pages with zero inbound links |
| broken-source | every `sources:` frontmatter entry must be a repo-relative path under the wiki's `raw/` tree that resolves on disk; an absolute, `~`-prefixed, or `raw/`-escaping entry is blocking (it resolves only on the author's machine — Python's `pathlib` even lets an absolute entry override the wiki-root join), same severity as broken markdown links. The frontmatter is the canonical source inventory; a non-resolving or non-portable entry breaks the provenance contract the field exists to enforce. |
| raw-source-path | every raw sidecar's `source_path:` must be a relative path to a source kept inside the repository the wiki ships within (it may sit outside the wiki dir but must stay inside the repo) that resolves on disk; an absolute, `~`-prefixed, or repo-escaping value is blocking because it resolves only on the author's machine or points outside the versioned tree. A local source outside the repo takes no `source_path:` — it is captured by the sidecar body excerpt and a prose locality note, so a sidecar without the field is fine. A wiki that is not inside a git repo is local-only and ships nowhere, so the check is skipped entirely there — every path already resolves on its one machine. Walks the `raw/` tree, which the per-page checks skip. |
| sources-section | deprecated body `## Sources` / `## Source references` H2 heading inside a wiki page. Source attribution lives in the `sources:` frontmatter (canonical inventory) and inline next to each claim; a bottom-of-page collection duplicates the frontmatter and splits the claim-source binding across the page. The check is body-only and skips fenced code blocks. |
| footnote | `[^name]` footnote references and `[^name]:` definitions outside fenced code blocks and inline code. The wiki uses inline standard-markdown links for claim-level attribution (`[text](relative/path.md)`) so attribution sits adjacent to the claim, feeds the broken-link check, and renders consistently across markdown viewers. |
| index | wiki pages not referenced in `index.md` |
| tags | tags used but missing from the `SCHEMA.md` taxonomy; tags in the taxonomy but unused on any page (stale tag detection) |
| taxonomy style | SCHEMA.md `## Tag Taxonomy` bullets that drift from the canonical `- Label: tag, tag, …` one-line form. Flags emphasis around the category label (`**Label:**`, `*Label:*`, `__Label:__`, `_Label:_`), `*` or `+` used in place of `-`, and soft-wrap continuation lines that split a bullet across physical lines. The loader tolerates all three forms so off-taxonomy warnings don't false-positive, and this check nudges authors back to the canonical form so the leniency stays a safety net. |
| stale | `updated` more than 90 days older than the newest cited source's `ingested` date |
| quality | `contested: true`; `confidence: low`; single-source pages with no confidence field set |
| drift | sha256 mismatch on files in `raw/`. The fix path is `python3 scripts/compute_sha256.py <file>` (or no-arg to refresh every raw file); the warning message names the script directly so an agent can act without reinventing the body-hash logic. |
| size | pages over 200 lines |
| log | `log.md` over 500 entries (rotate to `log-YYYY.md`) |
| markdown style | bullet style (`-` only); header level skipping; trailing punctuation in headers; fenced code without language identifier; multiple consecutive blank lines; bare URLs; list-marker spacing; trailing newline (matches the `format_markdown` skill) |
| wikilink | `[[target]]` or `[[target\|alias]]` wikilink-style references outside of fenced code blocks and inline code. The wiki uses standard markdown links `[text](relative/path.md)` so cross-references resolve in plain renderers and feed the broken-link check; the warning includes a hint suggesting the equivalent markdown form. |

## Page-walk scope

The per-page checks (frontmatter, links, structure, orphans, tags, size, and the rest) run on every Markdown file under the type folders. The walk always skips the `raw/` and `_archive/` trees; a vault extends that skip set by listing extra top-level directories on a `- Page-check exclusions: a, b` bullet in `SCHEMA.md`'s `## Lint` section (documented in `template_schema.md`). The names are read only outside fenced code blocks, so a documented example never becomes a live exclusion.

## Severity buckets

- **blocking** — broken links, broken or non-portable `sources:` frontmatter entries, non-portable raw-sidecar `source_path:` values, missing or malformed frontmatter, missing `index.md`, missing or unparseable `SCHEMA.md`, pages filed outside their `<type>s/<slug>.md` location. The script exits 1 while any blocking finding remains.
- **warn** — orphan pages, contested pages, source drift (sha256 mismatch), off-taxonomy tags, invalid enum or date values, pages missing from the index, missing expected type folder on disk, verbatim-boilerplate mismatches against the canonical references, `[[wikilink]]` references that should be standard markdown links, `[^footnote]` references and definitions that should be inline standard-markdown links.
- **info** — markdown style nits, oversized pages (>200 lines), low-confidence single-source pages, unused taxonomy tags, taxonomy-style drift in SCHEMA.md (emphasis labels, non-`-` bullet markers, soft-wrap continuations), deprecated body `## Sources` sections, log over 500 entries.

## Iteration loop

Run, fix highest severity, re-run. Repeat until the script exits 0 or only acceptable info-level findings remain. Append the outcome to `log.md`:

```text
## [YYYY-MM-DD] lint | N blocking, N warn, N info
```

If a check is wrong for the situation (e.g., a deliberately oversized synthesis page), don't silence by editing the script — note the rationale on the page or in `SCHEMA.md` and accept the info-level finding. The script surfaces, doesn't enforce.
