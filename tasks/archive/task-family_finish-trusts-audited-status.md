---
description: Make task_finish status-aware so a current `audited` task skips the redundant codebase re-verification, while a direct `finished` close on a never-audited task still verifies.
scope: plugins/ai_dev/skills/task_finish
created: 2026-06-29T18:42:31
updated: 2026-06-30T21:53:21
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# task_finish trusts a current `audited` stamp instead of re-running the audit

## Goal

On the canonical `… → implement → audit → finish` chain, `task_finish` stops
repeating the codebase verification that `task_audit` just completed. When the
task arrives carrying a current `status: audited` — the lifecycle's record that
`task_audit` confirmed every body item, every `## Acceptance` check, and every
required test against the code — `task_finish` treats the codebase-verification
gate as already satisfied and proceeds straight to the close-out, naming in its
report that the close relied on that audit. The user-visible outcome is that
finishing an audited task no longer re-walks the code and re-runs the suite, so
it completes quickly, while a direct close on an unaudited task keeps its full
safety.

The verification still runs where `task_finish` is the *only* gate — a direct
`finished` close on an `implemented`, never-audited task — and a `deferred`
close still performs no verification at all.

## Context

The redundancy lives in `task_finish`'s `<workflow>` step 3, the **Verify
before a `finished` close** step in `plugins/ai_dev/skills/task_finish/SKILL.md`.
It currently directs an *unconditional* re-verification — "run `task_audit` …
or carry out its check" — with no awareness of the task's current status, so it
repeats the full code walk and suite run even when `task_audit` ran moments
earlier and stamped the task.

`task_audit` already produces the handoff token. On a clean, complete verdict
over a current `implemented` task it stamps `status: audited` and points at
`task_finish` to close out (the **Stamp only a clean current implementation**
step and the `<output_contract>` hand-off in
`plugins/ai_dev/skills/task_audit/SKILL.md`). The base skill defines that token:
the `audited` status entry in `<frontmatter>` and the
`<lifecycle_responsibility>` note in `plugins/ai_dev/skills/task/SKILL.md` both
record that `audited` *means* the audit confirmed the work against the code. The
missing half is purely on the finish side — step 3 ignores the stamp it should
consume — so the fix is localized to `task_finish` and leaves `task_audit`'s
existing hand-off as-is.

This restores the original design intent. The task that introduced the skill
stated finish should let a user "close without re-running a full audit" (the
**Audit verifies; finish acts** rationale in
[task-skill_finish-sibling-skill.md](task-skill_finish-sibling-skill.md));
a later lifecycle pass renamed step 3 to the `finished` close and the wording
drifted into the unconditional re-check this task corrects.

## Approach

Rewrite `task_finish`'s `<workflow>` step 3 in place so the verify decision
reads the task's current `status` (already loaded in step 1) and branches:

- **`status: audited`** — the codebase verification already ran and passed.
  Treat the gate as satisfied, skip re-running `task_audit` or its check, and go
  straight to the step-4 close-out. The report names that the close relied on
  the existing `audited` stamp.
- **`status: implemented`** (or any non-`audited` state being closed as
  `finished`) — `task_finish` is the sole verification gate, so run `task_audit`
  or carry out its check exactly as today, resolving or reporting any gap before
  closing.
- **`deferred` close** — performs no verification, unchanged.

Add one staleness guard sentence: `task_finish` trusts a *current* `audited`
stamp (an `audited` task is live in `tasks/`, normally finished back-to-back
with the audit), and when the operator has concrete evidence the code changed
since that audit, finish re-verifies rather than trusting the stamp.

Reflect the reused-audit path in `task_finish`'s `<output_contract>` so a close
that skipped re-verification states it relied on the prior `audited` stamp.

Frame both edits as a rewrite of the existing step-3 and output-contract
passages to one canonical status-aware statement, not an appended alternative.

Non-goals: leave `task_audit`'s verification logic and its existing
finish-pointer hand-off unchanged; leave the base `<archive>` close-out steps,
the status model, the `<backward_move_guard>`, and the `deferred` path
untouched; keep the verification — only gate it on status rather than removing
it. Hold any skill-behavior eval growth for a separate session per the repo's
keep-skill-change-and-harness-expansion-separate rule.

## Acceptance

- `task_finish`'s `<workflow>` step 3 reads the current `status` and branches on
  it: an `audited` task skips re-running `task_audit` and proceeds to the
  close-out, while a non-`audited` `implemented` task closed as `finished` still
  runs the verification. Reading step 3 shows the `audited` status named as the
  skip condition.
- The prior unconditional "run `task_audit` … or carry out its check" wording no
  longer stands as the single path; one canonical status-aware statement
  replaces it, with no second copy of the old phrasing left in the step.
- Step 3 keeps the `deferred` carve-out: a `deferred` close performs no
  verification.
- A staleness guard sentence is present: with concrete evidence the code changed
  since the audit, finish re-verifies rather than trusting the stamp.
- `task_finish`'s `<output_contract>` states that a close which reused a prior
  audit reports it relied on the existing `audited` stamp.
- `task_audit/SKILL.md`, the base `task` skill's `<archive>` steps, the status
  model, and the `<backward_move_guard>` are unchanged — inspection confirms
  those passages carry no edit from this task.
