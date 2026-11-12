---
description: Non-English-language wiki guidance (content in-language, slugs pure ASCII), a linter warning for non-ASCII filenames, and an auto_shaper ASCII-fold remediation.
scope: plugins/knowledge_management
created: 2026-06-09T13:26:15Z
updated: 2026-11-11T20:03:05Z
status: ready
reported-by: Andreas Hoffmann
---

# Non-English-language wikis: content in-language, slugs pure ASCII, linter warns on non-ASCII filenames

## Goal

Let a wiki be authored in any language while keeping filenames portable. After this task:

- The wiki skills explicitly support **non-English content**: page bodies, headings, the `title:` frontmatter field, and content-specific metadata (tags as topic words in ASCII form) use the **language of the content**.
- **Filenames / slugs stay pure ASCII.** A content-language word is fine (`steinbildhauerei`, `lebensziele`), but non-ASCII characters are transliterated, not embedded: German `ü→ue, ö→oe, ä→ae, ß→ss`; other languages strip diacritics (`é→e`, `ñ→n`, `å→a`). The readable title keeps its native characters; only the slug is folded (e.g. title `Künstliche Evolution` → slug `kuenstliche-evolution`).
- The **linter flags any non-ASCII filename as a `warn`** (not blocking), naming the offending path and suggesting the ASCII-folded slug.
- The **`auto_shaper_wiki` agent** treats that warning as an autofixable finding: `git mv` the page to its ASCII slug and re-point every inbound reference.

This is both a small feature (new linter check + autofix + language guidance) and the fix for the gap that let the originating bug through.

## Context

### Originating incident

In a German personal-wiki session (2026-06-09, `myself` repo) a concept page was named `künstliche-evolution.md` with an **NFD-decomposed `ü`** (base `u` + combining diaeresis) in the slug. That broke two things:

- **Cross-platform git sync (macOS ↔ Linux).** macOS's `core.precomposeUnicode` behaviour and NFD/NFC mismatch meant the byte sequence of the filename differed between the machine the wiki was created on (Linux) and the editing machine (Mac). The page showed up as deleted-and-re-added rather than a stable path.
- **The wiki linter's byte comparison.** Path-matching logic drifted because the two normalization forms aren't byte-equal.

The fix applied manually in that session is the convention this task formalizes: rename to a **pure-ASCII, ASCII-folded slug** (`kuenstliche-evolution.md`), keep the readable German title `Künstliche Evolution` in frontmatter/H1, and re-point all references (9 in that case). ASCII-folding eliminates the entire NFC/NFD bug class permanently instead of repairing each instance. The user flagged the linter side as "basically a bug, handle it separately later". This is that follow-up.

### Why this is mostly formalizing an existing convention

The user's wiki **already** uses content-language ASCII slugs (`steinbildhauerei`, `lebensziele`, …). The umlaut slug was the lone off-convention file. The current scaffold half-states the rule at [template_schema.md](../plugins/knowledge_management/skills/wiki/references/template_schema.md), in the `## Conventions` "File names:" bullet. Extend that bullet to "pure ASCII; transliterate non-ASCII", with the German fold as the worked example. This scaffold is copied into every new wiki, so the convention lands per-wiki here:

> File names: lowercase, hyphens, no spaces (e.g., `transformer-architecture.md`)

It says lowercase/hyphens/no-spaces but **never says "ASCII only"**, and every example slug is English, so a non-English author has no signal that `ü` in a slug is a problem. This task closes that gap and makes the language axis explicit.

### Files involved

