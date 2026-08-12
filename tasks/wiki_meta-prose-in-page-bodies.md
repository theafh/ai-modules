---
description: Stop the auto_shaper_wiki agent (and wiki authoring contract) from inserting page-convention prose and lint-sanction prose into wiki page bodies.
scope: plugins/knowledge_management
created: 2026-05-28T19:24:26
updated: 2026-08-12T22:10:24
status: ready
reported-by: Andreas Hoffmann
---

# Forbid meta-prose in wiki page bodies

## Goal

Wiki page bodies carry only load-bearing knowledge — the entries, facts, and content the page is about. Page conventions belong in `wiki/SCHEMA.md`; lint sanctions belong in `wiki/log.md` (audit entries) or `SCHEMA.md`. After this task lands, the auto-shaper and the wiki authoring contract refuse to insert page-summary paragraphs that redefine page conventions, lint-sanction prose, or restatements of `SCHEMA.md` policies into ordinary page bodies.

## Context

This is one of a family of **generalisable refinements** to the wiki skills + `auto_shaper_wiki` agent. The trigger was a concrete friction point surfaced while auditing a real wiki, but the rule is stated globally so it applies to every user of the wiki skills, not just the originating case.

During that remediation the `auto_shaper_wiki` agent inserted two unwanted paragraphs that had to be stripped by hand:

- A page-summary paragraph defining "canon" ("Canon for an entry is…", "Each entry records…").
- A "Page size note" sanction paragraph explaining that the backlog naturally grows past the 200-line lint threshold.

The behaviour is licensed at five sites across the family — enumerate them with `rg -U --multiline 'rationale on\s+the page|rationale at the top' plugins/knowledge_management` and locate each by phrase:

- `<relint_until_clean>` in [auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md) — "note the rationale on the page's body **or** in `SCHEMA.md`".
- `<fix_oversized_page>` in the same file — "add a one-line rationale at the top" of the page.
- `<linter_is_truth_for_structure>` in the same file — "record the rationale on the page or in `SCHEMA.md`".
- `<inline_iteration_loop>` in [skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) — "note the rationale on the page or in `SCHEMA.md`".
- The iteration-loop paragraph of [lint_checks.md](../plugins/knowledge_management/skills/wiki/references/lint_checks.md) — the same sentence as SKILL.md's.

The body path gets picked because it sits closest to the lint finding, and nothing forbids inserting page-convention prose during remediation.

Carve-out: the special files `SCHEMA.md` and `index.md`, and pages of the synthesis types (`summary`, `query`, `comparison`), may carry organising prose, because that *is* their load-bearing content.

Cross-references:

- A wiki owner's memory note capturing the no-meta-in-body feedback.
- A wiki page's before/after diff where meta prose had been stripped from the body.
- A wiki `log.md` audit entry recording the cleanup.

Related tasks:

- [wiki_page-type-growth-and-anatomy.md](wiki_page-type-growth-and-anatomy.md) — this task owns dropping the body-routing wording; that task's matching step is verify-only.
- [wiki_auto-shaper-internal-contradictions.md](archive/wiki_auto-shaper-internal-contradictions.md) — finished; its exit-criterion rewrite in `<relint_until_clean>` is already live. Step 1 here drops only the remaining body-routing phrase in that block — do not re-derive the contested-warn carve-out.
- [wiki_lint-accepted-info-suppression.md](wiki_lint-accepted-info-suppression.md) — once its per-finding acceptance bullet ships, that bullet becomes the structured home for the rationale this task routes to `SCHEMA.md`'s `## Lint` section; the never-the-page-body rule is unchanged by it.

## Approach

1. **`plugins/knowledge_management/agents/auto_shaper_wiki.md`** — remove the body-routing license at all three of its sites from Context (locate by phrase, not by line number): in `<relint_until_clean>`, drop "on the page's body or"; in `<linter_is_truth_for_structure>`, drop "on the page or"; in `<fix_oversized_page>`, rewrite "add a one-line rationale at the top and accept the info-level finding" so the rationale is recorded in `SCHEMA.md`'s `## Lint` section (or the audit log entry) and the finding accepted — the page body gains no note. Sanctioned-finding rationale routes to `SCHEMA.md` (its `## Lint` section is the documented lint-config home) or `log.md` only. Re-run the Context enumeration grep afterward and confirm no body-routing match remains.
2. **Same file, `<remediate>` section** — add an explicit prohibition: when rewriting a page body, do not insert page-convention definitions, entry-anatomy explanations, canon-kind clauses, or lint-sanction prose. Lead with one short sentence naming what the page is for; stop there. Carve out the special files `SCHEMA.md`/`index.md` and the synthesis types `summary`/`query`/`comparison`.
3. **`plugins/knowledge_management/skills/wiki/SKILL.md`** — mirror the same prohibition in the authoring contract so authors invoking the skill directly inherit the rule, and drop the same body-routing license from `<inline_iteration_loop>` ("note the rationale on the page or in `SCHEMA.md`" loses "on the page or").
4. **[template_schema.md](../plugins/knowledge_management/skills/wiki/references/template_schema.md)** (the SCHEMA scaffold copied into every new wiki) — add the normative clause so each ingested wiki's `SCHEMA.md` carries the rule that the agent reads at `<read_schema>`.
5. **[lint_checks.md](../plugins/knowledge_management/skills/wiki/references/lint_checks.md)** — apply the same one-word drop to its iteration-loop sentence so the reference doc and `SKILL.md` keep saying the same thing.
6. **`plugins/knowledge_management/skills/wiki/scripts/lint.py`** — add an info-level heuristic flagging:
   - Lead paragraphs longer than two sentences on pages whose `type` is outside the synthesis set (`summary`, `query`, `comparison`); the special files stay outside the page walk already.
   - Phrases anywhere in the body matching: `Each entry records`, `Canon for an entry`, `Page size note`, `is sanctioned`, `is self-trimming`, `info-level finding`, `200-line lint threshold`, `graduate off`.

## Acceptance

- The prose files above — the agent, `SKILL.md`, `template_schema.md`, and `lint_checks.md` — carry the new prohibition, and `rg -U --multiline 'rationale on\s+the page|rationale at the top' plugins/knowledge_management` returns no body-routing license (including `<inline_iteration_loop>` in `SKILL.md`, where the phrase wraps across lines); in particular `<fix_oversized_page>` no longer instructs adding a rationale line to the page.
- `lint.py` reports the new info-level findings on both heuristics from Approach step 6: a fixture page containing any of the listed phrases, and a non-synthesis fixture page whose lead paragraph exceeds two sentences.
- Layer 2 scenario `MP-1` is registered in `tests/wiki/layer2/evals.json` and staged by `tests/wiki/layer2/setup_scenarios.sh` following the sibling `AS-*` pattern (`skill_name: wiki_fix`, out-of-band grading, top-level `passes` denominator). The fixture wiki contains an oversized `todo` page that trips the page-size info finding; after `wiki_fix`, assertions prove the page body gains no meta-prose or sanction paragraph and any accepted-finding rationale appears only in `SCHEMA.md`'s `## Lint` section or the audit log, never the page body. `MP-1` runs against the rewritten agent text as the harness resolves it and reaches the all-passes-clean result across that `passes` denominator, with the graded run recorded under `tests/wiki/layer2/workspace/`.
- `tests/wiki/run_all.sh --layer2` passes with no regression.
