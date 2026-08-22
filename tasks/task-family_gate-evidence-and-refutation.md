---
description: Make a task_auto_check ready verdict refutable: every clean content-lens checklist line carries the citation it rests on, and a first-round zero-issue approval passes a refute-by-default check.
scope: plugins/ai_dev
created: 2026-08-12T19:26:25
updated: 2026-08-12T20:10:35
status: ready
reported-by: Andreas Hoffmann
---

# Make the task_auto_check ready verdict refutable

## Goal

A `task_auto_check` run can tell a verified `clean` checklist line from an
asserted one, and an immediate first-call approval reaches `ready` only after its
evidence has been challenged. Two changes deliver this. Every `clean` value the
`auto_gate_task` verdict writes for a content-lens item carries the citation the
comparative reading rested on, so the verdict states a checkable claim instead of
a conclusion. A verdict that approves a task on the first gate call with no issue
surfaced sends those citations through the existing refute-by-default verifier
before the loop trusts the stamp, and a refuted citation returns the task to the
gate. `task_check` remains the only readiness authority and the only writer of
`status`.

## Context

The gate verdict records conclusions without the evidence behind them. The
`<output_contract>` in `plugins/ai_dev/agents/auto_gate_task.md` writes one
`## Checklist` line per checklist item, valued `clean` or `issue <n>`. Its
`<policy>` already demands the reading those lines stand for — the rule opening
`Walk the base <readiness_checklist> in order and in full` requires the
comparative reading per content-lens item, and its closing sentence holds that
`Existence checks` never on their own clear the content lens. The output format
records neither, so a run that searched for a symbol's presence and a run that
read the cited passage against the task's claim produce byte-identical
`clean` lines. Nothing in the verdict can be contested, and the loop in
`plugins/ai_dev/skills/task_auto_check/SKILL.md` consumes the verdict as given:
its `<gate>` step skips repair planning outright on a `ready` verdict.

The gap is observed, not hypothetical. In one batch of runs over comparable
sibling tasks, three runs stamped `ready` on the first gate call with every
checklist line `clean` and no issue raised, taking a fraction of the elapsed
time and the fewest helper calls of the batch, while the remaining runs surfaced
real issues across several rounds. Re-gating two of those three fast approvals on 2026-08-12 raised three and five
readiness issues respectively on
[wiki_base-skill-bundle-paths.md](archive/wiki_base-skill-bundle-paths.md) and
[wiki_base-skill-output-contract.md](wiki_base-skill-output-contract.md) and
returned both tasks to `checked`; both tasks are now `ready` again after repair.
The batch runs that surfaced those counts are the historical source for
the overturn eval whose fixture is a snapshot of the false first-call approval
body; the fixture no longer depends on either linked task's live body. The fast gates were not idle: each ran the full loop and
confirmed the task's existence claims correctly. What they skipped was the
comparative reading — they searched for tag presence, left the cited operation
bodies and the cited lint script unread, then recorded the Acceptance pairing
`clean`.

The depth the gate agent asks for is not enforceable on every harness.
`auto_gate_task` frontmatter carries both an `effort` and a
`model_reasoning_effort` pin, and `wiki/concepts/agent-definition-portability.md`
records which harnesses bind which of those keys under
`### Inheritance by omission, and where a pin belongs`. Where neither key binds,
the gate's reasoning depth follows whatever the harness's model router served for
that call, and the readiness verdict inherits it. Pinning a specific model is
rejected as the fix: it raises cost on every run permanently, including the
majority of runs that need no such floor.

Reasoning-trace introspection stays unavailable as a mechanism. An agent cannot
observe whether its own backend emitted extended reasoning, the orchestrating
loop receives only the helper agent's returned text, and reading a harness's
on-disk transcript is harness-specific and outside what a portable skill can
rely on. The trigger this task adds therefore reads only fields the structured
verdict already carries. The immediate-ready sentence in
`plugins/ai_dev/skills/task_auto_check/SKILL.md` that today routes a `ready`
verdict straight to `<finalize_mechanical_lint>` is pinned by
`tests/task_auto_check/script_tests/run.sh` under the `assert_contains` label
`immediate ready path finalizes lint`; this task's `<gate>` rewrite updates that
pin in place to the post-refutation wording; the `task_auto_check finalization
tag` pin in the same harness stays unchanged.

