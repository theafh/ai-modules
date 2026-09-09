---
description: Pin git_review's report to a prose form contract in the <report> stage so output reads as clear sectioned prose without field-block leakage, with token-level eval checks that grade the shape.
scope: plugins/ai_dev/skills
created: 2026-09-09T10:52:05
updated: 2026-09-09T23:06:19
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Pin git_review's report to a prose form contract

## Goal

The `git_review` skill produces a review report whose depth is good but whose
shape drifts: findings render as labelled field blocks under `###`
sub-headings, decisions appear twice, cross-cutting evidence leaks into
descriptive and verdict sections, and the report grows a metadata header and a
trailing publish offer. The deliverable is a **form contract** that pins how the
report reads, so a run produces the clear, sectioned prose of the original
hand-written prompt while keeping the skill's procedure and depth. The report
stays prose under the eight H2 labels `<headings>` names, in that order; which
of those labels appear stays owned as Approach already states, a finding stays a bold one-line
title followed by prose ending in a `Fix:` sentence, a decision has one home,
cross-cutting evidence has one home, the verdict names only the shortest-path
finding, the descriptive sections stay descriptive, and the report ends at the
closing answer. The change lands in the skill body and its template, and
`tests/git_review` gains token-level checks that fail on the field-block shape
and pass on the prose shape.

## Context

Two sessions reviewing the same pull request exposed the gap. One run began from
a hand-written prompt that carried the report shape implicitly and produced
clear sectioned prose. The other invoked `git_review` directly and produced the
drifted shape. Both ran the same deployed skill on the same model, so the inputs
were equal apart from the prompt's implicit form. The evidence that localizes
the cause: neither run ever opened `references/report_template.md`. Every tool
call in both transcripts was checked for a `references/` path and none appeared.
The template holds the only worked shapes, and the skill body points at it once,
near `<template>` in `<output_contract>`, as an instruction to "Fill" it. The
model read that pointer as descriptive and never loaded the file, so the form
the template carries bound nothing.

The report contract lives in the `git_review` `SKILL.md` `<report>` stage, which
pins each section's **contents** (`<lead>`, `<headings>`, `<finding_shape>`,
`<decision_shape>`, `<closing_answer>`) and leaves the **form** to the template.
The specific drift each rule allows:

- `<finding_shape>` lists what a finding must carry (location, evidence,
  consequence, fix, who decides) with no form rule, so the listed contents
  became labelled fields under a `###` heading.
- `<finding_shape>` says a finding "names who decides" and `<decision_shape>`
  gives decisions their own section, so each decision appeared twice.
  `<treat_claims_as_input>` then pulled the author's pull-request questions into
  the decisions section, detaching it from the fixes.
- `<run_the_gates>`, `<discussion>`, `<lint_baseline>`, and
  `<treat_claims_as_input>` each say what to report and not where, so gates and
  discussion counts landed in the lead in one run and the closing in the other,
  a baseline failure landed inside the structural verdict, and verification
  narrative landed inside the descriptive sections.
- `<lead>` lists six items and `<anchor_the_report>` calls the lead a delta
  anchor, and `<draft_the_report_to_a_file>` produces a standalone file, so the
  model wrote a title line and a key-value metadata block above the prose.
- Nothing bounds the lead to the shortest-path finding, so the verdict previewed
  a second finding in full.
- `<no_nitpicking>` is an opt-in modifier with no default, and `<lint_baseline>`
  says baseline is not a finding without saying it stays out of the report, so
  the report grew a "items I checked and am not raising" list.
- Nothing ends the report at the closing answer, so the gated publishing stage
  was advertised as a trailing offer.

