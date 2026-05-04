# Lint Check Matrix

Reference for `scripts/lint.py` — what each check catches and which severity bucket it lands in.

| Bucket | Checks |
| --- | --- |
| schema | `SCHEMA.md` present; the `## Frontmatter` section has a `yaml` block declaring `type: a \| b \| c`. The linter loads the page-type enum and derives the corresponding page directories (`<type>s`, with `-y → -ies` pluralization) from this declaration. **Blocking** when the enum cannot be extracted — type-dependent checks are skipped until the schema is fixed. |
| boilerplate | Verbatim equality of "must-stay-verbatim" regions against the canonical templates in `references/`. Each `VerbatimSlot` pairs a wiki file with a template and an extractor — the default extractor returns everything above the first `##` heading, covering the SCHEMA.md prelude (H1 + attribution paragraph) and the log.md preamble (H1 + conventions blockquote). Add another slot to enforce additional regions. **Warn** on any mismatch — the lint output is the structural source of truth for these slots, independent of agent diligence. |
| frontmatter | required fields (`title`, `created`, `updated`, `type`, `tags`, `sources`); `type` validated against the schema-loaded enum; `confidence` enum; YYYY-MM-DD date format |
| custom fields | custom (non-canonical) frontmatter keys validated against their `field: a \| b \| c` declaration in `SCHEMA.md`'s `## Frontmatter`; pages using undeclared custom keys are flagged; declared-but-unused custom fields surface as info |
| links | broken markdown links to `.md` files; orphan pages with zero inbound links |
| index | wiki pages not referenced in `index.md` |
| tags | tags used but missing from the `SCHEMA.md` taxonomy; tags in the taxonomy but unused on any page (stale tag detection) |
| stale | `updated` more than 90 days older than the newest cited source's `ingested` date |
| quality | `contested: true`; `confidence: low`; single-source pages with no confidence field set |
| drift | sha256 mismatch on files in `raw/` |
| size | pages over 200 lines |
| log | `log.md` over 500 entries (rotate to `log-YYYY.md`) |
| markdown style | bullet style (`-` only); header level skipping; trailing punctuation in headers; fenced code without language identifier; multiple consecutive blank lines; bare URLs; list-marker spacing; trailing newline (matches the `format_markdown` skill) |

## Severity buckets

- **blocking** — broken links, missing or malformed frontmatter, missing `index.md`, missing or unparseable `SCHEMA.md`. The script exits 1 while any blocking finding remains.
- **warn** — orphan pages, contested pages, source drift (sha256 mismatch), off-taxonomy tags, invalid enum or date values, pages missing from the index, verbatim-boilerplate mismatches against the canonical references.
- **info** — markdown style nits, oversized pages (>200 lines), low-confidence single-source pages, unused taxonomy tags, log over 500 entries.

## Iteration loop

Run, fix highest severity, re-run. Repeat until the script exits 0 or only acceptable info-level findings remain. Append the outcome to `log.md`:

```text
## [YYYY-MM-DD] lint | N blocking, N warn, N info
```

If a check is wrong for the situation (e.g., a deliberately oversized synthesis page), don't silence by editing the script — note the rationale on the page or in `SCHEMA.md` and accept the info-level finding. The script surfaces, doesn't enforce.