A second consumer shares both changed contracts, so each change stays additive
for it. `plugins/ai_dev/agents/auto_shaper_task.md` invokes `auto_gate_task` for
the read-side readiness dimension with the stamp withheld, and it sends its own
proposal union to `auto_verifier_task`. The citation requirement belongs to the
gate's own output contract and so holds in both invoking modes. The refutation
trigger belongs to the `task_auto_check` loop alone, because the read-side mode
writes no stamp for a refutation to protect and that agent's `<policy>` keeps
readiness promotion owned by `task_auto_check`.

## Approach

Rewrite four passages in place: three product artifacts and one script-test
pin; within the `task_auto_check` rewrite also extend `<output_contract>` for
refutation reporting; and extend the Pattern A harness under
`tests/task_auto_check/evals/` for two new immediate-ready citation evals and
the existing-ready-outcome regression.

In `plugins/ai_dev/agents/auto_gate_task.md`, rewrite the `## Checklist` line
specification inside `<output_contract>`, and the `<policy>` rule that governs
the checklist walk, so a `clean` value on a content-lens item carries the
citation its reading rested on: the artifact read plus the verbatim span that
settled the item. The existing `clean | issue <n>` vocabulary stays, gaining the
citation on the `clean` branch; an `issue <n>` line needs none, because the issue
it points at already carries its location and evidence. Keep the citation to a
pointer plus the span it turns on, and preserve the contract's existing
bound that keeps session transcripts, tool logs, and file dumps out of the
deliverable. The charter, structural, and premise items keep their current form,
since the checklist already grounds those in existence checks and the premise
line already carries its own staleness label. Require an interaction scan
checklist line in that same citation-free form, placed between the approach
fitness line and the content-lens lines in both the `<output_contract>`
`## Checklist` specification and the `<policy>` walk order. Also rewrite
`<inputs>` to admit an
optional `refuted-citation set` from the orchestrator alongside existing inputs,
and add one `<policy>` rule that consumes each entry and surfaces it as a
readiness issue in the verdict so a `ready` stamp cannot land while those entries
remain; keep the addition additive for the `auto_shaper_task` read-side call.

In `plugins/ai_dev/skills/task_auto_check/SKILL.md`, rewrite `<gate>`'s handling
of a `ready` verdict so the immediate-approval signature routes through a
refutation step before the loop trusts the stamp. The signature is the
conjunction of four fields the verdict already reports: this is the run's first
gate call, `prior_status` is `open`, `status` is `ready`, and the verdict's
`## Issues` is empty with every checklist line `clean`. On that signature, invoke
`auto_verifier_task` with the verdict's citations and the frozen intent, and
frame the question as whether each citation supports the `clean` claim it was
written for. When every citation survives, the `ready` stamp stands and the run
proceeds to `<finalize_mechanical_lint>` as it does today. When the verifier
refutes one or more citations, the loop re-invokes `auto_gate_task` with the
refuted-citation set supplied as input; the gate agent consumes that set per its
refuted-citation `<policy>` rule above and surfaces each entry as a readiness
issue in the verdict; `task_check` writes whatever status its own re-assessment
reaches; the surfaced issues enter the ordinary repair path; a subsequent gate
call never re-enters citation refutation. A refutation round counts as a round against the
existing `<loop_bounds>` cap. State the trigger's narrowness in the rule itself
so the cost stays bounded on the face of the contract: the pass fires only on a
first-call approval that surfaced nothing, which is the pattern the observed
overturns landed on, and never on a verdict that raised issues or on a `ready`
reached after repair rounds, where `prior_status` is already `checked`.
Also rewrite `<output_contract>` in the same file so the loop report names
whether the immediate-ready refutation trigger fired, whether each citation
`survived` or was `refuted`, and whether the `ready` stamp stood or the run
returned to the gate.

In `tests/task_auto_check/script_tests/run.sh`, rewrite the `assert_contains`
needle labeled `immediate ready path finalizes lint` in place to match the
post-refutation `<gate>` wording; leave the `task_auto_check finalization tag`
pin unchanged.

In `plugins/ai_dev/agents/auto_verifier_task.md`, rewrite `<role>`, `<objective>`,
and `<inputs>` in place so a gate-citation-set call is a first-class mode beside
the existing proposal-union mode. `<inputs>` admits the gate-citation set
alongside the reviewer proposals it takes today. Keep one `<policy>` rule
applying its standing `Reject by default.` stance to a citation: keep a `clean`
claim only when the cited span, read in place, settles the checklist item it was
written for, and refute it when the span is absent, says something other than the
claim, or establishes only an existence fact for an item the gate's own contract
holds that existence checks cannot clear. Rewrite the unassessable rule so a
citation-only call with a readable citation set is assessable and does not fail
for lack of proposals. Add an additive `<output_contract>` citation-mode branch
that returns each citation as `survived` or `refuted` with a reason, and leave
the proposal-edit sections of `<output_contract>` (`## Approved edits` /
`## Rejections and routes`) intact so the `auto_shaper_task` whole-tree path
keeps its current contract, stated once.

