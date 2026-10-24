---
description: "Add git_auto_review: a loop that runs git_review as its gate, fixes qualifying findings with verified agents, and stops under scope, severity, regression, decision, and round-cap rules."
scope: plugins/ai_dev
created: 2026-10-24T20:48:07
updated: 2026-10-24T20:48:07
status: open
reported-by: Andreas Hoffmann
---

# Add git_auto_review, an automated review-and-fix loop around git_review

## Goal

Add `git_auto_review`, an opt-in loop beside `git_review` that does for a finished change what `task_auto_check` does for a task. It runs `git_review` verbatim as its only gate, fixes the findings that qualify through a single writer agent, verifies each round's fixes refute-by-default, re-reviews the delta, and repeats until the review is clean or a stop rule fires. Every fix stays in the working tree, uncommitted. The loop carries five convergence rules from the start, which the Approach defines: a scope anchor, a severity floor, a regression ledger, routing of owner decisions, and a stop rule.

## Context

The user ran `git_review` by hand in rounds with fixes in between throughout October 2026. One change, the git_review secret scan, took nine review rounds and eleven fix rounds in one day. Each round surfaced defects earlier rounds had missed, defects the previous fix had introduced, and requests to extend scope to new input shapes and pre-existing configuration behaviour. Across 34 tasks studied from 2026-09-24 to 2026-10-24, fix rounds introduced about 40 of the 280 findings raised after readiness. Reviews also found what audits had passed, because a review builds adversarial inputs, which is the value this loop automates and the reason it needs explicit convergence rules. The review findings that drove those rounds came from a frontier-model review; the new agents inherit the orchestrator's model like the task family's agents.

The gate is `plugins/ai_dev/skills/git_review/SKILL.md`. Its report sorts findings under "What is critical", "Bugs it may introduce", and "What should be fixed though it is not a clear bug", labels each `verified` or `inferred` and marks the non-blocking ones, and keeps "Decisions the implementer must make before fixing" in a section of its own. On a delta re-review its `<tags>` rule tags every prior finding closed, open, open and not acknowledged, settled by a decision, or regressed, and tags a defect first seen in the delta `new`. `git_review` edits the branch only on an explicit request in the current turn; invoking this loop is that request.

The shape to mirror is `plugins/ai_dev/skills/task_auto_check/SKILL.md`: `<single_gate>`, `<relay>`, `<verification_standard>`, `<audit_delta>`, `<concurrent_modification_guard>`, `<agent_failure_policy>`, and `<loop_bounds>`, with its agents under `plugins/ai_dev/agents/` and the doctrine in `wiki/concepts/agent-delegated-automation.md`.

The boundary with [the autonomous implement loop](task-family_autonomous-implement-loop.md): its `task_auto_implement` runs implement, audit, re-implement on findings, and finish, and its audit answers whether the task was built. `git_auto_review` answers whether the change is correct and mergeable. It runs after a clean audit, or on any change the user names with no task at all, and neither loop re-runs the other's gate.

## Approach

1. **Write the front end** at `plugins/ai_dev/skills/git_auto_review/SKILL.md`, named `<family>_auto_<rest>` beside the manual `git_review` per the standing repo rules. It accepts the targets `git_review` accepts that live in the local working tree: the default branch's uncommitted changes and unpushed commits, or a checked-out branch. It takes two optional inputs: a task file path that anchors scope, and a positive integer that overrides the round cap.
2. **Write three agents** under `plugins/ai_dev/agents/`, named `auto_<role>_git`:
   - `auto_gate_git` runs `git_review` verbatim, a first review and then delta re-reviews. It returns the report followed by a structured verdict: each finding's id, heading, `verified` or `inferred` label, non-blocking mark, location, `Fix:` sentence, and re-review tag, plus the decisions list. It writes no file.
   - `auto_fixer_git` is the single serialized writer. For each approved finding it makes the fix in the working tree and adds or extends a reproduction, a test or a command that fails before the fix and passes after, and appends that reproduction to the run's regression ledger. It writes only the finding's location, the reproduction, and the ledger.
   - `auto_verifier_git` is read-only and refute-by-default. In triage mode it approves the findings that qualify under the convergence rules, with a reason for every finding it does not approve. In delta mode it maps every hunk of the round's diff to an approved finding id or its reproduction and marks any other hunk `unmapped`.
