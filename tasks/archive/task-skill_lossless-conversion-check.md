---
description: Add a built-in lossless-conversion step so deriving tasks from any source — chat, note, todo, file, PDF — verifies no unit of meaning was dropped, without the user asking.
scope: plugins/ai_dev/skills/task
created: 2026-05-28T19:49:23
updated: 2026-06-01T23:25:41
status: implemented
---

# Verify lossless conversion when deriving tasks from any source

## Goal

Whenever the create flow turns a **source** into task files — whether that is
one task or many — the skill should verify on its own that every relevant unit
of meaning in that source is retained in the task(s) it creates, before offering
to drop the source or declaring it done. Producing a single task does not exempt
it: a source can carry far more than one task's worth of meaning, and the lone
task must still capture all of what's relevant. This holds for **any source
type**, not just a file on disk: an AI chat session being mined into tasks, a
pasted note, a `todo.md`, a spec, a PDF, a meeting transcript. Today nothing in
the workflow does this, so the quality depends on the user noticing and asking
for a re-check.

The volume of source material scales the *risk* of dropping something, not
whether the check runs — the more there is to process, the more can slip, so the
check always runs and keeps going until everything relevant is accounted for.

Building the check in is a turns/tokens win: a real `todo.md`→tasks session
shipped a "done" set, the user had to explicitly ask "double check no
information got lost," and the resulting audit found **four** real drops. That
is a whole extra round-trip the skill should have closed itself — and the same
loss can happen mining a long chat session or a PDF just as easily as a file.

## Context

Two skills create tasks and **both** need this contract, so it must be wired
into each explicitly rather than parked in one and assumed to carry:

- The base `task` skill's `<create>` workflow (and its `<batch_creation>` step) —
  reached directly, and when `task_create` hands a multi-item split back to it.
- The `task_create` skill — which writes a **single** task file itself and does
  not route that path through the base `<create>`; it only borrows the base
  skill's named sub-sections (`<prior_art>`, `<file_format>`, `<discover>`,
  `<lint>`). A contract added only to base `<create>` would silently skip the
  single-task-from-a-source path, which is exactly `task_create`'s lane and the
  case the Goal calls out. Add the contract to base `<create>` **and** reference
  it from `task_create` (factor the shared wording into one block both cite, so
  the two stay in step).

Neither path has any notion today of *deriving* tasks from pre-existing source
material, nor a fidelity gate for that case. The single-source-of-truth and
"write for a single-shot implementer" pitfalls assume content originates as
direct intent, not as a body of source being decomposed.

This task generalizes several source-specific drops seen in practice (a shared
top-of-file preamble vanishing, a rationale clause and a list item dropped, a
carve-out silently widened) into one reusable, **medium-agnostic** rule rather
than encoding each as its own fix or tying the rule to one source type.

## Approach

Add a short lossless-conversion sub-step — authored once and cited by **both**
the base `task` skill's `<create>` workflow and the `task_create` skill — that
fires **whenever any task is derived from source material, regardless of its
medium or how many tasks result** — chat session, note, todo, file, PDF,
transcript, paste, and whether it yields one task or many. It states a
lossless-conversion contract:

- **Every relevant unit of meaning in the source maps to at least one task.**
  Rewriting, merging, expanding, or restructuring source content is fine;
  dropping relevant meaning is not. Where one task is created, that task carries
  all of what's relevant; where many are, the meaning is spread across them with
  nothing left behind.
- **Source-wide content propagates, it does not evaporate.** Content that scopes
  the *whole* source rather than one section (a shared preamble, a global
  caveat) must be carried into each derived task that it governs, not left
  behind in the source.
- **Run a coverage pass before declaring done.** Walk the source unit by unit
  (section, bullet, rule, turn) and confirm each is represented; report
  rewrites, merges, and intentional expansions explicitly, and surface anything
  not yet covered for the user to decide.
- **Leave the source's disposition to the user; never remove it on the skill's
  own initiative.** When the source is a shared asset or a file on disk, the
  skill does not delete, move, overwrite, or truncate it by itself — it reports
  coverage and *proposes* what could happen to the source, and any removal waits
  for the user's explicit say-so. When the source is ephemeral (a live chat
  session, a paste) there is nothing on disk to dispose of, so "disposition"
  here means simply not declaring done until coverage is clean. Either way,
  confirm coverage first, then hand the keep/drop decision to the user.

Frame the trigger by **whether there is a source being mined, not by its format
or by the task count** — explicitly call out that a chat session turned into
tasks is as much a source as a file is, and that producing a single task does
not skip the check. The only thing that scales with source size is how much
work the coverage pass is, never whether it runs. Keep it positive and
action-oriented per repo authoring conventions, and keep it proportional — a few
sentences of policy in the workflow, not a new heavyweight procedure; a thin
direct request resolves the pass in one glance, a rich source takes a real
walk-through.

Non-goal: no script enforces "no meaning lost" — semantic coverage is a
behavioural check the agent performs, not something `lint.py` can mechanically
verify. Do not add a lint rule for it.

## Acceptance

- The lossless-conversion contract is authored once and wired into **both** the
  base `task` skill's `<create>` workflow and the `task_create` skill, so the
  single-task-from-a-source path (which runs through `task_create`, not base
  `<create>`) is covered too. It is scoped to **any source type** (not just a
  document on disk) and states source-wide-content propagation, the unit-by-unit
  coverage pass, and the disposition rule below.
- The disposition rule makes clear the skill never deletes, moves, overwrites, or
  truncates a shared asset or on-disk source on its own — it proposes, coverage
  is confirmed first, and any removal waits for the user's explicit decision.
- The policy is written to fire without the user prompting for it, and to key on
  the presence of a source being mined rather than on its medium or on how many
  tasks result — including the single-task case.
- Covered by evals in `tests/tasks/evals/` spanning more than one source type and
  more than one task-count shape — at minimum a multi-section source doc with a
  shared preamble that yields several tasks, and a source whose relevant content
  collapses into a single task — where the agent preserves every relevant unit's
  meaning, carries source-wide content into each governed task, and reports
  coverage before offering to drop the source. Grow the eval suite in its own
  commit per repo convention.
- `make lint` stays clean (prose-only change).