The verifier's refutation judges the evidence behind a `clean` claim and never
re-decides readiness. Preserving that boundary is a constraint on the wording of
all three product-artifact edits: `<single_gate>` in the loop holds that
`task_check` is the only gate, that the loop computes no second readiness score,
and that it does not override the stamp, and the gate agent's `<policy>`
separately forbids defining a second readiness bar, score, rubric, or severity
system. A demotion therefore happens only as the outcome of a fresh `task_check`
gate call, never as a status written by the loop or the verifier.

Extend the Pattern A harness under `tests/task_auto_check/evals/` with two new
eval ids — `immediate_ready_citations_survive` and
`immediate_ready_citations_overturn` — each with its fixture under
`evals/fixtures/`, an `evals.json` entry, and matching `stage.sh` and
`grade.sh` arms. Re-run the existing evals in that suite that exercise a
`ready` outcome so the trigger leaves a repair-path `ready` on its current
route.

**Out of scope:**

- Pinning a model, an effort level, or a reasoning depth on any skill or agent in the family, per the rejection recorded in `## Context`.
- Editing the base `<readiness_checklist>` in `plugins/ai_dev/skills/task/SKILL.md`; this task changes how a verdict evidences its walk of that checklist, not the checklist itself.
- Adding the refutation trigger to the read-side gate path in `plugins/ai_dev/agents/auto_shaper_task.md`, which writes no stamp.

## Acceptance

1. `plugins/ai_dev/agents/auto_gate_task.md` requires a citation on every `clean`
   content-lens checklist line, in both the `<output_contract>` `## Checklist`
   specification and the `<policy>` rule governing the checklist walk, and names
   the citation's two parts: the artifact read and the verbatim span that settled
   the item. The prior bare `clean | issue <n>` specification is superseded rather
   than joined by a second one: searching the file for the checklist line
   vocabulary returns one canonical statement of the format. The same file's
   `<inputs>` admits the optional refuted-citation set, and its `<policy>`
   consumes each entry and surfaces it as a readiness issue so a `ready` stamp
   cannot land while those entries remain; the addition is additive for
   `auto_shaper_task`. Searching the file for that input and that consume rule
   returns one canonical statement of each.
2. That same file keeps its charter, structural, and premise checklist lines in
   their current form, requires an interaction scan checklist line in that same
   citation-free form between the approach fitness line and the content-lens
   lines in both the `<output_contract>` `## Checklist` specification and the
   `<policy>` walk order — searching the file for that placement returns one
   canonical statement of it — keeps `issue <n>` lines free of any citation
   requirement, and keeps the `<output_contract>` bound that holds session
   transcripts, tool logs, and file dumps out of the deliverable.
3. `plugins/ai_dev/skills/task_auto_check/SKILL.md` states the refutation trigger
   as the conjunction of the four named verdict fields — first gate call,
   `prior_status: open`, `status: ready`, and an empty issue list with every
   checklist line `clean` — and names `auto_verifier_task` as the agent invoked
   on it. The same statement frames the verifier question as whether each
   citation supports the `clean` claim it was written for. Searching the file
   for the trigger returns one statement of it.
4. The refutation route in that file re-invokes `<gate>` / `auto_gate_task` with
   the refuted items supplied as the refuted-citation set input, leaves the
   resulting status to `task_check`, states that a refutation round counts against
   the existing `<loop_bounds>` cap, and states that a subsequent gate call never
   re-enters citation refutation. No passage added by this task writes `status`,
   defines a readiness score or severity system, or overrides a stamp; the
   `<single_gate>` rule stands unedited.
5. The rewritten `<gate>` in `plugins/ai_dev/skills/task_auto_check/SKILL.md`
   states that when every citation survives refutation, the `ready` stamp stands
   and the run proceeds to `<finalize_mechanical_lint>`. Searching the file for
   that survive path returns one canonical statement of it.
