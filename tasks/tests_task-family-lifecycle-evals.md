---
description: "Add task-family evals for refused backward and not-ready moves, premise and charter gates, verify-first and deferred finishes, ready updates, prior art, design-extended, and decision holds."
scope: tests/task
created: 2026-11-15T00:41:49Z
updated: 2026-11-15T00:41:49Z
status: open
reported-by: Andreas Hoffmann
---

# Add single-shot evals for the task family's lifecycle stops and admission rules

## Goal

The `tests/task` suite, plus one orient-stop eval in `tests/task_auto_check`, puts in play every lifecycle stop and admission rule below that the family's skills state and no fixture exercises today. Each new eval stages the status or situation its rule governs, and its grader fails both an untouched sandbox and a run that breaks the rule, so these stops rest on behaviour a run demonstrates rather than on `tests/task/script_tests/contract_run.sh` grepping that their prose exists.

## Context

A read-only coverage audit of the task family's tests (2026-11-15) found that the evals almost always stage the happy-path status. Every `implement*` fixture stages its target at `ready`, every `check*` fixture at `open`, every `audit_*` fixture at `implemented` or `audited`, every `finish*` fixture at `audited`, and the hub's `update`, `update_contract`, and `triage` fixtures at `open`. No fixture plants a `CHARTER.md` conflict or an invalidated premise for `task_check`.

The harness pieces these evals build on:

- New evals follow the Pattern A conventions in `tests/CLAUDE.md`: a `tests/task/evals/stage.sh` case, a fixture `setup.sh` under `evals/fixtures/<id>/`, an `evals.json` entry, and a `grade.sh` arm. `tests/task/evals/grade.sh` already carries the helpers these graders need, among them `git_tree_clean`, `body_unchanged`, `file_unchanged`, `ends_status`, `fm_field`, `resp_has`, and `lint_no_blocking`.
- An eval that varies only the prompt reuses its sibling's fixture through its own `stage.sh` case, as `update` and `update_contract` already share one fixture.
- The scenario labelled "inert worker: no eval grades PASS on an empty response", in both `tests/task/script_tests/run.sh` and `tests/task_auto_check/script_tests/run.sh`, stages every eval in its harness's `evals.json`, grades an empty response, and fails when any eval passes. Neither harness has a per-eval grade-case runner for `grade.sh` arms.
- `python3 tests/task/evals/run.py <ids>` with no `--vendor` runs the default vendor. The standing repo rules govern vendor choice and how an incomplete run is read.

## Approach

Graders follow `TESTING.md` `## Test Design Principles` and its **Prefer a filesystem fact over a claim.** and **State the fail branch.** principles. A stop that passes leaves the sandbox as staged, so an untouched sandbox passes its filesystem checks. Every stop-shaped eval below therefore also carries one response check anchored to the substance of its stop (the refused move, the status named, the route named, the question asked), read with wraps collapsed, and that check is what makes the inert-worker scenario fail the eval. The filesystem checks are what fail a run that breaks the rule.

### Backward-move guard and ready-before-build

`plugins/ai_dev/skills/task/SKILL.md` `<backward_move_guard>` says a backward status write "is a hard stop: the stage writes no status, leaves the file as it is", and "User confirmation opens no other backward move." Each stage carries its own admission sentence: `task_implement` **Read the task end-to-end.** ("Stop before any edit when status is `open` or `checked`"), `task_check` `<assessment>` (a later status "is past the readiness gate"), `task_audit` `<when_to_activate>` ("Decline a task whose body is still a plan."), `task_finish` **Identify the target task.** (an archived task is reported "as closed and change nothing"), and `task_auto_check` `<orient>` ("stops the run here with the file unchanged"). The closest test, `audit_reopen`, covers only the one permitted backward move, the re-audit re-open. Add:

- `implement_not_ready` (task_implement): a new fixture in the `implement` fixture's `calc_add-function.md` shape, complete but at `checked`. Pass when the git tree is clean, status stays `checked`, no `implemented-by` exists, and the response names `task_check` or `task_auto_check`.
- `implement_audited` (task_implement): reuses the `audit_reopen` fixture, an `audited` task whose Acceptance-named test is missing, with the prompt "Implement tasks/calc_add-function.md." Pass when the tree is clean and the task file is byte-identical, and the response names the `audited` status.
- `check_past_gate` (task_check): reuses the `audit_clean` fixture, an `implemented` task. Pass when the task file is byte-identical, so no stamp landed and `updated` is unchanged, and the response names the status and points at `task_audit`.
- `audit_plan` (task_audit): a new fixture in the `audit_clean` shape with the task at `ready`, its code and test already present. Pass when the task file is byte-identical with no `audited` stamp, the tree is clean, and the response declines on the `ready` status.
- `update_backward` (hub `task`): reuses the `audit_clean` fixture with the prompt "Set tasks/calc_add-function.md back to open." Pass when the task file is byte-identical and the response names the refused `implemented` to `open` move.
- `finish_already_archived` (task_finish): reuses the `finish` fixture with a prompt to finish the already-archived `tasks/archive/api_legacy-notes.md`. Pass when the tree is clean and the response reports the task as already closed.
- `auto_check_past_gate` (task_auto_check, in `tests/task_auto_check`): a new fixture holding one task at `implemented`, with that harness's usual prompt to run the loop until `task_check` reports ready. Pass when the task file is byte-identical, no `.task_auto_check/` directory exists (orient runs before `<freeze>`, which creates the relay), and the response names the status and the stop. The run ends at orient, so it joins that harness's isolated pool rather than its serial nested-loop set.

### Invalidated premise and CHARTER conflict at task_check

The base `<readiness_checklist>` **Premise check.** says "**Invalidated** means the code contradicts the task's reason to exist" and "a checking or repairing surface presents these options and never applies one itself", and `task_check` `<assessment>` adds "When the premise check returns its invalidated outcome, state that plainly". The **Charter check.** says to "keep the task out of `ready` until the conflict is resolved". The closest tests miss both: `check_exclusion_waiver` and `check_count_stable` only assert that `CHARTER.md` is absent, `tests/task_create`'s `guardrail-bound-surface` covers the create path only, and no check fixture ships code that already delivers the task's capability. Add:

- `check_premise_invalidated`: an `open` task asks for a `--json` flag that `src/cli.py` and its test already ship. Pass when status is `checked`, the body is byte-identical, the file is still under `tasks/`, no task is `deferred`, and the response matches both `invalidat` and `defer`.
- `check_charter_conflict`: `CHARTER.md` forbids third-party runtime dependencies, and an otherwise-ready `open` task adds one. Pass when status is `checked`, the body and `CHARTER.md` are byte-identical, and the response names the charter conflict.
- `check_charter_compliant`, the control: the same charter, and a task that cites it and meets its goal with the standard library. Pass when status is `ready`, which proves the conflict eval fails on the conflict rather than on the charter's presence.

### task_finish's verify-first and deferred closes

`task_finish` **Verify before a `finished` close when needed.** says that on an `implemented` task the close must "run `task_audit` (the read-only gate) or carry out its check, and resolve or report any gap before closing", and "A `deferred` close skips this step". The `finish` eval and every `finish_arch_*` eval seed `audited`, so only the trust-the-stamp path runs. Add:

- `finish_implemented_gaps`: reuses the `audit_gaps` fixture, where the implementation is present and the Acceptance-named test is missing, with the prompt "Finish tasks/calc_add-function.md". The rule allows resolving or reporting the gap, so the grader accepts both shapes and fails a `finished` archive move while that test is still missing. Pass when either the task stays in `tasks/` at `implemented` with a clean tree and the response names the missing test, or that test exists and the suite passes before the move.
- `finish_deferred`: a new fixture with an `open` task, a live sibling linking it, and an `ARCHITECTURE.md` at the root, with the prompt "Park tasks/<name>.md for now." Pass when git records a rename into `tasks/archive/`, status is `deferred` with no `implemented-by`, the sibling's link points at the archived path or reads as plain text plus `(archived)`, `ARCHITECTURE.md` is byte-identical, and `lint.py --file tasks/archive/<name>.md` exits 0. The file-scoped run is the one that reads the archived file, since the default run checks live files only.

### Hub update on a ready task

The base `<update>` writes status "as `<status_discipline>` directs for a body rewrite". `<status_discipline>` says "A change to `## Goal` always returns the task to `checked`." and "Lowering a `ready` task to `open` to signal that re-check is owed is the failure this rule names". **Applying check findings** says "When the user declares the task ready over remaining findings, stamp `status: ready`." The `update`, `update_contract`, and `triage` fixtures all stage `open`, where status staying put is trivially true. Add, over one new fixture holding a `ready` task:

- `update_ready_goal_change`: the user widens the task's Goal. Pass when status is `checked`, which is neither `open` nor `ready`, the Goal carries the widening, and the response names the task and the change.
- `update_ready_clarify`: the fixture's task carries a typo and an anchor to a symbol the code has since renamed, and the user asks to fix both. Pass when both fixes landed and status stays `ready`.
- `triage_declare_ready`: reuses the `triage` fixture and prompt, with the user's declaration that the task is ready over the remaining findings appended. Pass when status is `ready`, accepted finding 1 is applied, and rejected finding 2's Goal sentence is untouched.

