---
description: Reframe task family docs to a five-step lifecycle spine, task_select demoted to a chooser, check/auto-check merged into one entry, staged-spec lineage removed, and 'Work tracking' header retitled.
scope: plugins/ai_dev
created: 2026-07-14T19:38:42
updated: 2026-07-21T08:47:33
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Reframe the task family's docs around a five-step lifecycle spine and a readiness-prep purpose

## Goal

Simplify how the `task_*` family is advertised so its headline reads as one
uncomplicated spine rather than a six-station pipeline. The lifecycle the docs
promise becomes **create → check → implement → audit → finish** — the five
stages a single task's status actually climbs — with `task_select`,
`task_explain`, and `task_fix` sitting beside that spine as tools rather than
stations on it, and the check stage shown in the docs as one entry led by
`task_auto_check` with the `task_check` gate folded into it. The user-visible
outcome:

- The advertised chain is five steps everywhere it appears — in every `task_*`
  skill's `<family>` block and in both READMEs — with `task_select` no longer
  inside the arrow.
- `task_select` is presented as a read-only chooser that recommends the next
  task to work on — the one that most advances the project — and names its
  natural next action, which may be a check pass before implementation rather
  than assuming the task is already at the `ready` status. It is skippable for a
  one-task run, leaned on for a larger backlog, and grouped with the other
  beside-the-spine skills rather than in the lifecycle list. It sets no task
  status, which is why it is not a spine stage.
- The two READMEs fold `task_check` and `task_auto_check` into one compact
  readiness entry (three to four lines) led by `task_auto_check`, with the
  read-only `task_check` gate it reuses folded in inline, so the lifecycle list
  stays short instead of growing a station per skill.
- No staged-spec framework lineage remains in the family's shipped docs: the
  report-shape and workflow descriptions stand on their own instead of citing
  `spec_check`, `spec_audit`, or `spec_implement`.
- The plugin README's section header stops underselling the family as "Work
  tracking." The head reframes the family's real purpose: preparing a work item
  to single-shot implementation readiness for an AI agent, with the human in the
  loop as the driver and sense-maker — not merely tracking that work exists.
