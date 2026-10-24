---
description: Make task_fix and task_auto_check regroup a live task's scattered account of one target per repeated-link warn, gather by account in the base protocol, and count archived findings only.
scope: plugins/ai_dev
created: 2026-09-17T19:54:01
updated: 2026-09-18T08:49:13
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Give the repeated-link finding writing owners so task_fix and task_auto_check regroup live tasks

## Goal

A `repeated-link` lint finding on a live task has an agent that acts on it. When
`task_fix` runs inline over the tree, or `task_auto_check` runs over one task, the
agent reads the body's whole account of the counted target, gathers an account that
two or more sections carry into the one section that owns it, keeps each surviving
link where its site earns it, and reports one line per finding with its disposition.
A finding whose only gathering would change what the task is for, or that reveals
the body grew into separate concerns, is surfaced with that reason. A finding on an
archived task is reported as part of a count and the archived body stays as archived.
The user-visible outcome is that a backlog sweep no longer ends with the finding
handed back to the user, and a sweep that finds the material already gathered says so
per finding rather than in one summary sentence.

## Context

The base `task` skill ships the detector, the grouping rule, and the react protocol
that [task-family_cross-link-hygiene](task-family_cross-link-hygiene.md)
delivered. That task excluded auto-regrouping and a migration sweep on the ground
that regrouping is a prose judgement the author owns, and assumed live tasks would
converge as they pass through readiness and repair. The convergence path was never
wired. The base `<lint>` mechanically fixable set omits `repeated-link`. The
`task_fix` `<surface_for_review>` entry led by **Repeated-link findings** takes the
protocol's read-only path and keeps the finding human-owned on the escalated path
too, so `auto_shaper_task` leaves it as well. The `task_auto_check`
`<mechanical_lint_boundary>` applies only the mechanically fixable set. The
`<readiness_checklist>` carries no grouping item, so `task_check` never raises it.
The `<archive>` workflow's file-scoped close-out lint does not require it cleared.
The protocol's own sentence, "A writing surface applies the regroup in its own edit
round", hands the work to a surface it never names. In a sweep on a sibling
repository's backlog on 2026-09-16, `task_finish` deferred the live findings to
`task_fix` as body reshaping, `task_fix` deferred them to the user as a prose
judgement, and only a direct instruction produced the regroup.

Two wording gaps compound the ownership gap. The protocol's decision step, "Decide
whether they state one relationship in several places or name a distinct role each
time", tests the two link sites, while the grouping rule's lead sentence, "Gather
what the body says about one link target into one place", is about the material. The
same sweep applied the site test, kept every repeat under the grouping rule's
carve-out for an edit site named in Approach that Context introduced, and acted on
the one remaining finding by downgrading a link to plain text. Re-read against the
material, three of those bodies narrated one handoff in up to four sections, and the
regroup that followed left every link count where it was. The linter's floor and
message stay right for this: a target linked twice was exactly where the scattered
account sat, and the linter's docstring already frames the count as a hint about the
body's order rather than an instruction to drop a link.

The change reaches the base `task` skill's `<lint>` protocol, the `task_fix`
remediate step, surface-for-review entry, and output contract, the `task_auto_check`
repair routing, `<verification_standard>`, and applied-edit `issue:` report fields,
the `auto_reviewer_task`, `auto_verifier_task`, and `auto_shaper_task` agents, and
their tests. The standing repo rules place a rule the whole family shares once in the base
skill. The autonomous-loop design in `task_auto_check` and `auto_shaper_task` keeps
body repairs verifier-approved with one writer per run, and the in-repo wiki's
automation concept keeps genuine judgement calls with the human; this task fits both
by applying only the meaning-preserving regroup autonomously and surfacing the rest.
The live `task-family_repo-wide-link-integrity` task widens which files the linter
reads and states that the repeated-link warn keeps its per-file behaviour, which this
task leaves intact.

## Approach

Deliver the protocol reword and the owners it names as one change, since each is
meaningless without the other.