The report shape was always meant to be part of the contract: the origin task
[ai-dev_git-review-skill.md](../ai-dev_git-review-skill.md) records under **A human
acts on the output, so its shape is part of the contract** that the skill pins
the headings and evidence set. What it pinned was the heading set and each
section's contents; the prose form was left to the unread template. This task
closes that gap and edits the same `<report>` stage and template that task
shipped. It is distinct from the reviewer-side edit-gate change, which touches
neither the report nor its form and is owned by the sibling task named in **Out
of scope**.

The `tests/git_review` eval harness grades agent behavior with `claude -p`
workers and a deterministic `grade.sh`, whose `says` / `says_not` predicates
grep the response for verbatim tokens the report cannot paraphrase. The drift was
observed on an opus-tier model while the harness runs sonnet workers, so the form
checks must be verbatim-token assertions rather than prose judgements, or they
pass on the worker while the shape still drifts on the model in use.

## Approach

Pin the form where the model always reads it, give each drifting item one home,
and prove the checks discriminate.

Add a `<form>` rule to the `<report>` stage in the `git_review` `SKILL.md` that
states the report's shape directly, superseding the reliance on the unread
template:

- The report is prose under the headings `<headings>` names. Heading
  presence stays with `<first_review_presence>`, `<delta_presence>`, and
  `<scope_modifiers>` (`<only_what_is_open>`, `<focus_area>` /
  `<evidence_unchanged>`);
  `<form>` does not own which headings appear. The lead is one paragraph
  with no title line above it and no key-value metadata block. Findings
  and decisions use no `###` outline headings as section chrome; a `###`
  that appears only inside quoted evidence stays allowed.
- A finding is a bold one-line title that carries its location and its label
  token, then one to three prose paragraphs, ending with a `Fix:` sentence. It
  uses no `Location:` / `Label:` / `Governing document:` / `Decides:` field
  labels.
- A decision is a bold one-line title, then the named options and the suggested
  default.

Give decisions one home: rewrite `<finding_shape>` so a finding ends at its
`Fix:` sentence and, where the fix is a judgement call, carries one clause
pointing to the decisions section, and rewrite `<decision_shape>` so each
decision ties back to the finding it settles. An author's pull-request question
becomes a decision only when a fix depends on it; otherwise it earns one sentence
of context in the lead.

Give cross-cutting evidence one home: extend `<lead>` so the gates that ran and
where each ran, the discussion counts, and any unread remainder each take one
sentence in the lead and appear nowhere else, and extend `<closing_answer>` so it
carries the test merge, the counts, the checks, and one sentence of policy
context and nothing else. Bound the verdict so the lead names only the finding
that is the shortest path to yes.

Keep the descriptive sections descriptive: `What the changes do and implement`,
`What it retires`, and `What of the existing workflow changes` carry no label, no
`Fix:`, and no verification narrative; a confirmed claim is stated as the fact it
established, and a risk noticed while describing moves to its findings section.
Keep baseline and non-findings out: a baseline item is left out or gets one
clause where a reader would expect it as a finding, there is no list of items
checked and not raised, and minor items fold into the last paragraph of the
should-fix section by default; `<no_nitpicking>` keeps the one-line fold as
that default's stricter opt-in. End the report at the closing answer with no
unsolicited trailing publish or copy offer; stage notes that
`<the_report_is_the_whole_answer>`, `<draft_the_report_to_a_file>`,
`<the_note_joins_the_report>`, and `<copy_ready_block>` on request may still
follow the report in the answer. Rewrite `<copy_ready_block>` from "Offer a
copy-ready fenced markdown block with plain paths when the user prefers to post
by hand." to on-request post-report join wording so the copy-ready block joins
after the report only when asked. Rewrite `<draft_the_report_to_a_file>` so it
holds the report verbatim with no title added so the chat answer and the draft
are one text.

