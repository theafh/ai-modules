---
description: Make the raw-sidecar `source_path:` anchor unambiguous wherever it is taught and enforced — resolved from the wiki root, valid for an in-repo target outside the wiki dir via `../` — retiring the misleading "repo-relative" wording, and have the `file://` reconciliation compute the wiki-root-relative form so the automated fix cannot emit a lint-failing path.
scope: plugins/knowledge_management
created: 2026-07-22T12:32:59
updated: 2026-07-22T12:32:59
status: open
reported-by: Andreas Hoffmann
---

# Disambiguate the raw-sidecar `source_path:` anchor language, and compute the form in the `file://` reconciliation

## Goal

The wiki skill states one unambiguous rule for the raw-sidecar `source_path:`
anchor, everywhere it is taught, enforced, and reconciled: the value is a
relative path **resolved from the wiki root**, and it may point outside the
wiki directory (via `../`) as long as it stays inside the repository the wiki
ships in. The descriptor "repo-relative" — which reads as "relative to the
repo root" and misdirects exactly the in-repo-but-outside-the-wiki case — is
replaced by that explicit framing in the linter's user-facing messages, in
`references/lint_checks.md`, and in the `template_schema.md` reconciliation
bullets. And the `file://`/bare-path → `source_path:` reconciliation computes
the wiki-root-relative form (the same `os.path.relpath(resolved, wiki)` the
absolute-path safe-fix already uses) rather than leaving an author or the
`auto_shaper_wiki` agent to hand-spell it, so the automated reconciliation can
no longer emit a path the linter then rejects.

## Context

The anchor itself is settled and correct, and this task does not reopen it. The
Option-A decision in
[wiki_lint-local-path-portability.md](archive/wiki_lint-local-path-portability.md)
established that `source_path:` is a portable relative path that may sit outside
the wiki dir but must stay inside the repo, and the linter implements it by
resolving `(wiki / src)` against the wiki root, with the canonical
`../shared/spec.md` example in `template_schema.md`. This task changes wording
and one reconciliation code path, not that contract.

The defect is terminological, and it has teeth. Across
[lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py)'s
`raw-origin` and `raw-source-path` messages,
[lint_checks.md](../plugins/knowledge_management/skills/wiki/references/lint_checks.md),
and the reconciliation bullets of
[template_schema.md](../plugins/knowledge_management/skills/wiki/references/template_schema.md),
the anchor is called "repo-relative" — the Option-A task even writes
"repo-relative, resolved against the wiki root", equating the two in one
phrase. In this codebase's vocabulary "repo" names the *bound* (stay inside the
repo), not the *anchor* (the wiki root). The conflation is harmless wherever the
source lives inside the wiki (`sources:`/`raw/…`, and most `source_path:`
values), because there the wiki-root anchor and a repo-root reading coincide.
It diverges for exactly one case: an in-repo source that sits **outside** the
wiki directory, where the literal "repo-relative" reading yields `sources/…`
(which the wiki-root join rejects) while the correct portable form is
`../sources/…`.