**a. Reword the react protocol in place.** In the base `task` skill's `<lint>`
section, the paragraph led by **Repeated-link react protocol.** becomes one procedure.
Read every mention of the counted target in the body, linked or plain. Where two or
more sections carry the same account of the target (the same relationship, fact, or
handoff), gather that account into the section that owns it by the `<body>` anatomy:
Context for background and current state, Approach for the edit or the mechanism, the
`**Out of scope:**` block for a deferral. Leave the other sites a one-clause pointer
or nothing, and keep the meaning of `## Goal` and the Acceptance contract unchanged,
moving a sentence out of Goal only when Goal still states what the task delivers
without it. Then keep each surviving link where its site earns it on its own under
the grouping rule's carve-outs. The finding is resolved when the body's account sits
in one place; the surviving link count is not the measure, and a count that stays
above the floor after the regroup is reported as kept because each site earns its
link. Keep the existing route to the split guidance when gathering reveals separate
concerns. Replace the two sentences about an unnamed writing surface and read-only
surface with the named owners: `task_fix` on its inline path, `auto_shaper_task` when
`task_fix` escalates, `task_auto_check` through its repair path, and the hub's
`<update>` workflow when it edits a body apply the regroup and bump `updated` once
with their edit round; `task_check`, `task_audit`, `task_explain`, `task_select`,
and `task_finish` report the finding with the sections that link the target. State in the same paragraph that
the writing owners regroup live tasks under `tasks/`, and that a finding on an
archived task is reported as part of a count with the archived body left as archived.
Keep the mechanically fixable set's omission of `repeated-link`, with its reason
reworded so the react protocol is named as the finding's owner.

**b. Make `task_fix` a writing owner on its inline path.** In its `<workflow>`
**Remediate.** step, extend the sentence that names the advisory repairs (the
unambiguous reverse-duplicate removal and the meaning-preserving negation reframe)
with the meaning-preserving regroup under the base protocol, applied to each live
`repeated-link` finding. Rewrite the `<surface_for_review>` entry led by
**Repeated-link findings** so it covers only the surfaced class: a regroup whose only
gathering would change the meaning of `## Goal` or the Acceptance contract, or that
reveals separate concerns and routes to the split guidance. Drop its clause keeping
the finding human-owned on the escalated path, so escalation hands the finding to
`auto_shaper_task` like the other body repairs. Rewrite the `<output_contract>` so
the report carries one shared per-finding disposition line shape for each live
finding—file, target, linking sections, and disposition (regrouped, kept because
each site earns its link, or surfaced with the reason)—plus one archived-count
line, with regrouped findings counted in `N issues resolved` and surfaced ones in
`K flagged for review`.

**c. Route the finding through the `task_auto_check` repair path.** Add a Grouping
advocate to the `auto_reviewer_task` `<standing_stances>` list citing the base
`<markdown_policy>` grouping rule and the react protocol. Widen `auto_reviewer_task`
`<role>`, the grounding `<policy>` rule that today requires a `task_check` issue,
`<inputs>`, and the output-contract `issue:` field so a lint-originated
`repeated-link` finding is an admissible issue class beside a `task_check` issue or
`task_fix` judgement-call label, with no remaining only-`task_check` grounding. In
`task_auto_check`, run the base linter over the target during `<freeze>` alongside
the snapshot, keep the target's `repeated-link` findings in loop-local state, and
map them in `<plan_repairs>` to that stance beside the gate verdict's issues, so
`auto_verifier_task` judges the proposed regroup for minimum change and frozen
intent and `<apply_repairs>` writes it in the same edit group. On every `<gate>`
path that would proceed to `<finalize_mechanical_lint>` after a `ready` verdict
without a body-repair round—including the branch that begins "When the verdict
reports `ready`, skip body-repair planning for this round", the exit when the
immediate-approval signature does not hold, and the citation-survive exit that
today proceeds to finalize "as on any other `ready` verdict"—run one repair round
for the repeated-link findings alone before finalize. Rewrite `task_auto_check`'s
`<output_contract>` so the shared per-finding disposition line shape Approach **b**
names is mandatory for each dispositioned finding on every dispositioning
path—including regroups applied through `<plan_repairs>` / `<apply_repairs>` and that
ready→finalize repair round—so grepping the skill for that shared-shape requirement
finds the rule. Keep `<mechanical_lint_boundary>` and `<finalize_mechanical_lint>`
unchanged in what they apply (only the mechanically fixable set), and filter
dispositioned `repeated-link` findings out of the finalization report's
surfaced-but-not-fixed line and the stuck/human-routed channel: regrouped findings
and findings kept because each site earns its link do not appear there; only
regroups the verifier rejected or the reviewer surfaced remain. Rewrite
`<verification_standard>` so a lint-originated repeated-link regroup is an
approvable cited-issue class beside gate-verdict issues, and keep the applied-edit
report's `issue:` field able to name that class.