Rewrite the worked examples that the prose form changes in
`references/report_template.md`: rewrite the opening ("The skeleton to fill…"
through "this file for the form they take on the page") into worked-example
framing, rewrite the opening lead skeleton (`Reviewed
commit:` / `Tree state:` / `Forge layer:` / `Diff:` and the `**Approvable in
general:**` block) into the one-paragraph prose lead, rewrite `## A finding on
the page` as a bold title plus prose plus `Fix:` (not a field block), leave
`## A decision on the page`, `## The closing answer on the page`, and
`## A delta tag on the page` as-is, with the binding form rules now living in
`<report>`. Rewrite `<template>` in `<output_contract>` from its Fill-as-binding
instruction ("Fill `references/report_template.md`…") to worked-example framing
of the form `<report>` / `<form>` now pin, and keep the rest of
`<output_contract>` aligned so no passage still leaves the binding form to the
template alone. The evidence
that the template goes unread settles the placement: rules that must bind belong
in the always-read skill body, and the template illustrates them.

Add token-level form checks to `tests/git_review`. In `evals/grade.sh`, extend
the case arms for the `seeded_findings` eval (id 1) and the `clean_change` eval
(id 2) so each asserts, with `says_not`, that the response carries no
`**Location:**`, no `**Label:**`, and no `**Decides:**` field label, plus a
structure-scoped check (for example a region helper beside the existing
`headings_in_order`) that findings and decisions are not outlined under
`###` headings followed by a space — not a whole-response `says_not "### "` substring, which
fails when a finding quotes `CHARTER.md`'s `### DOES` / `### DOES NOT` —
plus a line-anchored check (for example `no_leading_h1_title` matching `^#[ ]`
and not `^##`) that the response carries no leading H1 title line — not a bare
`says_not "# "` substring, which matches inside required `##` H2 headings —
and a check that "Suggested default" occurs only after the decisions heading (a
small region helper beside the existing `headings_in_order`). In the same pass,
rewrite the `seeded_findings` dual-home "who decides" requirement in both
`evals/evals.json` and the `grade.sh` case 1 `attest` to the single-home rule.
Update those two evals' `expected_output` and `expectations` in
`evals/evals.json` to state the prose-form contract. Prove the new needles
discriminate with a committed fixture pair under `tests/git_review`: a
prose-form response the form checks pass and a field-block response the same
checks fail, exercised by a compact `script_tests` case named
`form_discrimination` that runs form-only helpers against those fixtures
(minimal sandbox only if needed) so the discrimination is a deterministic tree
artifact rather than a stochastic worker outcome.

**Out of scope:** the reviewer-side edit-gate change, owned by
[ai-dev_git-review-drop-codeowners-condition.md](../ai-dev_git-review-drop-codeowners-condition.md).
The eight headings themselves and the two-verdict structure stay as they are;
this task changes how each section reads, not which sections exist. The
evidence-collection and heading-range scripts under `scripts/` stay untouched.
Version bumps and their lockstep across the plugin and marketplace files stay
with the standing repo versioning rules, applied at commit time, and are not
steps this task file carries.

## Acceptance

- The `git_review` `SKILL.md` `<report>` stage carries a `<form>` rule stating
  the prose shape: prose under the headings `<headings>` names, with heading
  presence left to `<first_review_presence>`, `<delta_presence>`, and
  `<scope_modifiers>` (`<only_what_is_open>`, `<focus_area>` /
  `<evidence_unchanged>`),
  one-paragraph lead with no title line and no metadata block, no `###`
  outline headings as finding or decision chrome, a finding as a bold
  one-line title that carries its location and its label token, then one to
  three prose paragraphs ending with a `Fix:` sentence with no field labels,
  and a decision as a bold title plus
  options plus default. Grepping the stage returns the rule and the
  presence-ownership clause.
  `<draft_the_report_to_a_file>` holds the report verbatim with no title added;
  grepping that tag's text returns the verbatim-hold requirement.
