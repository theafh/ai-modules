---
description: Replace the query workflow's file-valuable-answers judgment call with a deterministic filing default, explicit first-synthesis handling, and a mandatory one-line filed-or-not report.
scope: plugins/knowledge_management
created: 2026-06-11T17:46:27
updated: 2026-07-30T11:23:55
status: ready
reported-by: Andreas Hoffmann
---

# Deterministic query-page filing decision

## Goal

The wiki query workflow's decision to persist an answer becomes
deterministic and observable: identical query sessions produce identical
filing behaviour, and every query session states its filing decision to the
user in one line. This is the general behaviour definition whose absence
caused the motivating incidents (see Context), not a point-fix for one
session.

## Context

`plugins/knowledge_management/skills/wiki/SKILL.md`, `<query>` section,
the **File valuable answers back** step is the entire current trigger: "File valuable answers back if the
answer would be painful to re-derive (multi-source synthesis, structured
comparison, novel reasoning) … Skip trivial lookups." It names no default,
no threshold, no user-visible decision, and no handling for an answer the
user has not yet validated. The model fills that gap with invented policy.

Motivating incidents (2026-06-09, a personal German-language wiki — three
sessions asked the same multi-page question within 48 hours and produced
three different behaviours):

1. One session synthesized from 16 pages, then asked the user whether to
   file the synthesis; the conversation moved on, the question dangled,
   nothing was filed.
2. One session answered and ended — filing never mentioned.
3. One session declined to file with an invented criterion ("first
   synthesis, user reaction pending", citing a perceived wiki norm of
   persisting only after a correction round) and wrote only a log entry.

Each behaviour is a defensible reading of the **File valuable answers back** step. Corroboration that the
trigger under-fires generally: across the user's five active wikis,
`queries/` holds one page in total, and an unrelated wiki's log likewise
records a 2026-06-04 query entry stating "not filed as a query page".

Anchors in the same SKILL.md that this task builds on:

- `<page_anatomy>`: the query page anatomy already carries a "Confidence
  and caveats" section — the natural carrier for unvalidated-first-synthesis
  status.
- `<adopt_when_user_named_the_path>`: the house pattern for a mandatory
  one-line surfaced decision ("silence is the failure mode this surface
  report exists to prevent") — reuse its shape.
- `<summary_vs_query>` and `<page_types>`: the *type* pick (queries/ vs
  summaries/ vs comparisons/) stays as specified there; this task fixes
  only *whether and when* to persist, and how the decision is surfaced.

Related task:
[wiki_log-entries-only-on-changes](archive/wiki_log-entries-only-on-changes.md) —
co-edited the same `<query>` numbered workflow and has shipped, so its
changes-only log rule is already in place and the one-line report defined
here is now the only trace an unfiled query leaves.

## Approach

Rewrite the `<query>` **File valuable answers back** step (and add the closing report step) in place:

1. **Deterministic default.** When the synthesized answer draws on three or
   more wiki pages, or contains cross-page reasoning present on no single
   page, filing the answer back is the default action. A direct lookup
   restating one or two pages skips filing. Skipping a
   default-filing-worthy answer requires a concrete stated reason in the
   **Mandatory one-line decision report** below.
2. **First-synthesis handling.** Pending user validation is explicitly
   named as not a skip reason: file the first synthesis and record its
   unvalidated status under the page's "Confidence and caveats" section;
   later user corrections flow through the normal page-update path. This
   replaces both observed workarounds (asking and dangling; declining and
   logging).
3. **Mandatory one-line decision report.** Every query session ends its
   answer with one line, on either branch: filed → name the created page
   path; skipped → name the reason. The report replaces asking the user
   before filing — the user corrects in the next turn if the call was
   wrong, mirroring the `<adopt_when_user_named_the_path>` pattern.

Keep the rewrite inside the `<query>` section, positive and
action-oriented per the repo's authoring conventions. The "painful to
re-derive" rationale may stay as motivation, but the operative trigger is
the page-count/novel-reasoning criterion above.

## Acceptance

1. The `<query>` section states exactly one filing rule, carrying an
   explicit default action tied to the multi-page / novel-reasoning
   criterion and a stated-reason requirement for skips; the readiness test
   is that two implementers reading only that section reach the same
   filed-or-not decision for a 12-page synthesis (filed) and a single-page
   lookup (skipped).
2. The section names pending user validation as not a skip reason and
   routes unvalidated status into the query page's "Confidence and
   caveats" section.
3. The section mandates the one-line filed-or-not report in chat on both
   branches, and contains no instruction to ask the user before filing.
4. A behaviour-layer scenario in the wiki test harness stages a fixture
   wiki and runs two query evals: a question requiring synthesis across 3+
   pages yields a `queries/` page conforming to `<page_anatomy>` plus the
   one-line filed report; a single-page lookup yields no new page plus the
   one-line skip report with a reason. Both scenarios fail against the
   current skill text and pass with the rewrite; record the pass/fail per
   eval run in the harness's standard result format.
