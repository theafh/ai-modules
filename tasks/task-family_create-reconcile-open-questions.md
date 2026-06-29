---
description: After task_create writes and lints a task, add a step that surfaces the draft's one residual open decision with a reconciliation suggestion and asks the user to resolve it now or defer it.
scope: plugins/ai_dev/skills/task_create
created: 2026-06-29T19:39:17
updated: 2026-06-29T23:14:49
status: ready
reported-by: Andreas Hoffmann
---

# task_create surfaces a task's open decision after writing and offers to reconcile it while context is fresh

## Goal

After task_create writes and lints a task file, it runs one more step. It first
reconciles from the available context — the cited skills, the codebase, and the
project's standing knowledge — every question it can settle with high
confidence, deciding those itself rather than asking, and surfaces to the user
only the single piece that genuinely needs human judgment: the one labeled open
decision the **Decide or label** ceiling permits — the genuinely-open item the
authoring material cannot settle, whether it surfaces as a "this or that" fork or
as an under-specified pointer no available material resolves — paired with a
concrete reconciliation suggestion, and asks whether to resolve it now or defer
it. When
the draft carries no such residue, the step stays silent rather than
manufacturing questions the material already answers, so filing a complete task
stays fast. When the user resolves it now,
task_create applies the fix to the just-written file while the creating context
is still loaded and re-lints; when the user defers, the decision stays in the file
for `task_check` to surface later. The user-visible outcome is that a task that
needs a decision gets it at creation time — when the person who asked for it is
present and the context is fresh — instead of arriving cold at `task_check`,
where reconstructing the deferred decision is the slow part of the path to
`ready`.

This delivers an *interaction*, not a new detection rule. What counts as an open
question is already defined by the base `task` skill's **Decide or label** rule
and the `<readiness_checklist>`'s **Ambiguity / under-specification** lens, and
task_create already self-checks the draft against them. The new step takes that
residue — the part that genuinely needs user input — and puts it in front of the
user instead of silently writing it and reporting done.

## Context

task_create's `<workflow>` in `plugins/ai_dev/skills/task_create/SKILL.md` today
ends at the **Lint** step: it self-checks the draft (the **Self-check the draft**
step), writes (the **Write** step), lints (the **Lint** step), and reports through
its `<output_contract>`. The **Self-check the draft** step today reads "resolve every finding before writing,"
which on its face leaves no residue; reconciling that wording with the base
**Decide or label** ceiling it draws on — resolve every fork derivable from
authoring-time material, and carry forward the one genuinely-open decision that
material cannot settle — is part of this task (see `## Approach`), so the
**Self-check the draft** step and the new step state the residue once and agree.
That carried-forward residue is the set of findings the **Self-check the draft**
step cannot resolve from the material available at authoring
time. Those are exactly the cases the base skill's `<body>` **Decide or label**
rule governs: decide every fork derivable from the cited skills, the codebase,
and standing knowledge, and when one decision genuinely needs input that
material cannot provide, label it ("Open decision:") with its options and a
default — one labeled open decision being the ceiling. The
`<readiness_checklist>`'s **Ambiguity / under-specification** item names the same
residue from the check side, where "an unresolved either/or is a **Decide or
label** finding."

Today that residue is written into the file and left for `task_check` to flag
later. The base `task` skill already holds both halves this step needs: the
machinery to recognize the residue (the **Decide or label** rule and the
**Ambiguity** lens) and the machinery to resolve it interactively (the
`<update>` **Applying check findings** flow, where the user replies with issue
numbers and per-number accept / reject / modify decisions, each accepted
finding's minimum fix is applied in one update round, `updated` is bumped once,
and the linter re-runs once). What is missing is connecting the two at creation
time: nothing prompts the user to reconcile the residue while the context that
produced it is still loaded.

The motivating observation is that, in practice, freshly created tasks routinely
carry undecided "this or that" phrasing and decisions handed to the reader, and
that residue is what makes the later path to `ready` slow — `task_check`
surfaces it once the creating context is gone, so each decision costs a cold
re-read to reconstruct. Front-loading the reconciliation to creation time, as an
offer the user can take or decline, is the fix.

The step belongs to task_create because task_create is the interactive
single-task on-ramp where a user is present at creation. The detection rule it
draws on stays in the base skill per the family's author-once convention, and
the reconcile interaction reuses the base skill's existing apply-findings flow
rather than defining a parallel one — so this task adds neither a new lens nor a
new check, only the creation-time interaction layered over the lenses that
already exist.

## Approach

Add one step to task_create's `<workflow>`, in sequence after the **Lint** step
(for example named **Surface and reconcile the open decision**). It runs once the
file is written and lint-clean, so every item it surfaces references the file as
it now stands on disk.

1. **Collect the residue.** Reuse the **Self-check the draft** step's single
   carried-forward finding: the one labeled "Open decision:" the draft could not
   settle from authoring-time material — capped at one by the base `<body>`'s
   **Decide or label** rule, with the `<readiness_checklist>`'s **Ambiguity /
   under-specification** lens routing an unsettleable fork or under-specified
   pointer into that same decision rather than opening a second stream beside it.
   Define no new detection here: the residue is exactly what that rule and lens
   already name. When the residue is empty, say so in one line and finish without
   prompting; the step surfaces this residue alone and never generates a question
   the material already answers.
2. **Present the open decision with a reconciliation suggestion.** Surface the one
   carried-forward decision from step 1 (at most one item) as a single numbered
   entry: state the open question in one line, then give
   a concrete reconciliation suggestion — which option to pick and why, the
   concrete value a vague pointer should take, or the requirement to add — so the
   user reconciles by confirming or correcting a proposal rather than from a
   blank prompt. This with-suggestions framing is the point of the step: the user
   chooses among drafted resolutions instead of being handed the work back.