- The template-only reliance is superseded, not merely supplemented: the
  `<template>` reference and `<output_contract>` frame the template as worked
  examples of a form the `<report>` stage now pins, and no passage still leaves
  the binding form to the template alone; grepping `references/report_template.md`
  shows the prior binding-form assignment ("The skeleton to fill" and "this file
  for the form they take on the page") gone.
- `references/report_template.md`'s worked examples show the one-paragraph prose
  lead with none of `Reviewed commit:`, `Tree state:`, `Forge layer:`,
  `Diff:`, or `**Approvable in general:**` as field labels, and a finding as
  bold-title prose ending in `Fix:` with none of `Location:`, `Label:`,
  `Governing document:`, or `Decides:` as field labels; grepping the file for
  those labels returns nothing. Grepping the file also returns the leave-as-is
  decision, closing, and delta stay tokens: `## A decision on the page`,
  `Suggested default:`, `## The closing answer on the page`, `The test merge
  against`, `## A delta tag on the page`, and `` `closed`: ``.
- `<finding_shape>` and `<decision_shape>` give a decision exactly one home: the
  finding ends at `Fix:` with an optional pointer to the decisions section, and
  the decisions section ties each decision to its finding. An author's
  pull-request question becomes a decision only when a fix depends on it;
  otherwise it earns one sentence of context in the lead; grepping the
  rewritten shapes returns that gate, and grepping the lead rule returns the
  otherwise lead-context fallback. `<lead>` and
  `<closing_answer>` name where the gates, discussion counts, unread remainder,
  and policy context appear, each in one place. The lead names only the
  shortest-path finding; grepping the lead/verdict bound returns that
  constraint. `What the changes do and implement`, `What it retires`, and
  `What of the existing workflow changes` carry no label, no `Fix:`, and no
  verification narrative; grepping those section rules returns the
  descriptive-only constraints. Baseline and non-findings stay out of the
  report (or one clause where a reader would expect a finding), with no
  checked-and-not-raised list, and minor items fold into the last should-fix
  paragraph by default; `<no_nitpicking>` keeps the one-line fold as that
  default's stricter opt-in; grepping those rules returns the default and the
  one-line opt-in. The report ends at the closing answer with no unsolicited
  trailing publish or copy offer, while stage notes that
  `<the_report_is_the_whole_answer>`, `<draft_the_report_to_a_file>`,
  `<the_note_joins_the_report>`, and `<copy_ready_block>` on request may
  still follow; grepping the end bound returns that scoped stop and the join
  allowance, grepping `<copy_ready_block>` shows the prior "Offer a copy-ready"
  wording gone and on-request join wording present, and grepping the other three
  tags returns their join wording.
- `evals/grade.sh` grades the form on the `seeded_findings` eval (id 1) and
  the `clean_change` eval (id 2): each case arm asserts via `says_not` that the
  response carries no `**Location:**`, no `**Label:**`, no
  `**Decides:**`, plus a structure-scoped check that findings and decisions
  are not outlined under `###` headings followed by a space (not a whole-response
  `says_not "### "`), plus a line-anchored check (for example `no_leading_h1_title`
  matching `^#[ ]` and not `^##`) that there is no leading H1 title — not a bare
  `says_not "# "` — and a check that "Suggested default" appears only after the
  decisions heading. Grepping the two case arms returns the new checks. The same
  pass rewrites the case 1 `attest` that still requires "who decides" to the
  single-home rule; grepping that attest shows the old dual-home string gone and
  the single-home attest present.
- `evals/evals.json` states the prose-form contract in the two evals'
  `expected_output` and `expectations`, and the `seeded_findings` who-decides
  expectation reads as the single-home rule, matching the rewritten case 1
  attest.
- A committed fixture pair proves discrimination: the new `grade.sh` form checks
  pass on a prose-form response fixture and fail on a field-block response
  fixture, run through the compact `tests/git_review/script_tests`
  `form_discrimination` case (form-only helpers against those fixtures; minimal
  sandbox only if needed) that exits 0 when the pass-fixture passes and the
  fail-fixture fails.