6. `plugins/ai_dev/skills/task_auto_check/SKILL.md` `<output_contract>` requires
   the loop report to name whether the immediate-ready refutation trigger fired,
   whether each citation `survived` or was `refuted`, and whether the `ready`
   stamp stood or the run returned to the gate. Searching the file for that
   reporting requirement returns one canonical statement of it.
7. `plugins/ai_dev/agents/auto_verifier_task.md` admits the gate-citation input
   in `<inputs>`, carries dual-mode `<role>` / `<objective>` / `<inputs>` /
   unassessable handling for citation-set calls, carries one rule applying its
   refute-by-default stance to a citation, and carries an `<output_contract>`
   citation-mode branch that lists each citation as `survived` or `refuted` with
   a reason. The reviewer-proposal input and the proposal-edit sections of
   `<output_contract>` (`## Approved edits` / `## Rejections and routes`) survive
   the edit intact, so the `auto_shaper_task` call site keeps its current input
   contract.
8. In `tests/task_auto_check/script_tests/run.sh`, the `assert_contains` needle
   labeled `immediate ready path finalizes lint` is superseded in place to the
   post-refutation `<gate>` wording; searching that file for the prior bare
   sentence `If the verdict reports \`ready\`, skip body-repair planning for this
   round and proceed to \`<finalize_mechanical_lint>\` before reporting.` returns
   no match, and searching for the new wording returns exactly one. The
   `task_auto_check finalization tag` pin is unchanged.
9. A new eval `immediate_ready_citations_survive` in
   `tests/task_auto_check/evals/evals.json`, with its fixture under
   `evals/fixtures/immediate_ready_citations_survive/`, a matching `stage.sh`
   case arm, and a matching `grade.sh` case arm for that id, stages a task whose
   fixture frontmatter starts at `status: open` and whose body content gates
   clean on the first call, and expects the run to report the trigger firing,
   the citations surviving refutation, and the `ready` stamp standing with zero
   body edits. The eval follows the harness's existing entry shape and the
   fixture-validation step the harness runbook prescribes before a full loop
   run.
10. A second new eval `immediate_ready_citations_overturn`, with its fixture
    under `evals/fixtures/immediate_ready_citations_overturn/`, a matching
    `stage.sh` case arm, and a matching `grade.sh` case arm for that id, stages
    a fixture that is a snapshot of
    [wiki_base-skill-output-contract.md](wiki_base-skill-output-contract.md) at
    `status: open`, planted with the five readiness gaps the 2026-08-12 re-gate
    of that task surfaced (the false first-call approval body before repair).
    The fixture body carries these verbatim greppable defects:
    1. **Fixed files/lint/log triad** — `## Approach` opening requires every
       core-operation entry to state which files changed, the lint outcome, and
       the log entry written, contradicting how `<query>`, `<present_candidates>`,
       and `<capture_procedure>` actually report in the hub.
    2. **Tag-only citation rule** — `## Approach` requires citing inline report
       blocks by verbatim tag name, while only `<ingest>` has
       `<report_what_changed>`; `<query>`'s **Report the filing decision in one
       line** and `<capture_procedure>` use untagged numbered prose and
       `<lint_and_audit>` splits broad vs narrow paths without one report tag.
    3. **Weak per-operation proof** — The `## Acceptance` entry that requires
       the block to "names the report returned" for five tagged operations
       without grep-verifying each operation's report fields or explicit absence
       branches.
    4. **No placement proof** — `## Approach` places the block "at the end of
       the hub body" but the `## Acceptance` entry that searches for
       `<output_contract>` proves existence by search only, not position after
       `</pitfalls>` immediately before `</wiki>`.
    5. **Unproven positive-shape rule** — `## Approach` requires framing each
       entry as the shape returned rather than a list of omissions, with no
       Acceptance item verifying positive report framing.
    Run it three times sequentially, per the sequential-run discipline the
    harness runbook sets for repair-class evals, and record in the harness's
    results location how many of the three runs reached `ready`, and for each
    run whether a first-call zero-issue verdict occurred and whether its
    citations were refuted. The recorded measurement over that fixed denominator
    of three is the deliverable, read against the baseline in `## Context` that
    both re-gates of this material raised issues. A run that reaches `ready`
    from a first-call zero-issue verdict whose citations were never challenged
    is a defect in the trigger condition and blocks completion; a run whose
    citations are challenged and survive is a valid outcome and blocks nothing.
11. The existing evals in `tests/task_auto_check/evals/evals.json` that exercise
    a `ready` outcome still pass, confirming the trigger leaves a repair-path
    `ready` verdict on its current route.