3. **Ask resolve-now or defer.** The user resolves the decision now or defers it,
   and may accept, reject, or modify the
   suggestion — the same per-number accept / reject / modify shape the base
   skill's `<update>` **Applying check findings** flow already defines, applied
   here to the single carried-forward entry. Reuse that
   flow's mechanics rather than inventing a parallel one.
4. **Apply the resolve-now decision in one round.** When the decision is resolved now,
   apply the minimum fix to the just-written file while the creating context is
   fresh, folding any user modification in over the suggestion, then bump
   `updated` once and re-lint once — one update round per the apply-findings flow.
   A deferred decision stays in the file unchanged: the genuinely-open fork remains the
   one labeled open decision within the **Decide or label** ceiling for
   `task_check` to surface later, so deferring loses nothing the existing path
   would have caught.

Keep the step opt-in and non-blocking: it offers reconciliation and records the
user's choice; it never withholds the created file or forces a decision. A user
who wants the task captured as-is defers every item and the step ends.

Extend task_create's `<output_contract>` in place so the report names the open
decision surfaced and the user's resolve-now / defer decision, and
notes a clean re-lint when any fix was applied — superseding the current contract
sentence rather than standing a second one beside it. Frame all three edits as
rewrites. First, rewrite the **Self-check the draft** step in place: today it reads
"resolve every finding before writing," which leaves no residue; reframe it so it
resolves every finding derivable from authoring-time material and labels the one
genuinely-open decision that material cannot settle — citing the base skill's
**Decide or label** ceiling rather than copying it — so the step no longer claims
zero residue. Then the `<workflow>` gains one step in sequence after **Lint** that
points at that **Self-check the draft** residue rather than re-describing it, and the
`<output_contract>` becomes one canonical statement that covers the new
reporting.

Non-goals: add no new detection rule or `<readiness_checklist>` lens — the
residue comes from the existing **Decide or label** rule and **Ambiguity /
under-specification** lens, and any change to what those *mean* belongs in the
base skill, not here; define no parallel reconciliation mechanism — reuse the
base `<update>` apply-findings flow; touch no other sibling skill; leave
task_create's own `<role>` untouched — its "no surrounding workflow" phrasing
scopes task_create against the broader backlog workflows (list, query, update,
finish), so an interactive step within creation, like the existing prior-art
gate, is consistent with it; and name no harness-specific prompting tool —
describe the surface-and-ask behavior in harness-agnostic terms, matching the
family's existing apply-findings wording. Hold any skill-behavior eval growth for
a separate session per the repo's keep-skill-change-and-harness-expansion-separate
rule. This edits shipped skill content under `plugins/ai_dev/`, so the standing
plugin-version-bump and validation gates apply at commit time.

## Acceptance

- task_create's `<workflow>` carries a new step after the **Lint** step that, once
  the file is written and lint-clean, surfaces the draft's one residual open
  decision (if any) and asks the user to resolve or defer it; grepping
  `task_create/SKILL.md` finds it.
- The step sources its item from the existing **Self-check the draft** step's
  single carried-forward "Open decision:" — the one the base `<body>`'s **Decide
  or label** rule caps at and into which the `<readiness_checklist>`'s **Ambiguity
  / under-specification** lens routes an unsettleable fork or under-specified
  pointer — and defines no new detection rule of its own; reading the step shows
  it citing that base rule and lens rather than restating them.
- The step surfaces only that **Self-check the draft** residue and generates no
  questions of its own: when the residue is empty it finishes in one line without
  prompting, so a draft the material fully settles is filed without added
  questions. Reading the step shows the empty-residue branch and no
  question-generation path beyond the residue.
- The **Self-check the draft** step is rewritten in place so it resolves every
  finding derivable from authoring-time material and labels the one genuinely-open
  decision per **Decide or label**, rather than claiming it resolves every finding
  before writing; grepping `task_create/SKILL.md` confirms the prior "resolve
  every finding before writing" wording is superseded — one canonical statement
  remains — and the **Self-check the draft** step agrees with the new post-lint step that surfaces the
  residue.
- The surfaced decision carries a concrete reconciliation suggestion (which option
  and why, the concrete value for a vague pointer, or the requirement to add), so
  the user confirms or corrects a proposal; a decision presented as a bare question
  with no suggestion does not satisfy the step.
- The reconcile interaction reuses the base skill's `<update>` **Applying check
  findings** flow (per-number accept / reject / modify, one update round, a
  single `updated` bump, one re-lint) and cites it rather than re-describing a
  parallel mechanism.
- Resolve-now applies the minimum fix to the just-written file and re-lints;
  defer leaves the item in place, a genuinely-open fork remaining the one labeled
  open decision within the **Decide or label** ceiling for `task_check` to catch
  later. Reading the step shows both branches.
- The step is opt-in and non-blocking: it never withholds the created file or
  forces a decision, and a defer-everything reply ends the step with the file as
  written. Reading the step confirms this.
- The step is harness-agnostic: it names no provider-specific prompting tool,
  matching the base apply-findings flow's wording; a grep of the step finds no
  harness tool name.
- task_create's `<output_contract>` is rewritten in place to report the surfaced
  open decision and the user's resolve-now / defer decision, plus a
  clean re-lint when a fix was applied; grepping finds one canonical contract
  statement, not a second copy of the prior sentence beside it.
- The base `task` skill is unchanged by this task: its `<body>` **Decide or
  label** rule (including the one-decision ceiling), its `<readiness_checklist>`,
  and its `<update>` flow carry no edit — inspection confirms the change is
  localized to `task_create/SKILL.md`.
