---
description: Non-English-language wiki guidance (content in-language, slugs pure ASCII), a linter warning for non-ASCII filenames, and an auto_shaper ASCII-fold remediation.
scope: plugins/knowledge_management
created: 2026-06-09T15:26:15
updated: 2026-09-05T21:26:04
status: open
reported-by: Andreas Hoffmann
---

# Non-English-language wikis: content in-language, slugs pure ASCII, linter warns on non-ASCII filenames

## Goal

Let a wiki be authored in any language while keeping filenames portable. After this task:

- The wiki skills explicitly support **non-English content**: page bodies, headings, the `title:` frontmatter field, and content-specific metadata (tags as topic words) use the **language of the content**.
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

The user's wiki **already** uses content-language ASCII slugs (`steinbildhauerei`, `lebensziele`, …). The umlaut slug was the lone off-convention file. The current scaffold half-states the rule at [template_schema.md](../plugins/knowledge_management/skills/wiki/references/template_schema.md):

> File names: lowercase, hyphens, no spaces (e.g., `transformer-architecture.md`)

It says lowercase/hyphens/no-spaces but **never says "ASCII only"**, and every example slug is English, so a non-English author has no signal that `ü` in a slug is a problem. This task closes that gap and makes the language axis explicit.

### Files involved

- [SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md): the `<folder_layout>` section (slug shape) and the authoring-conventions area. Add the non-English-language guidance and the content-vs-slug split.
- [template_schema.md](../plugins/knowledge_management/skills/wiki/references/template_schema.md) holds the `## Conventions` "File names:" bullet. Extend to "pure ASCII; transliterate non-ASCII" with the German fold as the worked example. This scaffold is copied into every new wiki, so the convention lands per-wiki here.
- In [scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py), add the new check. Findings are `Issue(severity, bucket, page, message)`; severity constants `SEV_BLOCKING / SEV_WARN / SEV_INFO`; existing path-shape logic lives in `check_type_location`. Add a sibling `check_filename_ascii` (bucket `filename`) and register it in the run pipeline.
- In [references/lint_checks.md](../plugins/knowledge_management/skills/wiki/references/lint_checks.md), document the new check row in the matrix and add it to the **warn** bucket list.
- [auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md): the `<remediate>` phase, beside the existing `<fix_wrong_directory_for_declared_type>` move and under the `<use_git_mv>` constraint. Add an ASCII-fold-rename remediation for the new warning.

### Related task

- [wiki_two-pass-normalisation.md](archive/wiki_two-pass-normalisation.md) co-edits the same `auto_shaper_wiki.md` `<remediate>` phase. Coordinate so the new ASCII-fold rename slots in as a fix-group alongside the displaced-semantics routing rule rather than conflicting with it.

The rename machinery to reuse already ships in the agent rather than arriving with that task: `<fix_wrong_directory_for_declared_type>` carries the `git mv`-then-repair-inbound-links-and-index pattern, and the `<use_git_mv>` fix constraint states the history-preserving rule every rename follows. Model the ASCII-fold remediation on those two rather than inventing a parallel mechanism.

## Approach

### The rule to document (two axes)

State the split crisply in both SKILL.md and the schema scaffold:

- **Content-language, native characters**: page body prose, H1 and other headings, the `title:` frontmatter field. `title: Künstliche Evolution` is correct.
- **Pure ASCII, language-neutral structure**: the slug/filename, the page-type enum values, frontmatter field *keys*, `status`/`confidence` enum values. These are machine vocabulary.
- **Tags** sit between the two. They are content-specific topic words (so content language: `bildhauerei`, not a forced English translation) **but** the linter byte-matches them against the SCHEMA.md taxonomy, so they share the slug's NFC/NFD risk. **Recommendation: fold tags to ASCII too** (`koerper`, not `körper`), a content-language word in ASCII. See the open decision below.