3. **State the convergence rules once** in a `<convergence>` block of the skill:
   - **Scope anchor.** A finding qualifies only when it concerns lines the change added or modified, or behaviour the change's intent covers, read from the anchoring task's Goal and Acceptance when a task file is given. A pre-existing issue and a scope extension go to the report as follow-up task proposals.
   - **Severity floor.** Findings under "What is critical" and `verified` findings under "Bugs it may introduce" qualify. `inferred` findings and findings under "What should be fixed though it is not a clear bug" are listed in the report.
   - **Regression ledger.** The ledger is `ledger.txt` in the run's relay directory, one reproduction command per line. A bundled script, `scripts/run_ledger.sh`, runs every line and reports each line's pass or fail, and the orchestrator runs it after every fix round. A failing line restores the round's pre-fix state and repeats the round once with the failing line named to the fixer; a second failure restores the pre-fix state and stops the run.
   - **Decisions.** Every entry under "Decisions the implementer must make before fixing", and every finding whose fix depends on one, goes to the user and receives no fix. When a task file anchors the run, the report gives the wording to record in that task, applied through the base `task` skill's `<update>` workflow on the user's answer, with the base `<status_discipline>` rule deciding the status.
   - **Stop rule.** The run stops when no qualifying finding remains, when a decision is pending, at a cap of 5 rounds unless overridden, after two consecutive rounds whose qualifying findings all sit in code the loop wrote in an earlier round, and on a helper failure.
4. **Keep the run safe and reversible.** Relay files live under `.git_auto_review/<run-stem>/` with a `.gitignore` of `*`; prompts name inputs by path and returns are saved byte for byte, as in `task_auto_check`. Save each round's pre-fix state as a patch of tracked changes plus a copy of untracked files, so a restore never touches committed history. Carry over the concurrent-modification guard and the helper-failure policy, and validate edits against `CHARTER.md` before writing when it exists.
5. **Route and register.** Add a routing line to `git_review`'s `<when_to_activate>` that sends an automated review-and-fix request to `git_auto_review`. Register the skill and the three agents as the standing repo rules for adding a skill and agents require, and record the loop as a worked instance in `wiki/concepts/agent-delegated-automation.md` through the wiki skill family.
6. **Build the tests** as a new harness `tests/git_auto_review/` in the skill-creator-aligned Pattern A layout the standing repo rules name, with `script_tests/run.sh` for `run_ledger.sh` and three behavioral evals run without `--vendor`.

**Out of scope:**

- Calling `git_auto_review` from `task_auto_implement` as its final stage, which the autonomous implement loop task owns along with the convergence of its own implement and audit rounds.
- Committing, pushing, posting a review comment, or resolving a review thread.
- Filing follow-up tasks, which stays the user's call on the proposals the report lists.
- Reviewing or fixing a pull request that is not checked out locally.

## Acceptance

1. `plugins/ai_dev/skills/git_auto_review/SKILL.md` exists with its directory name, frontmatter `name:`, and H1 aligned, and its `<convergence>` block carries the five bold labels **Scope anchor.**, **Severity floor.**, **Regression ledger.**, **Decisions.**, and **Stop rule.**, each stated only there.
2. `auto_gate_git.md`, `auto_fixer_git.md`, and `auto_verifier_git.md` exist under `plugins/ai_dev/agents/` with the contracts the Approach gives them, and `auto_fixer_git.md` is the only one that may write.
3. `tests/git_auto_review/script_tests/run.sh` proves `run_ledger.sh` exits 0 on an all-passing ledger and on an empty ledger, and exits non-zero naming the line number of a failing entry, under the bash floor the standing repo rules set.
4. Eval `fixes_in_scope_bug`: on a fixture repository whose uncommitted change carries one verified in-scope bug, the run fixes the bug, the ledger holds a reproduction that fails on the fixture's original change and passes after, the delta re-review tags the finding closed, the run stops clean, and `git rev-parse HEAD` reads the same before and after.
5. Eval `lists_preexisting_issue`: on a fixture whose change sits beside a pre-existing defect outside the changed lines, the defect's file is byte-identical after the run and the report lists the defect as a follow-up task proposal.
6. Eval `routes_decision`: on a fixture whose review yields a decision, the run stops for the user and the files the decision governs are byte-identical after the run.
7. `git_review`'s `<when_to_activate>` routes an automated review-and-fix request to `git_auto_review`; the plugin README, the root README layout tree, both plugin manifests, and both marketplace registrations name the new skill and agents; the test inventories name the new harness; and `wiki/concepts/agent-delegated-automation.md` names the loop.