**d. Let `auto_shaper_task` execute the regroup on escalation.** Rewrite its rule
that begins "Resolve these four defect kinds and no others" to five kinds, adding the
repeated-link regroup as a verifier-gated body repair the writer executes, and add
the regroup to the `## Applied fixes` grouping in its report. Rewrite its
`<remediate>` block so the serial-writer paragraph that today runs `For a split…`,
`For a scope relocation…`, `For a body-framing reframe…`, and `For a
backlog-coherence repair…` also runs `For a repeated-link regroup…`: apply the base
`task` skill's **Repeated-link react protocol** to the finding's live task, and bump
that task's `updated` once with that edit. Rewrite `auto_verifier_task`'s rule that
approves writer-executed plans for "those three kinds and no others" so it approves
split, relocation, backlog-coherence, and repeated-link regroup plans (those four
kinds and no others), keeping body-framing-reframe as a shaper defect kind outside
that writer-executed-plan list as it is today, and widen the agent's role/policy and
output-contract `issue:` field typing so the lint-originated repeated-link class is
namable for both the `task_auto_check` repair path and the shaper path.

**e. Prove the behaviour on staged fixtures.** Create `tests/task_fix/` under the
skill-creator-aligned pattern with the evals Acceptance names, each over a staged
tree, graded on the task file's bytes and the report's per-finding lines, and
register the harness under `## Current harnesses` in `tests/README.md` and in the
per-harness table in `tests/CLAUDE.md`. Add the two `task_auto_check` evals
Acceptance names beside the existing `mechanical_lint_*` scenarios. Supersede the
`tests/task_auto_check/script_tests/run.sh` `assert_contains` needle labeled
`immediate ready path finalizes lint` (today the verbatim skill sentence "When every
citation survives, the `ready` stamp stands and the run proceeds to
`<finalize_mechanical_lint>` as on any other `ready` verdict.") so the needle matches
the rewritten ready→finalize wording that routes the repeated-link repair round
before finalize. Re-run the family contract test so the reworded passages stay within
the contract it asserts.

**Out of scope:**

- Retuning `REPEATED_LINK_FLOOR`, changing the linter's message, or making the check
  section-aware, since the count-two case is where the scattered account sat and the
  floor's own comment keeps a retune available against fresh data.
- Adding a grouping item to the `<readiness_checklist>`, since a legitimately kept
  repeat would then hold a task out of `ready` on a style warn; `task_check` stays a
  reporting surface for this finding.
- Clearing findings on archived tasks or at `task_finish` close-out, since the
  live-only rule in **a** is the counterpart and the `<archive>` workflow's
  file-scoped lint already leaves them unrequired.
- Widening which files the linter reads, owned by
  [task-family_repo-wide-link-integrity](task-family_repo-wide-link-integrity.md).

## Acceptance

1. In the base `task` skill's `<lint>` section, the paragraph led by
   **Repeated-link react protocol.** names `task_fix` inline, `auto_shaper_task` on
   escalation, `task_auto_check` through its repair path, and the hub `<update>` as
   the surfaces that apply the regroup, names `task_check`, `task_audit`,
   `task_explain`, `task_select`, and `task_finish` as the surfaces that report it
   with its sections, and grepping the skill for "A writing surface applies the
   regroup" and for "A read-only surface reports the finding" finds nothing.
2. The same paragraph's decision step reads the body's whole account of the target
   and gathers a repeated account into its owning section, states that the finding is
   resolved when the account sits in one place regardless of the surviving link count,
   and grepping the skill for "name a distinct role each time" finds nothing.
3. The same paragraph states that the writing owners regroup live tasks and that a
   finding on an archived task is reported as part of a count with the body left as
   archived, grepping the base skill for that archived-count statement finds exactly
   one site, and the mechanically fixable set's omission of `repeated-link` names the
   react protocol as the finding's owner.
4. The `task_fix` `<workflow>` **Remediate.** step names the meaning-preserving
   regroup among the advisory repairs it applies inline, its `<surface_for_review>`
   entry led by **Repeated-link findings** covers only the Goal-meaning,
   Acceptance-contract, and separate-concerns cases, and grepping `task_fix` for
   "human-owned on the escalated path as well, because deciding whether to gather"
   finds nothing.
5. The `task_fix` `<output_contract>` requires the shared per-finding disposition
   line shape Approach **b** names for each live `repeated-link` finding, one
   archived-count line, and counts regrouped findings in `N issues resolved` and
   surfaced ones in `K flagged for review`.
6. The `auto_reviewer_task` `<standing_stances>` list carries a Grouping advocate
   citing the base `<markdown_policy>` grouping rule and the react protocol, and its
   `<role>`, grounding `<policy>`, `<inputs>`, and output-contract `issue:` field
   each admit a lint-originated `repeated-link` finding as an issue class; grepping
   those four sites for only-`task_check` grounding of the admissible issue class
   finds nothing.
7. In `task_auto_check`, `<freeze>` records the target's `repeated-link` findings,
   `<plan_repairs>` maps them to the Grouping advocate, every ready→finalize path
   Approach **c** names runs one repair round for them before finalize, and
   `<mechanical_lint_boundary>` still excludes them from mechanical application, and
   both the finalization surfaced-but-not-fixed line and the stuck/human-routed
   channel omit dispositioned repeated-link findings (regrouped or kept) while still
   carrying verifier-rejected or reviewer-surfaced ones; grepping `task_auto_check`
   for that disposition filter finds the rule, grepping it for "as on any other
   `ready` verdict" finds nothing, and the superseded `immediate ready path
   finalizes lint` `assert_contains` needle in
   `tests/task_auto_check/script_tests/run.sh` matches that rewritten ready→finalize
   wording.
8. The `auto_shaper_task` rule lists five defect kinds including the repeated-link
   regroup, its `## Applied fixes` grouping names the regroup, its `<remediate>`
   block carries a `For a repeated-link regroup…` clause that applies the base react
   protocol and bumps `updated` once with that edit, and grepping the agent for
   "these four defect kinds" finds nothing.
9. `tests/task_fix/evals/evals.json` holds three staged evals. In
   `regroup_live_skip_archived` a live task carries the same handoff account in
   `## Goal` and `## Context` with two links to one sibling and an archived task links
   one target twice; it passes when the live body carries that account in
   `## Context` only with `updated` bumped, the archived file is byte-identical, and
   the report carries the live finding's line as regrouped plus the archived-count
   line. In `kept_each_site_earns_link` Context introduces a page as background and
   Approach names it as an edit site with distinct accounts; it passes when the body
   is byte-identical and the report line reads kept. In `surfaced_acceptance_contract` the two
   sites are `## Goal` and one `## Acceptance` item with `## Context` silent about the
   sibling, and each copy is load-bearing for its own section, so neither can absorb the
   other and every gathering available strips a section of its own contract; it passes
   when the body is byte-identical, both links still stand, and the report line reads
   surfaced with that reason rather than kept. Each eval fails when its file-state or
   report condition does not hold. The absent `## Context` copy is load-bearing for the
   eval: the surfaced class protects `## Goal` and the Acceptance contract only, so any
   duplication including a Context copy has a benign escape in trimming Context, which
   costs no section its contract.
10. `tests/task_fix/` follows the skill-creator-aligned layout with fixtures, a runner
    matching `tests/task_auto_check/evals/run.py`, and deterministic grading, and
    both `## Current harnesses` in `tests/README.md` and the per-harness table in
    `tests/CLAUDE.md` carry a `task_fix/` row.
11. `tests/task_auto_check/evals/evals.json` gains `regroup_via_reviewer`, where the
    target carries a scattered account behind a `repeated-link` finding and passes
    when the gathered body lands in one verifier-approved edit group with `updated`
    bumped once and the finalization report lists no repeated-link finding as
    surfaced-but-not-fixed, and `regroup_immediate_ready`, where `task_check` reports
    `ready` on the first call and passes when one repair round still runs for the
    finding before finalization and the report carries its disposition line in the
    shared shape, with the file state held to whichever disposition the run reported:
    a regrouped finding clears the warn, leaves the account in one section, and bumps
    `updated`, while a kept or surfaced one leaves the body byte-identical. That
    second eval grades the routing rather than the disposition because its fixture
    names `throttle.py` as Approach's edit site and the sibling task only as the
    dependency behind it, which sits on the contested edge of the grouping rule's
    carve-out for "an edit site named in Approach that Context introduced as
    background"; pinning a disposition there would test that judgement call rather
    than the ready-path routing this task delivers. The existing `mechanical_lint_*`
    evals pass unchanged.
12. `tests/task/run_all.sh` exits 0 against the reworded passages, including the
    family contract test under `tests/task/script_tests/contract_run.sh`.
13. `task_auto_check`'s `<verification_standard>` admits a lint-originated
    repeated-link regroup as an approvable cited-issue class, the applied-edit
    report's `issue:` field can name that class, `auto_verifier_task`'s
    writer-executed-plan rule lists split, relocation, backlog-coherence, and
    repeated-link regroup, its role/policy and output-contract `issue:` field admit
    that lint-originated class for both the `task_auto_check` and shaper paths, and
    grepping `auto_verifier_task` for "those three kinds and no others" finds nothing.
14. `task_auto_check`'s report requires the shared per-finding disposition line
    shape Approach **b** names for each target `repeated-link` finding the run
    dispositioned, and grepping the skill for that shared-shape requirement finds
    the rule.