That case is not exotic — it is the wiki-as-a-subdirectory-of-a-code-repo
layout. A wiki that lives inside a project repo is that project's shared
human/agent memory layer about the project, so it routinely references sibling
in-repo material — source snapshots, specs, code, docs — that sits outside the
wiki dir but inside the repo. `source_path:` targets of that shape are normal,
and the anchor language has to be correct for them. A real migration surfaced
it: a pre-split wiki carried into a code repo had a
`source_url: file://sources/earlier-versions/foo.md` naming a repo-root sibling
of the wiki; the correct `source_path:` was `../sources/earlier-versions/foo.md`,
but the "repo-relative" guidance (and the file's own stale SCHEMA) pointed at
`sources/earlier-versions/foo.md`, which the linter rejected as "does not
resolve on disk".

Two harms follow, the second the reason this is worth fixing rather than
tolerating:

- A human (or agent) following the message or the reconciliation prose writes
  the repo-root-relative path and the linter rejects it.
- The `file://`/bare-path → `source_path:` reconciliation shipped in
  [wiki_origin-field-contract.md](archive/wiki_origin-field-contract.md)
  (gaps 2 and 5) is **prose-guided** — "a `file://` … naming an in-repo target
  becomes a repo-relative `source_path:`" — with no code computing the form for
  the `file://` case, unlike the absolute-path safe-fix (gap 6) where
  `portable_rewrite` already returns the correct `../` form. So the now-automated
  `auto_shaper_wiki` reconciliation, applied to a `file://` naming an
  in-repo-outside-wiki target, can write a lint-failing `sources/…`. The
  behavior is correct only as long as the source happens to live inside the wiki.

The template's main-body definition already reads correctly ("a relative path
from the wiki root — it may point outside the wiki directory (for example
`../shared/spec.md`) but must stay inside the repo"); the fix is to propagate
that exact framing to the surfaces that still say "repo-relative" and to back
it with the computed rewrite.

Full edit surface: `scripts/lint.py` (the `raw-origin` and `raw-source-path`
messages, and the `file://`/bare-path reconciliation that should compute and
carry the rewrite), `references/lint_checks.md` (the `raw-origin` and
`raw-source-path` rows), `references/template_schema.md` (the reconciliation
bullets, aligned to the already-correct main body), the
[auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md)
`file://`-reconciliation move so it applies the computed form, and the
`tests/wiki/` Layer-1 fixtures/strings and a Layer-2 scenario.

## Approach

1. **Adopt one canonical phrasing and propagate it.** Take the
   `template_schema.md` main-body framing as the canonical wording — "a relative
   path resolved from the wiki root; it may point outside the wiki directory
   (via `../`) but must stay inside the repository the wiki ships in" — and
   rewrite in place every source_path-facing surface that describes the *anchor*
   as "repo-relative": the `raw-origin` `file://` and bare-path redirect
   messages and the `raw-source-path` rewrite-hint and both-fields messages in
   `lint.py`, the corresponding rows in `lint_checks.md`, and the reconciliation
   bullets in `template_schema.md`. Keep "stays inside the repo" where it states
   the *bound*; only the anchor descriptor changes. Leave the `sources:`/`raw/…`
   messages alone unless a parallel tweak reads cleaner there — `raw/` is always
   in-wiki, so no behavior rides on their wording.
2. **Compute the form in the `file://` reconciliation, don't rely on prose.**
   Where the `raw-origin` check flags a `file://` or bare-path `source_url:`
   whose value names an in-repo target, resolve it and carry the wiki-root-relative
   rewrite (`os.path.relpath(resolved, wiki)`, the helper the absolute-path
   safe-fix uses) in the message — `-> ../sources/…` — rather than an instruction
   to hand-spell a "repo-relative" path. Mirror it in the `auto_shaper_wiki`
   `file://`→`source_path:` reconciliation move so the automated fix applies the
   computed form, closing the case where an in-repo-outside-wiki target became a
   lint-failing `sources/…`. An out-of-repo target still routes to the excerpt
   rule, unchanged.
3. **Cover it in the tests.** Update the Layer-1 fixtures, strings, and comments
   that assert the old wording; add a fixture for the in-repo-outside-wiki case
   (a `file://`/bare-path or absolute target one directory above the wiki
   resolving to a repo sibling, expecting the `../…` rewrite in the warn); add or
   extend a Layer-2 `auto_shaper_wiki` scenario asserting the automated
   `file://`→`source_path:` reconciliation of an in-repo-outside-wiki source
   writes `../…` and re-lints clean; run the wiki suite green.

**Out of scope:**

- **The anchor decision.** Option A (wiki-root-anchored, repo-bounded,
  out-of-repo captured by excerpt) stands; this task only makes the language and
  the computed rewrite match it.
- **Rewriting the archived tasks.** `wiki_origin-field-contract.md` and
  `wiki_lint-local-path-portability.md` are the historical decision record and
  stay as written; only the live skill artifacts change.
- **The origin-field contract otherwise.** No change to the
  `source_url:`/`source_path:`/neither split, to origin optionality, or to any
  check beyond the wording and the computed-form fix.

## Acceptance

1. `rg "repo-relative"` over the source_path-facing surfaces (the `raw-origin`
   and `raw-source-path` messages in `lint.py`, those two rows in
   `lint_checks.md`, and the reconciliation bullets in `template_schema.md`)
   returns no occurrence that describes the **anchor**; each instead states the
   path is resolved from the wiki root and may reach an in-repo target outside
   the wiki dir via `../`. Occurrences that state the repo **bound** ("must stay
   inside the repo") may remain.
2. **Layer-1 fixture.** A raw sidecar whose `source_url:` is a `file://` (or
   bare-path) value naming an in-repo file one directory outside the wiki (a repo
   sibling) yields a warn whose message carries the computed `../…`
   wiki-root-relative rewrite, not a bare "repo-relative" instruction; an
   in-wiki-adjacent target still yields its correct form; an out-of-repo target
   still routes to the excerpt rule.
3. **Layer-2 `auto_shaper_wiki` scenario.** Reconciling a `file://` `source_url:`
   that names an in-repo source outside the wiki dir writes
   `source_path: ../…` (the computed wiki-root-relative form), and re-linting the
   result is clean — the automated reconciliation no longer produces a path the
   linter rejects.
4. The `template_schema.md` reconciliation bullets read consistently with its
   own main-body anchor definition, and the `tests/wiki/` suite passes.