Give the German transliteration map explicitly (`ä→ae, ö→oe, ü→ue, ß→ss`) since a naive Unicode→ASCII fold would wrongly produce `u`/`o`/`a`; note that other languages strip diacritics instead.

### Linter check

- New `check_filename_ascii`: for every wiki page path (including `raw/<kind>/<slug>.md` sidecars, which are filenames too), if any character in the filename is non-ASCII, emit `Issue(SEV_WARN, "filename", page, …)`. Message names the path and suggests the folded slug. If feasible, additionally detect NFD-decomposed names (compare `unicodedata.normalize("NFC", name)` to the raw bytes) and call that out, since that was the exact failure mode.
- `warn`, not blocking, per the user's instruction. Rationale to record: the non-ASCII filename doesn't break the linter run itself, it breaks downstream git sync; warn keeps the wiki usable while surfacing the issue. (If the user later wants it blocking, only the severity constant changes.)

### Auto_shaper remediation

When the `filename` warning fires, the autofix mirrors the manual session fix:

1. Compute the ASCII-folded slug (German fold; diacritic-strip otherwise).
2. `git mv` the page (or sidecar) to the new path so history is preserved as a rename.
3. Re-point every inbound reference: markdown links, `sources:` frontmatter entries, `index.md`, and `contradictions: [other-page-slug]` lists.
4. Leave the readable title/H1 untouched; bump `updated`; record the rename in `log.md`.

### Open decision to surface to the user (do not silently pick)

**Should tags be ASCII-folded, or kept with native characters?** The user's instruction said tags use the content language but did not pin down ASCII. Default for this task: **ASCII-fold tags** (they are byte-matched identifiers, same risk class as slugs). The alternative, native-character tags, is viable only if the linter's tag↔taxonomy matching NFC-normalizes both sides first; otherwise the original bug reappears in tag matching. Implement the ASCII default unless the user chooses native-character tags, in which case add the NFC-normalization to the tag check instead.

### Non-goals

- Do **not** rely on setting `git config core.precomposeUnicode` as the fix, because it is machine-specific and brittle. ASCII-folding is robust regardless of git config; mention the pitfall only as root-cause context.
- A ship-time migration sweep: implementing this task renames nothing in any existing wiki. Renames happen per wiki through the normal channel: the linter surfaces the `warn`, and that wiki's next `wiki_fix`/audit run applies the ASCII fold as an ordinary deterministic remediation under the agent's remediation contract (`git mv` plus re-pointed references; the readable title keeps its native characters). This differs deliberately from the log posture in [wiki_log-heading-uniqueness-and-repair.md](archive/wiki_log-heading-uniqueness-and-repair.md): log entries are append-only records, so their repair is info-level and on demand; page filenames are living structure, so the fold is warn-level and auto-applied.

## Acceptance

- SKILL.md states the content-language-vs-ASCII-slug split and explicitly covers non-English wikis, with the German fold (`ä→ae, ö→oe, ü→ue, ß→ss`) as a worked example and a note that other languages strip diacritics.
- `template_schema.md`'s "File names:" convention requires pure ASCII and shows the transliteration rule.
- `lint.py` emits a `warn`/`filename` finding for a page whose filename contains a non-ASCII character, names the path, and suggests the ASCII slug; NFD-decomposed names are detected if implemented.
- `lint_checks.md` documents the new check in the matrix and lists it under the warn bucket.
- `auto_shaper_wiki.md` `<remediate>` phase carries the ASCII-fold rename remediation (git mv + re-point references), coordinated with the [wiki_two-pass-normalisation.md](archive/wiki_two-pass-normalisation.md) edits to the same section.
- The tags open decision is reflected: either tags fold to ASCII (default) or the tag check NFC-normalizes both sides, per the user's call.
- A wiki linter fixture with a non-ASCII / NFD filename produces the new warning; after the auto_shaper fix the filename is pure ASCII, references resolve, and the linter is clean.
- The wiki test suite (`tests/wiki/run_all.sh`) passes.