- A full read-through of both READMEs leaves no passage still contradicting the
  new framing (dangling "what should I work on next" gate claims, "single-task
  siblings" labels, or select-as-gate prose).

## Context

The change is entirely in orientation prose — skill `<family>` blocks and the
two READMEs. No skill behavior, script, schema, or the linter changes; the
skills stay distinct (this merges a README *entry*, never the skills
themselves), and `task_select` stays a real, listed sibling.

**Why five steps, not six.** The create→finish path is a status ladder: each
stage stamps the task file (`task_check` writes `ready`/`checked`,
`task_implement` writes `implemented`, `task_audit` writes `audited`,
`task_finish` writes `finished`), per the base skill's `<lifecycle_responsibility>`.
`task_select` appears on no status-writer list — it reads the eligible live
tasks at any status and recommends the one that best advances the project,
naming its natural next action (which may be a check pass, then implement), and
changes no file. So it is a chooser feeding the spine, not a rung on it, and a
single-task backlog never invokes it. Advertising it as a mandatory station
overcomplicates the pitch and misdescribes what it does.

**Where the six-step arrow lives today.** The verbatim phrase
`create → check → select → implement → audit → finish` appears in the `<family>`
block of all ten `task_*` skills (`task`, `task_create`, `task_check`,
`task_auto_check`, `task_explain`, `task_select`, `task_implement`, `task_audit`,
`task_finish`, `task_fix`) and in both READMEs. Nine skills use the Unicode
arrow `→`; `task_explain`'s `<family>` block uses the ASCII `->` variant. The
base `task/SKILL.md` `<family>` block carries the sentence inside a longer
drift-spectrum paragraph. `task_auto_check`'s variant reads "opt-in replacement
for manual readiness refinement" rather than "opt-in readiness repair loop" —
keep that wording, change only the arrow.

**What stays.** Every skill's `<family>` bulleted sibling list keeps listing
`task_select` — only the chain-arrow sentence drops it. Routing lines that
mention `task_select` by function ("choose what to work on next
(`task_select`)") in the `<when_to_activate>` / route-elsewhere prose of
`task_check`, `task_audit`, `task_fix`, `task_implement`, `task_finish`, and
`task_explain` stay as-is: they describe select's unchanged job, not the spine.

**Staged-spec lineage to remove** (framework attributions, not the generic word
"spec"): plugin README's `task_check` "ported from staged-spec's `spec_check`"
and `task_audit` "ported from staged-spec's `spec_audit`"; root README's
`task_check` "returns `spec_check`'s shape", `task_implement` "ported from
staged-spec's `spec_implement`", and `task_audit` "`spec_audit` shape"; and
`task_check/SKILL.md`'s "Borrow `spec_check`'s shape exactly". In each case keep
the actual report shape or workflow (the `# General assessment` + ranked
`## Issues` list, the `Success`/`Gaps:` verdict, the read→implement→verify flow)
and drop only the "from spec_*" provenance. Leave
`ai_instruction_formatting/SKILL.md`'s `<after_spec_execution>` example tag
alone — it is an illustration of tag naming, not a framework reference.

**README target structure.** In each README, the lifecycle list becomes
`task_create` → combined check/auto-check entry → `task_implement` →
`task_audit` → `task_finish`; the beside-the-spine group gains `task_select`
alongside the existing `task_explain` and `task_fix`. The plugin README's
"Standing apart from that flow:" sub-list is the landing spot for select; give
that group a lead-in that frames all three as tools beside the spine, not
leftovers.

**Specific stale passages the sweep resolves:**

- Plugin README `### Work tracking` header and its section intro — retitle and
  reframe to the readiness-prep purpose above.
- Plugin README "Each gate below catches a different kind of gap" paragraph
  names `task_select` as one of the gap-catching gates; drop select from that
  enumeration (creation, `task_check`, `task_audit` remain the gates) and let
  select's description carry its chooser role instead.
- Both READMEs' "The single-task siblings run in lifecycle order, **create →
  check → select → implement → audit → finish**, with `task_auto_check`
  available as an opt-in readiness repair loop between create/check and
  selection:" — the "single-task siblings" label is false for select, and
  "between create/check and selection" dangles once select leaves the list.
- Root README's "they answer three questions without editing anything: is this
  ready to build, what should I work on next, and is it done?" — the two spine
  gates (`task_check` → ready-to-build, `task_audit` → done) stay the read-only
  gates; reframe "what should I work on next" as select's separate read-only
  chooser rather than a third spine gate.
- Root README's "It works like Jira or Trello, but for AI agents" framing — keep
  the accurate async-backlog point, but let the section lead with the
  readiness-prep purpose so tracking reads as a means, not the headline.

**Co-edit coordination.** Several open siblings also edit these skill files —
notably [the Out of scope boundary task](task-family_out-of-scope-boundary-convention.md),
which enumerates the shared co-edit set (`task/SKILL.md`,
`task_implement/SKILL.md`, `task_auto_check/SKILL.md`, `task_audit/SKILL.md`,
`task_fix/SKILL.md`). This task touches a different region (the `<family>`
block and README lists) than those tasks (`<body>`, `<readiness_checklist>`,
workflow steps), so the edits compose. Whichever task lands later re-reads the
shared files and anchors its edits to the target passages by verbatim label, not
by position or line number.

## Approach

Edit orientation prose only, in positive language and the existing pseudo-XML /
Markdown structure, rewriting each affected passage in place to its target form.

**Skill `<family>` blocks (all ten `task_*` skills, the base `task` included):**

1. In every `task_*` skill's `<family>` chain sentence, rewrite the arrow
   `create → check → select → implement → audit → finish` to
   `create → check → implement → audit → finish`, and rewrite the adjunct tail so
   it reads: `task_auto_check` as the opt-in readiness repair loop (keep
   `task_auto_check`'s "replacement for manual readiness refinement" variant),
   `task_select` as a read-only chooser for what to work on next, and `task_fix`
   maintaining the tree. Apply the same arrow change to `task_explain`'s ASCII
   `->` variant, preserving its `->` style. Anchor each edit to the verbatim
   arrow phrase, not to a line. Leave each `<family>` bulleted sibling list
   unchanged — `task_select` stays listed there.

**Plugin README (`plugins/ai_dev/README.md`):**

1. Retitle the `### Work tracking` header and rewrite its section intro to lead
   with the family's purpose: preparing one work item to single-shot
   implementation readiness for an AI agent, with the human as driver and
   sense-maker. Keep the existing "gaps get filled wrongly by a one-shot
   implementer" argument that follows.
2. Rewrite the "Each gate below catches a different kind of gap" paragraph to
   drop `task_select` from the gate enumeration.
3. Rewrite the "single-task siblings run in lifecycle order" lead-in to the
   five-step spine without the "single-task siblings" label and without the
   dangling "between create/check and selection" tail.
4. Merge the `task_check` and `task_auto_check` bullets into one readiness entry
   of three to four lines led by `task_auto_check` — the opt-in loop that drives
   a task to the `ready` status by reusing that gate — with the read-only
   `task_check` gate (and its `ready`/`checked` verdict) folded in inline. Drop
   the "ported from staged-spec's `spec_check`" attribution while keeping the
   report shape.
5. Move the `task_select` bullet out of the lifecycle list into the
   beside-the-spine sub-list (with `task_explain` and `task_fix`), reframing it
   as the skippable read-only chooser that recommends the next task to work on —
   the one that most advances the project — and names its natural next action,
   superseding select's current "A read-only step between readiness and
   implementation" line and not implying it only ranks tasks already at the
   `ready` status. Give that sub-list a lead-in that frames its members as tools
   beside the spine. Remove the `task_audit` "ported from staged-spec's
   `spec_audit`" attribution, keeping its verdict shape.

**Root README (`README.md`):**

1. Apply the same five-step arrow and select-relocation to the `### ai_dev`
   task passage: rewrite the intro lifecycle sentence ("create → check →
   select → implement → audit → finish lifecycle gives each step its own
   skill") and the "single-task siblings" lead-in, reframe the "three
   questions" passage so select's "what to work on next" is the separate
   chooser rather than a third gate, move the `task_select` bullet into the
   "Standing apart from that flow:" sub-list, merge the
   `task_check`/`task_auto_check` bullets into one readiness entry as described
   for the plugin README, and soften the "Jira or Trello" framing to lead with
   the readiness-prep purpose. Remove the `spec_check`, `spec_implement`, and
   `spec_audit` attributions from the `task_check`, `task_implement`, and
   `task_audit` bullets, keeping each described shape and flow.

**Skill body staged-spec attribution:**

1. Rewrite `task_check/SKILL.md`'s "Borrow `spec_check`'s shape exactly" in place
   so the report shape (the `# General assessment` paragraph plus the ranked
   `## Issues` list) is stated as this skill's own contract, with no reference to
   `spec_check`.

**Out of scope:**

- No skill behavior, workflow logic, script, schema, or linter change; the
  merge of the `task_check` and `task_auto_check` bullets in each README is a
  README *entry* merge, and `task_check` and `task_auto_check` remain separate
  skills.
- `task_select` is not removed, renamed, or deprecated — it stays a listed
  sibling and a real skill; only its place in the advertised arrow changes.
- Routing / cross-reference mentions of `task_select` by function in other
  skills' `<when_to_activate>` prose stay unchanged.
- The generic word "spec"/"specification" and the `<after_spec_execution>`
  example tag are not swept; only staged-spec framework lineage attributions go.
- No change to task files under `tasks/` (including the sibling tasks that
  discuss StagedSpec as the family's predecessor) — this task governs shipped
  skill and README prose only.

This edits shipped skill content, so the standing repo version-bump,
plugin-lockstep, and lint-clean-before-commit rules apply at commit time.

## Acceptance

- A grep for `create → check → select → implement → audit → finish` and for the
  ASCII `create -> check -> select -> implement -> audit -> finish` across
  `plugins/ai_dev/` and `README.md` returns nothing; the five-step
  `create → check → implement → audit → finish` (and the `->` variant in
  `task_explain`) appears in all ten `task_*` `<family>` blocks and in both
  READMEs' lead-in. In each skill `<family>` sentence, `task_auto_check`,
  `task_select`, and `task_fix` are named in the tail beside the arrow rather
  than inside it.
- The `task_auto_check` variant survives the five-step rewrite as the one
  canonical exception, verified against the rewritten (five-step) state so the
  check flips rather than passing on today's six-step text:
  `task_auto_check/SKILL.md`'s `<family>` block now contains both the five-step
  `create → check → implement → audit → finish` arrow and the tail wording
  "opt-in replacement for manual readiness refinement" (and never "opt-in
  readiness repair loop"), while each of the other nine `task_*` `<family>`
  blocks contains both the five-step arrow (the `->` variant in `task_explain`)
  and "opt-in readiness repair loop" (and never "replacement for manual
  readiness refinement"); equivalently, a grep for `replacement for manual
  readiness refinement` across the ten blocks matches only
  `task_auto_check/SKILL.md`, and a grep for `opt-in readiness repair loop`
  matches the other nine and never `task_auto_check`.
- Every `task_*` skill's `<family>` bulleted sibling list still lists
  `task_select`, confirming select was demoted in the arrow only, not delisted.
- In `plugins/ai_dev/README.md`, the lifecycle list runs `task_create` → one
  combined check/auto-check entry → `task_implement` → `task_audit` →
  `task_finish` with no `task_select` bullet among them; the combined entry is
  three to four lines led by `task_auto_check` with the `task_check` gate folded
  in inline; and `task_select` appears once, in the beside-the-spine sub-list
  with `task_explain` and `task_fix`.
- In `README.md`, `task_select` likewise sits in the "Standing apart from that
  flow:" sub-list, the `task_check`/`task_auto_check` bullets are merged, and the
  "three questions" passage no longer presents "what should I work on next" as a
  spine gate.
- The plugin README's task section header is no longer "Work tracking", and its
  intro leads with preparing a work item to single-shot implementation readiness
  for an AI agent with the human as driver and sense-maker; the superseded
  "Work tracking" heading no longer appears.
- A grep for `spec_check`, `spec_audit`, `spec_implement`, `staged-spec`, and
  `StagedSpec` across `plugins/ai_dev/README.md`, `README.md`, and the `task_*`
  `SKILL.md` files returns no lineage attribution; the `task_check` report shape,
  the `task_audit` verdict shape, and the `task_implement` flow are each still
  described, now self-contained.
- `ai_instruction_formatting/SKILL.md` is byte-identical before and after
  (its `<after_spec_execution>` example tag is untouched), confirming the sweep
  hit framework lineage only.
- A read-through of both READMEs confirms each reframed passage carries its new
  wording, not only its new location: in both READMEs the `task_select` bullet
  describes the read-only chooser that recommends the next task to work on — the
  one that most advances the project — and names its natural next action,
  without implying the task is already at the `ready` status, superseding the
  plugin README's prior "A read-only step between readiness and implementation"
  line; in `README.md`, the task section leads with the readiness-prep purpose
  rather than the "Jira or Trello" comparison (kept, if at all, as a means
  rather than the headline), and its combined check/auto-check entry is the same
  three-to-four-line entry led by `task_auto_check` with the `task_check` gate
  folded in inline that the plugin README's entry carries; and in
  `plugins/ai_dev/README.md`, the beside-the-spine sub-list opens with a lead-in
  that frames its members as tools beside the spine.
- A read-through of both READMEs finds no remaining "single-task siblings"
  label, no "between create/check and selection" tail, and no prose that still
  calls `task_select` a lifecycle gate or station.