- [SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md): the `<folder_layout>` section (slug shape) and the `<write_or_update_pages>` authoring bullets. Add the non-English-language guidance and the content-vs-slug split.
- In [scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py), add the new check. Findings are `Issue(severity, category, path, message, line)`; severity constants `SEV_BLOCKING / SEV_WARN / SEV_INFO`; existing path-shape logic lives in `check_type_location`. Add a sibling `check_filename_ascii` (category `filename`) and register it in the run pipeline. Page filenames come from `iter_wiki_pages` and raw-sidecar filenames from `iter_raw_files`, so the check covers both iterators.
- In [references/lint_checks.md](../plugins/knowledge_management/skills/wiki/references/lint_checks.md), document the new check row in the matrix and add it to the **warn** bucket list.
- [auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md): the `<remediate>` phase, beside the existing `<fix_wrong_directory_for_declared_type>` move and under the `<use_git_mv>` constraint. Add an ASCII-fold-rename remediation for the new warning.

### Related task

- [wiki_two-pass-normalisation.md](archive/wiki_two-pass-normalisation.md) shipped the displaced-semantics routing rule as `<two_pass_remediation>` in the same `auto_shaper_wiki.md` `<remediate>` phase. The new ASCII-fold rename slots in as a fix-group alongside that shipped rule.

The rename machinery to reuse already ships in the agent rather than arriving with that task: `<fix_wrong_directory_for_declared_type>` carries the `git mv`-then-repair-inbound-links-and-index pattern, and the `<use_git_mv>` fix constraint states the history-preserving rule every rename follows. Model the ASCII-fold remediation on those two rather than inventing a parallel mechanism.

## Approach

### The rule to document (two axes)

State the split crisply in both SKILL.md and the schema scaffold:

- **Content-language, native characters**: page body prose, H1 and other headings, the `title:` frontmatter field. `title: Künstliche Evolution` is correct.
- **Pure ASCII, language-neutral structure**: the slug/filename, the page-type enum values, frontmatter field *keys*, `status`/`confidence` enum values. These are machine vocabulary.
- **Tags** sit between the two. They are content-specific topic words (so content language: `bildhauerei`, not a forced English translation) **and** the linter byte-matches them against the SCHEMA.md taxonomy, so they take the slug's fold: a content-language word written in ASCII (`koerper`, not `körper`). State that fold in SKILL.md beside the slug rule.

Give the German transliteration map explicitly (`ä→ae, ö→oe, ü→ue, ß→ss`) since a naive Unicode→ASCII fold would wrongly produce `u`/`o`/`a`; note that other languages strip diacritics instead.

### Linter check

- New `check_filename_ascii`: for every wiki page path (including `raw/<kind>/<slug>.md` sidecars, which are filenames too), if any character in the filename is non-ASCII, emit `Issue(SEV_WARN, "filename", page, …)`. Message names the path and suggests the folded slug. If feasible, additionally detect NFD-decomposed names (compare `unicodedata.normalize("NFC", name)` to the raw bytes) and call that out, since that was the exact failure mode.
- `warn`, not blocking, per the user's instruction. Rationale to record: the non-ASCII filename doesn't break the linter run itself, it breaks downstream git sync; warn keeps the wiki usable while surfacing the issue. (If the user later wants it blocking, only the severity constant changes.)

### Auto_shaper remediation

When the `filename` warning fires, the autofix mirrors the manual session fix:

1. Compute the ASCII-folded slug (German fold; diacritic-strip otherwise).
2. `git mv` the page to its ASCII slug so history is preserved as a rename.
3. Re-point every inbound reference that can name a page: markdown links, `index.md`, and `contradictions: [other-page-slug]` lists (`sources:` entries resolve only under `raw/` or a declared primary-source root, so none names a page).
4. Leave the readable title/H1 untouched; bump `updated`; record the rename in `log.md`.

