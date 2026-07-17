---
description: "Broaden the base task skill's role to orientation and state the system's concept: a task file is enough on its own to implement, with every available context staying in play."
scope: plugins/ai_dev/skills/task
created: 2026-06-09T11:06:38
updated: 2026-06-10T20:50:09
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Base role states the task-system concept: self-sufficient, all context in play

## Goal

The base `task` skill's `<role>` reads as broad orientation — the hub of the
`task_*` family, the project-local backlog, and the concept behind the whole
system: **every task file is written to be self-sufficient** — the task itself
is enough to implement the work, including for a later session with no memory
of the task's creation — **and that sufficiency is a floor, never a filter**:
an implementer draws on everything actually available — the codebase, the
project's standing instructions, the user in the loop. The skill states this
concept generally; specific cases illustrate it instead of becoming rules of
their own.

## Context

- The current role codifies the concept through one overindexed specific:
  "implement it with no further context from chat", echoed by the
  `<single_shot_ready>` pitfall's "needs the original chat". Both entered with
  the skill's first commit (75c495f, 2026-05-28) as model-written phrasing
  that survived unreviewed. The intended meaning was always the general one:
  the task is enough when nothing else is there, and everything else stays in
  play when it is.
- The exclusion reading has costs on record: judging a task file as the
  implementer's "sole input" produced a false positive demanding a
  version-bump bullet the repo's `CLAUDE.md` owns (2026-06-02), and pushed
  repo rules to be copied into task bodies, where the copies drifted until
  mass-stripped (commit 3e48d5e).
- Roles across the family carry identity and lane (compare `task_check`'s
  role, which holds its read-only stance), with rules living in dedicated
  sections. The base role today instead restates the single-shot bar, the
  open/archive layout (`<architecture>` and `<status_matches_location>` own
  it), and the wiki boundary (`<not_in_scope>` owns it).
- All edits stay within `plugins/ai_dev/skills/task/SKILL.md`. The sibling
  skills' bar sentences follow in
  [task-family_implementer-input-bar.md](task-family_implementer-input-bar.md),
  which builds on the definition this task lands.

## Approach

- Rewrite `<role>` as two-to-three sentences of orientation: hub and source
  of truth of the `task_*` family; the project-local backlog of plain-markdown
  task files living next to the code; the system concept — self-sufficient
  task files, with all available context in play at implementation time.
  Layout, status, and boundary rules stay in their own sections.
- Restate the bar where the base skill defines it — the `<body>` lead
  sentence ("a single-shot AI coder picking up only this file") and the
  `<single_shot_ready>` pitfall — as the general principle: the file carries
  everything the work needs that the project itself does not already hold;
  whatever exists at implementation time (codebase, standing instructions,
  the user) is used. The vanished birth conversation serves as an example of
  why self-sufficiency matters, carried by the principle rather than carrying
  it.
- Add the corollary at the same definition site: content a standing project
  instruction already mandates is cited from the task, with the rule's text
  staying in its source document.
- Keep concept statements at concept altitude throughout the file: general
  formulations first, specific cases as illustrations.

## Acceptance

- The base `<role>` carries orientation only — hub identity, backlog, the
  self-sufficiency concept with its all-available-context half — and zero
  rule definitions; layout, status/location, and wiki boundary appear only in
  their dedicated sections.
- `rg -i "no further context from chat" plugins/ai_dev/skills/task/SKILL.md`
  returns nothing, and the `<single_shot_ready>` pitfall states the general
  principle with the birth conversation at most as an example.
- The cite-don't-restate corollary stands at the bar's definition site.
