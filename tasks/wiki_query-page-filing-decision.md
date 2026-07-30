---
description: Replace the query workflow's file-valuable-answers judgment call with a deterministic filing default, explicit first-synthesis handling, and a mandatory one-line filed-or-not report.
scope: plugins/knowledge_management
created: 2026-06-11T17:46:27
updated: 2026-07-30T19:05:49
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

- `<page_anatomy>` plus `references/template_schema.md`: "Confidence and
  caveats" is defined on the query row alone — the summary row carries
  "Open threads", the comparison row "Verdict / synthesis" — while the
  schema's `## Frontmatter` block declares `confidence:` as an optional
  quality signal available on every page type. The **First-synthesis
  handling** step in `## Approach` names the carrier the filing step writes.
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
here is now the only trace an unfiled query leaves. That sibling also
shipped the skip-branch eval `answer-only-query-writes-no-log-entry`
(`L2-6`) in the wiki behaviour-layer harness under `tests/wiki/layer2/`,
which the standing repo rules keep local-only and uncommitted: it stages a
populated fixture wiki, asks a single-page lookup, and already asserts no
page under `queries/`, `summaries/`, or `comparisons/` plus
`files_created: none`. Its prompt constraint beginning "Treat this as the
trivial single-page lookup it is" pre-decides the skip, so the eval proves
the skip happened without proving the skill's rule produced it.

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
   unvalidated status in the type-neutral `confidence:` frontmatter
   field, set to `medium` while validation is pending — a value the
   `**Confidence**` bullet in `<write_or_update_pages>` leaves open,
   since that bullet reserves only `high` for multi-source support. The
   record therefore lands on whichever page type the type rule picks,
   and a page filed as `query` carries the same status in its
   "Confidence and caveats" section. A later user correction is an
   ordinary page update on the existing `<write_or_update_pages>` path,
   which this task leaves as it stands. This replaces both observed
   workarounds (asking and dangling; declining and logging).
3. **Mandatory one-line decision report.** Every query session ends its
   answer with one line, on either branch: filed → name the created page
   path; skipped → name the reason. The report replaces asking the user
   before filing — the user corrects in the next turn if the call was
   wrong, mirroring the `<adopt_when_user_named_the_path>` pattern.

Keep the rewrite inside the `<query>` section, positive and
action-oriented per the repo's authoring conventions. The "painful to
re-derive" rationale may stay as motivation, but the operative trigger is
the page-count/novel-reasoning criterion above.

Shape the 3+-page synthesis eval fixture as a question where "the question
shape itself is what makes the answer valuable" per `<summary_vs_query>`,
so the untouched type rule picks `queries/` for it and the eval's only
variable is the filing decision this task changes.

Both eval scenarios observe the filing decision through a declared report
field rather than through the agent's chat answer:
`tests/wiki/layer2/build_prompt.py` tells the agent "The report block IS
your final answer", so a pass's `response.txt` may carry that block alone
and a `response_text_*` assertion cannot see the one-line report
reliably. Give each scenario an `extra_report_fields` entry
`filing_decision: <the one-line filed-or-not report, verbatim>` plus the
matching `extra_report_field_doc` line — that declaration is what
registers the key with the report parser in `grade.py`.

## Acceptance

1. The `<query>` section states exactly one filing rule, carrying an
   explicit default action tied to the multi-page / novel-reasoning
   criterion and a stated-reason requirement for skips; the readiness test
   is that two implementers reading only that section reach the same
   filed-or-not decision for a 12-page synthesis (filed) and a single-page
   lookup (skipped).
2. The section names pending user validation as not a skip reason and
   routes unvalidated status into the type-neutral `confidence:`
   frontmatter field with the value `medium`, on whichever page type the
   type rule files, with `query` the only type also sent to a "Confidence
   and caveats" body section.
3. The section mandates the one-line filed-or-not report in chat on both
   branches, and contains no instruction to ask the user before filing.
4. The shipped `answer-only-query-writes-no-log-entry` eval carries the
   skip branch, superseded in place rather than duplicated by a second
   single-page-lookup scenario: its prompt constraint beginning "Treat
   this as the trivial single-page lookup it is" is gone and its
   `user_request` drops the trailing sentence "Just answer the question
   from what the wiki already says.", leaving the prompt with no filing
   instruction while the surviving "Do not fetch from the web and do not
   invent domain facts" constraint keeps the answer scoped to the wiki's
   own pages. Beside the assertions it already carries it gains one
   `report_field_matches` assertion on `filing_decision` requiring both a
   skip verdict and the page-count reason for it, its pattern loose
   enough to accept the phrasings a correct skip report takes.
5. A new behaviour-layer scenario in the same harness stages a fixture
   wiki and asks the question-shaped 3+-page synthesis query `## Approach`
   specifies. It carries one `glob_file_contains` assertion per section of
   the `<page_anatomy>` query row over its `queries/*.md` glob — the
   question verbatim as the page title, a synthesized answer carrying at
   least one relative `.md` cross-link, and a "Confidence and caveats"
   section — plus one `report_field_matches` assertion on
   `filing_decision` matching a `queries/<slug>.md` path shape, since the
   agent picks the slug and a fixed-path check cannot name it.
6. Both scenarios are measured baseline-first: run each against the
   current skill text before the rewrite lands, then against the rewrite,
   at least five passes per side through the harness's `--passes` override
   (its default is two), matching the per-side pass-rate convention the
   `answer-only-query-writes-no-log-entry` eval's own description already
   states. The recorded deliverable is each scenario's per-side pass rate
   over that fixed five-pass denominator, captured in the harness's
   `grading_summary.json` (per-pass verdicts) and `benchmark.json`
   (per-assertion rates). The rewrite counts as working when each scenario
   reaches 5/5 on the rewrite side while its baseline side stays at or
   below 1/5. When either side misses that bar, report both measured rates
   with the diverging assertions and the observed behaviour, and leave the
   disposition to the user rather than re-running for a better draw.
