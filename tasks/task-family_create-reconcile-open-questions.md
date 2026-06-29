---
description: After task_create writes and lints a task, add a step that surfaces the draft's residual open questions with reconciliation suggestions and asks the user to resolve each now or defer it.
scope: plugins/ai_dev/skills/task_create
created: 2026-06-29T19:39:17
updated: 2026-06-29T19:39:17
status: open
reported-by: Andreas Hoffmann
---

# task_create surfaces a task's open questions after writing and offers to reconcile them while context is fresh

## Goal

After task_create writes and lints a task file, it runs one more step: it
surfaces to the user the open questions the draft still carries — the labeled
open decision, any unresolved "this or that" fork, and any under-specified
pointer the self-check could not settle from the material available at authoring
time — each paired with a concrete reconciliation suggestion, and asks per item
whether to resolve it now or defer it. When the user resolves an item now,
task_create applies the fix to the just-written file while the creating context
is still loaded and re-lints; when the user defers, the item stays in the file
for `task_check` to surface later. The user-visible outcome is that a task which
needs decisions gets them at creation time — when the person who asked for it is
present and the context is fresh — instead of arriving cold at `task_check`,
where reconstructing each deferred decision is the slow part of the path to
`ready`.

This delivers an *interaction*, not a new detection rule. What counts as an open
question is already defined by the base `task` skill's **Decide or label** rule
and the `<readiness_checklist>`'s **Ambiguity / under-specification** lens, and
task_create already self-checks the draft against them. The new step takes that
residue — the part that genuinely needs user input — and puts it in front of the
user instead of silently writing it and reporting done.

## Context

task_create's `<workflow>` in `plugins/ai_dev/skills/task_create/SKILL.md` today
ends at step 8, **Lint**: it self-checks the draft (step 6, **Self-check the
draft**), writes (step 7), lints (step 8), and reports through its
`<output_contract>`. Step 6 already judges the draft against the base `task`
skill's `<readiness_checklist>` and resolves every finding it can before writing
— but some findings cannot be resolved from the material available at authoring
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

Add one step to task_create's `<workflow>`, in sequence after step 8 **Lint**
(for example named **Surface and reconcile open questions**). It runs once the
file is written and lint-clean, so every item it surfaces references the file as
it now stands on disk.

1. **Collect the residue.** Reuse the step 6 **Self-check the draft** findings —
   those falling under the base `<readiness_checklist>`'s **Decide or label** and
   **Ambiguity / under-specification** lenses — together with any "Open
   decision:" label written into the body. Define no new detection here: the
   residue is exactly what those existing lenses already name and what the draft
   could not settle from authoring-time material. When the residue is empty, say
   so in one line and finish without prompting.
2. **Present each item with a reconciliation suggestion.** Surface the residue as
   a numbered list. For each item, state the open question in one line, then give
   a concrete reconciliation suggestion — which option to pick and why, the
   concrete value a vague pointer should take, or the requirement to add — so the
   user reconciles by confirming or correcting a proposal rather than from a
   blank prompt. This with-suggestions framing is the point of the step: the user
   chooses among drafted resolutions instead of being handed the work back.
3. **Ask resolve-now or defer, per item.** For each numbered item the user
   chooses to resolve it now or defer it, and may accept, reject, or modify the
   suggestion — the same per-number accept / reject / modify shape the base
   skill's `<update>` **Applying check findings** flow already defines. Reuse that
   flow's mechanics rather than inventing a parallel one.
4. **Apply the resolve-now decisions in one round.** For every item resolved now,
   apply the minimum fix to the just-written file while the creating context is
   fresh, folding any user modification in over the suggestion, then bump
   `updated` once and re-lint once — one update round per the apply-findings flow.
   Deferred items stay in the file unchanged: a genuinely-open fork remains the
   one labeled open decision within the **Decide or label** ceiling for
   `task_check` to surface later, so deferring loses nothing the existing path
   would have caught.

Keep the step opt-in and non-blocking: it offers reconciliation and records the
user's choice; it never withholds the created file or forces a decision. A user
who wants the task captured as-is defers every item and the step ends.

Extend task_create's `<output_contract>` in place so the report names the open
questions surfaced and the user's per-item resolve-now / defer decisions, and
notes a clean re-lint when any fix was applied — superseding the current contract
sentence rather than standing a second one beside it. Frame both edits as
rewrites: the `<workflow>` gains one step in sequence after **Lint**, and the
`<output_contract>` becomes one canonical statement that covers the new
reporting.

Non-goals: add no new detection rule or `<readiness_checklist>` lens — the
residue comes from the existing **Decide or label** and **Ambiguity** lenses, and
any change to what those *mean* belongs in the base skill, not here; define no
parallel reconciliation mechanism — reuse the base `<update>` apply-findings
flow; touch no other sibling skill; and name no harness-specific prompting tool —
describe the surface-and-ask behavior in harness-agnostic terms, matching the
family's existing apply-findings wording. Hold any skill-behavior eval growth for
a separate session per the repo's keep-skill-change-and-harness-expansion-separate
rule. This edits shipped skill content under `plugins/ai_dev/`, so the standing
plugin-version-bump and validation gates apply at commit time.

## Acceptance

- task_create's `<workflow>` carries a new step after step 8 **Lint** that, once
  the file is written and lint-clean, surfaces the draft's residual open
  questions and asks the user to resolve or defer each; grepping
  `task_create/SKILL.md` finds it.
- The step sources its items from the existing step 6 **Self-check the draft**
  findings under the base `<readiness_checklist>`'s **Decide or label** and
  **Ambiguity / under-specification** lenses plus any "Open decision:" label, and
  defines no new detection rule of its own; reading the step shows it citing
  those base lenses rather than restating them.
- Each surfaced item carries a concrete reconciliation suggestion (which option
  and why, the concrete value for a vague pointer, or the requirement to add), so
  the user confirms or corrects a proposal; an item presented as a bare question
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
  open questions and the user's per-item resolve-now / defer decisions, plus a
  clean re-lint when a fix was applied; grepping finds one canonical contract
  statement, not a second copy of the prior sentence beside it.
- The base `task` skill is unchanged by this task: its `<body>` **Decide or
  label** rule (including the one-decision ceiling), its `<readiness_checklist>`,
  and its `<update>` flow carry no edit — inspection confirms the change is
  localized to `task_create/SKILL.md`.