The remediation lands as `<fix_non_ascii_filename>` in `<fix_moves>`, and the dispatch sentence that maps an issue category to its move gains `filename` → `<fix_non_ascii_filename>`. Because a warn-only finding leaves `lint.py` exiting 0, the clean-skip condition gains "and no live `filename` warn" at both places that state it: `<compile_issue_list>`'s "If the lint pass exits 0 and the page-first walk finds no semantic issues, the wiki is clean" sentence, and `<assess_output>`'s "If the wiki is clean (lint passes and the page-first walk finds no semantic issues)" condition, so a wiki whose only finding is that warn enters `<remediate>` instead of stopping at assessment. A non-ASCII `raw/` sidecar filename draws the same `filename` warn but takes the report-only disposition: `<raw_directory_read_only>` keeps `raw/` content and paths untouched, so name the sidecar path in the final report and apply no move, the way `log-scope` and `citation` are reported without a body edit. That warn stays live while the audit exits clean, so `<lint_clean>` gains a second carve-out beside the contested-`quality` one for a live `filename` warn on a `raw/` sidecar, scoped to `raw/` sidecars so a page's `filename` warn stays live until the rename clears it.

### Non-goals

- Do **not** rely on setting `git config core.precomposeUnicode` as the fix, because it is machine-specific and brittle. ASCII-folding is robust regardless of git config; mention the pitfall only as root-cause context.
- A ship-time migration sweep: implementing this task renames nothing in any existing wiki. Renames happen per wiki through the normal channel: the linter surfaces the `warn`, and that wiki's next `wiki_fix`/audit run applies the ASCII fold as an ordinary deterministic remediation under the agent's remediation contract (`git mv` plus re-pointed references; the readable title keeps its native characters). This differs deliberately from the log posture in [wiki_log-heading-uniqueness-and-repair.md](archive/wiki_log-heading-uniqueness-and-repair.md): log entries are append-only records, so their repair is info-level and on demand; page filenames are living structure, so the fold is warn-level and auto-applied.

## Acceptance

- SKILL.md states the content-language-vs-ASCII-slug split and explicitly covers non-English wikis, with the German fold (`ä→ae, ö→oe, ü→ue, ß→ss`) as a worked example and a note that other languages strip diacritics.
- `template_schema.md`'s "File names:" convention requires pure ASCII and shows the transliteration rule, and states in the same block that the readable `title:`/H1 keeps its native characters.
- `lint.py` emits a `warn`/`filename` finding for a page whose filename contains a non-ASCII character, names the path, and suggests the ASCII slug; NFD-decomposed names are detected if implemented.
- `lint_checks.md` documents the new check in the matrix and lists it under the warn bucket.
- `auto_shaper_wiki.md` `<remediate>` phase carries the ASCII-fold rename remediation (git mv + re-point references), coexisting with the shipped `<two_pass_remediation>` rule in the same section.
- SKILL.md states the tags rule in one sentence: tags are content-language topic words written ASCII-folded, with `körper` → `koerper` as the worked example.
- A `tests/wiki/layer1/run.sh` scenario creates at run time a page whose filename carries a non-ASCII character plus an NFD-decomposed name (never a committed non-ASCII fixture name, which `core.precomposeUnicode=true` normalizes), and asserts the `filename` warn names each path and suggests its ASCII slug.
- The same scenario stages a `raw/<kind>/<slug>.md` sidecar whose filename carries a non-ASCII character and asserts the `filename` warn fires on that sidecar path. The report-only disposition that finding takes is bounded by `auto_shaper_wiki.md`'s `<lint_clean>` criterion, which carries a `raw/`-sidecar `filename` carve-out beside the contested-`quality` one, so a wiki whose only live warn is that finding reports it and still exits clean.
- A `tests/wiki/layer2` `AS-*` scenario registered in `tests/wiki/layer2/evals.json` with its sandbox staged in `tests/wiki/layer2/setup_scenarios.sh` stages an otherwise-clean wiki whose only live finding is a non-ASCII page filename (no non-ASCII sidecar), plus the three reference classes that can name a page (`index.md`, a markdown link, a `contradictions:` entry), runs `auto_shaper_wiki`, and asserts the filename is pure ASCII, every reference resolves, and the linter is clean; it is run with `python3 tests/wiki/layer2/run.py --scenario AS-<n>`.
- The wiki test suite (`tests/wiki/run_all.sh`) passes.
