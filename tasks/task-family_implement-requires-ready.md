---
description: Make task_implement require ready (or implemented for audit-gap repair), refuse open or checked, and gate done on Acceptance-named checks plus cheap surfaces.
scope: plugins/ai_dev/skills/task_implement
created: 2026-10-12T19:02:54
updated: 2026-10-12T20:21:14
status: open
reported-by: Andreas Hoffmann
---

# Require ready before task_implement builds

## Goal

`task_implement` must refuse to start building when the target task is still `open` or `checked`. It builds only when status is `ready`, or when status is `implemented` and the run is repairing concrete `task_audit` gaps. On refusal it stops with no code edit and no status change, names the current status, and routes the user to `task_check` or `task_auto_check`.

Its default verification gate is the same scope: every check `## Acceptance` names, plus the cheap surfaces the repo always runs (`make lint`, the matching script tests, the bundled task linter when relevant). The full behavioral suite is not the default done-gate; it runs only when Acceptance names it, or as an out-of-band regression the operator asks for.

## Context

- **Observed.** Two implement-and-audit sessions (Codex `01a12f8e-ef70-79d3-a5df-5111af08069e` and a later Cursor parent loop) both ran `task_implement` against [the deletion-and-regate task](archive/task-family_readiness-loop-deletion-and-regate.md) while its status was still `open`. Both sessions followed the skill as written: the workflow reads status only to stop on `audited` or archived `finished` / `deferred`, then continues. Neither run hit a hard readiness stop.
- **Not a recent removal.** Commit `b011c11` (2026-10-11, "Ship task status discipline…") added the status read to `task_implement` and the past-implementation stop. It did not add, and git history does not show a prior, hard `ready` precondition in `task_implement`. The gap is a missing gate, not a regression that deleted one.
- **Selector already knows.** `task_select` already maps `ready` → `task_implement` and `open` / `checked` → `task_check` or refinement. The executable implement skill does not enforce that mapping, so a direct "implement this task" request bypasses the spine.
- **Verification-scope conflict.** The same Codex session stalled before audit because it ran the whole ~32-case `task_auto_check` behavioral suite after the Acceptance-named evals had already passed. `task_implement`'s `<role>` says it "runs the full suite clean", while workflow step 7 and the base `<verification_economy>` say to run the verifications Acceptance names (and to treat expensive evals as recorded evidence). That split sent the implementer into hours of unrelated regression work and left the task `open`.
- **Hub intent.** The base skill's lifecycle spine is create → check → implement → audit → finish. `ready` means implementation-ready. The manual sibling must hold that bar, including beside [the autonomous implement-loop task](task-family_autonomous-implement-loop.md), which already assumes a `ready` precondition for its opt-in loop and stays out of this change's scope.
- **Re-entry that must stay open.** `task_audit` routes gaps on an `implemented` task back to `task_implement`. That repair path stays valid. An explicit user override that skips readiness is out of scope; raising status to `ready` stays owned by `task_check`, `task_auto_check`, or the hub's apply-findings readiness declaration.

## Approach

1. **Rewrite the status gate in `task_implement`.** In step 1 of `<workflow>` ("Read the task end-to-end"), replace the current past-implementation-only stop with one admission rule:
   - Proceed when status is `ready`, or when status is `implemented` and the run is repairing named `task_audit` gaps.
   - Stop before any edit when status is `open` or `checked`: name the status, point to `task_check` / `task_auto_check`, and change nothing.
   - Keep the existing stop for `audited` and archived `finished` / `deferred`, routing new work to a follow-up task.
2. **Align the verification scope.** Rewrite `task_implement`'s `<role>` "full suite" sentence in place so it matches workflow step 7 and the base `<verification_economy>`: the done-gate is every Acceptance-named check plus the cheap repo surfaces; the full behavioral harness is not required unless Acceptance names it or the operator asks for that regression. Keep `task_audit`'s read of the same named surfaces consistent with that scope (it already inherits `<verification_economy>`).
3. **Cite the hub once.** Add a short citation in the base `task` skill's `<lifecycle_responsibility>` or `<status_discipline>` (whichever already names implement's write) so the ready-before-build rule lives once in the hub and the sibling cites it, matching family authoring conventions.
4. **Align the wiki.** Update `wiki/concepts/task-lifecycle-and-status-rules.md` through the wiki skill family so the before-implementation section states that `task_implement` admits only `ready` (and `implemented` for audit-gap repair), and that its default verification gate is Acceptance-named plus cheap surfaces.
5. **Pin it.** Extend `tests/task/script_tests/contract_run.sh` (or the implement-skill contract surface that already pins status reads) so a grep fails if the ready-admission stop or the Acceptance-named verification-scope wording disappears from `task_implement`. Add or extend a behavioral eval under `tests/task_implement/` only if that harness already exists; otherwise the script-test pin is enough for this change.

**Out of scope:** building `task_auto_implement`; changing `task_select`'s ranking; auto-running `task_check` inside `task_implement`; changing default timeouts, parallelism, or sandbox relocation for the behavioral harnesses.

## Acceptance

1. `task_implement`'s status gate admits only `ready` and audit-gap repair on `implemented`, and stops with no edit on `open` and `checked`, naming the status and routing to `task_check` / `task_auto_check`.
2. The past-implementation stop for `audited` / archived `finished` / `deferred` still holds.
3. `task_implement`'s `<role>` no longer treats the full behavioral suite as the default done-gate; it states Acceptance-named checks plus cheap surfaces, in agreement with workflow step 7 and `<verification_economy>`.
4. The hub carries one canonical statement of the ready-before-build rule, and `task_implement` cites it rather than inventing a second copy.
5. The lifecycle wiki page states the admission rule and the default verification scope, and the update ran through the wiki skill family.
6. The contract script test fails if the ready-admission wording or the Acceptance-named verification-scope wording is removed from `task_implement`, and `make lint` plus that script surface pass.
