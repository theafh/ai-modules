---
description: After task_create writes and lints a task, add a step that surfaces the draft's one residual open decision with a reconciliation suggestion and asks the user to resolve it now or defer it.
scope: plugins/ai_dev/skills/task_create
created: 2026-06-29T19:39:17
updated: 2026-06-30T07:27:09
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# task_create surfaces a task's open decision after writing and offers to reconcile it while context is fresh

## Goal

After task_create writes and lints a task file, one more workflow step surfaces
the single open decision the draft still carries — the residue defined in
`## Context` — together with a concrete reconciliation suggestion, and asks the
user to resolve it now or defer it. Resolving now applies the fix to the
just-written file while the creating context is still loaded; deferring leaves
the decision in the file for `task_check`. When the draft carries no such
residue, the step says so in one line and finishes without prompting. The
outcome is that a task needing a decision gets it at creation time, when the
requester is present and the context is fresh, instead of arriving cold at
`task_check` where reconstructing the decision is the slow part of reaching
`ready`.

This adds an interaction, not a detection rule: what counts as an open decision
is already the base `task` skill's **Decide or label** rule, which task_create
already self-checks the draft against.

## Context

The target is `plugins/ai_dev/skills/task_create/SKILL.md`. Its `<workflow>`
self-checks the draft (the **Self-check the draft** step), writes (the **Write**
step), lints (the **Lint** step), and reports through `<output_contract>` —
ending at **Lint** with no creation-time reconciliation.

The residue this task acts on is exactly one item: the single labeled "Open
decision:" the base `<body>` **Decide or label** rule permits as its ceiling —
the one fork or under-specified pointer the authoring material cannot settle,
which the `<readiness_checklist>`'s **Ambiguity / under-specification** lens
routes into that same decision rather than a second stream. This task defines no
new residue; it surfaces the one that rule and lens already name.

One wording gap blocks the new step today: the **Self-check the draft** step
reads "resolve every finding before writing," which on a literal read leaves no
residue for a later step to surface. The base **Decide or label** rule already
reconciles this — resolving a finding the material cannot settle *means* labeling
it as the one carried-forward open decision — so the step needs rewording to say
so, not a new rule.

The motivating observation is that freshly created tasks routinely carry one
undecided fork, and that residue is what makes the later path to `ready` slow,
because `task_check` surfaces it once the creating context is gone. Moving the
reconciliation to creation time, as an offer the user can take or decline, is
the fix. The step belongs to task_create because that is the interactive
single-task on-ramp where the requester is present at creation.

## Approach

Make three edits, all within `task_create/SKILL.md`.

1. **Reword the self-check step in place.** The **Self-check the draft** step
   today reads "resolve every finding before writing." Rewrite it to resolve
   every finding derivable from authoring-time material and carry forward,
   labeled "Open decision:", the one genuinely-open decision that material
   cannot settle — citing the base **Decide or label** ceiling rather than
   copying it, so one canonical statement replaces the old sentence.
2. **Add a `<workflow>` step after the **Lint** step.** Once the file is written
   and lint-clean, it takes the **Self-check the draft** step's carried-forward
   open decision (the residue from `## Context`), states it in one line, and
   pairs it with a concrete reconciliation suggestion — which option and why, the
   concrete value a vague pointer should take, or the requirement to add — so the
   user confirms or corrects a proposal rather than answering a blank prompt. It
   then asks resolve-now or defer. Resolving now applies the minimum fix to the
   just-written file, folding in any user modification, then bumps `updated` once
   and re-lints once; deferring leaves the decision in place for `task_check`; an
   empty residue ends the step in one line with no prompt. Reuse the base skill's
   `<update>` **Applying check findings** mechanics for the apply path — per-number
   accept / reject / modify, one update round, one `updated` bump, one re-lint —
   rather than defining a parallel one.
3. **Supersede the `<output_contract>` sentence** so the report also names the
   surfaced open decision, the user's resolve-now / defer choice, and a clean
   re-lint when a fix was applied — one canonical contract statement, not a second
   beside the old one.

Keep the step opt-in and non-blocking: it offers reconciliation and records the
choice but never withholds the created file or forces a decision; a defer reply
ends it with the file as written.

Non-goals: add no new detection rule or `<readiness_checklist>` lens — any change
to what the existing rule and lens *mean* belongs in the base skill; define no
parallel reconciliation mechanism; touch no file other than `task_create/SKILL.md`;
leave task_create's `<role>` untouched, since its "no surrounding workflow"
phrasing scopes the skill against the broader backlog workflows and an
interactive step within creation, like the existing prior-art gate, is
consistent with it; and name no harness-specific prompting tool, matching the
base apply-findings wording. This edits shipped skill content under
`plugins/ai_dev/`, so the plugin-version-bump and lint gates apply at commit time.

## Acceptance

- `task_create/SKILL.md`'s `<workflow>` carries a new step after the **Lint** step
  that, on a written and lint-clean file, surfaces the draft's one residual open
  decision and asks resolve-now or defer, and on an empty residue finishes in one
  line without prompting; both branches are present.
- The new step sources its item from the **Self-check the draft** step's
  carried-forward "Open decision:" and cites the base **Decide or label** rule and
  **Ambiguity / under-specification** lens rather than restating them; it defines
  no new detection.
- The **Self-check the draft** step is reworded in place to resolve every finding
  derivable from authoring-time material and label the one genuinely-open decision
  per **Decide or label**; the prior "resolve every finding before writing"
  wording no longer stands, and the reworded step agrees with the new step.
- The surfaced decision carries a concrete reconciliation suggestion — the option
  and why, the value for a vague pointer, or the requirement to add; a bare
  question with no suggestion does not satisfy the step.
- The apply path reuses and cites the base `<update>` **Applying check findings**
  flow (per-number accept / reject / modify, one update round, one `updated` bump,
  one re-lint) rather than a parallel mechanism: resolve-now applies the fix and
  re-lints, defer leaves the item for `task_check`.
- The step is opt-in and non-blocking — it never withholds the created file or
  forces a decision — and names no harness-specific prompting tool.
- The `<output_contract>` is superseded in place to report the surfaced open
  decision, the resolve-now / defer choice, and a clean re-lint when a fix was
  applied, leaving one canonical statement.
- The change is localized to `task_create/SKILL.md`: the base `task` skill
  (`<body>` **Decide or label**, `<readiness_checklist>`, `<update>`) and
  task_create's `<role>` are unchanged.