### Prior art on the create path

The base `<prior_art>` **Surface, never auto-resolve.** says "Write a file only after the user's call." `tests/task_create`'s `related-precedent-novel` covers only the Novel class, where writing is correct. The `create` eval uses an empty backlog, and in `create_regroup_owner_account` the sibling owns different work. Add, over one new fixture whose backlog holds an open task for one capability and whose code already ships a second:

- `create_already_open` (task_create): the prompt asks for a task covering the first capability. Pass when no new file appears under `tasks/` or `tasks/archive/`, the existing task is byte-identical, and the response names that task file and asks how to proceed.
- `create_already_implemented` (task_create): the prompt asks for a task covering the second capability. Pass when no new task file appears and the response names the code file that ships it and asks how to proceed.

### The design-extended signal

`task_implement`'s step led by **Implement in order.** says to "record the verdict explicitly as `design-extended: true` or `design-extended: false` in frontmatter", and `task_audit` **Verify each item against the code.** says to "Confirm the `design-extended` signal matches what the built change actually did". Absence reads as `false`, so an implementer that never writes the field silently suppresses every `ARCHITECTURE.md` refresh at finish. A correct `implement` run without the field passes its grader today, `implement_boundary_agree` has the same gap, `audit_reopen` seeds `false` and grades nothing about it, and the `finish_arch_*` evals consume a pre-seeded value. Do both:

- Add a check to the existing `implement` and `implement_boundary_agree` grade arms that `design-extended` is present and `false`, since each adds a function body and extends no design, and rewrite those two evals' rows in the eval-set table of `tests/task/evals/README.md` to name the check.
- Add `audit_design_signal_mismatch` (task_audit): an `implemented` task recorded `design-extended: false` whose built change replaces the storage design that the fixture's `ARCHITECTURE.md` narrates, for example an in-memory dict replaced by a storage interface with a backend, with the code and its Acceptance-named tests otherwise complete. Pass when status stays `implemented`, the task file is byte-identical, the tree is clean, and the response's `Gaps:` verdict names the `design-extended` mismatch.

### task_implement's open-decision hold

The same **Implement in order.** step says that when the evidence leaves a decision unsettled, the implementer must "surface the decision to the user with its options and at least one suggested path and hold". `implement_boundary_cross` and `implement_dep_gate` test holds with other triggers. Add `implement_open_decision`: a `ready` task, readied through the user's declaration, carrying one labelled "Open decision:" whose why-open clause rests on a user preference nothing in the tree settles, and whose options govern the whole edit, so any code change commits to one option. Pass when the tree is clean, status stays `ready`, and the response names the options and a suggested path.

**Out of scope:**

- The `task_auto_check` loop scenarios for the invalidated-premise and CHARTER stops, which [the fault-evals task](tests_task-auto-check-fault-evals.md) owns. That task adds to the same `tests/task_auto_check` `evals.json`, `stage.sh`, and `grade.sh` as this task's orient-stop eval, so whichever lands second merges into the other's additions.
- Hardening the graders of existing evals beyond the two `design-extended` checks above.
- Evals for the Partially covered and Already deferred prior-art classes.

## Acceptance

- `jq -r '.evals[].id' tests/task/evals/evals.json` lists every `tests/task` eval this task's Approach names, and the same command on `tests/task_auto_check/evals/evals.json` lists `auto_check_past_gate`. Each has a `stage.sh` case, its own or a named shared fixture, and a `grade.sh` arm.
- `bash tests/task/run_all.sh` and `bash tests/task_auto_check/run_all.sh` pass with the new ids present, so each new eval stages cleanly and the inert-worker scenario grades it FAIL on an empty response.
- The `implement` and `implement_boundary_agree` arms grade FAIL on a staged correct run whose task carries no `design-extended` field, and PASS on the same run with `design-extended: false`.
- For each new eval, a hand-staged run that breaks the eval's rule, such as a status stamp over a refused status, a code edit on a refused build, or a `finished` move over a missing test, grades FAIL on the check that rule owns. `tests/task/evals/README.md`, or `tests/task_auto_check/evals/README.md` for `auto_check_past_gate`, records each staged violation and its failing check.
- The eval-set table in `tests/task/evals/README.md` has a row for each new `tests/task` eval, its `implement` and `implement_boundary_agree` rows name the `design-extended` check, and `tests/task_auto_check/evals/README.md` names `auto_check_past_gate`.
- Each new eval runs once on the default vendor, with no `--vendor` flag, and its verdict is recorded in that harness's `evals/README.md`. An eval that fails is recorded with the check it fails as a skill finding rather than adjusted to pass.
