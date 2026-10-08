---
description: Delete the two one-time git diff --quiet guards from the charter_guardrail script tests so the suite judges file content and passes while an unrelated edit sits uncommitted.
scope: tests/charter_guardrail
created: 2026-10-08T17:28:56
updated: 2026-10-08T23:10:51
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Retire the git-state guards in the charter_guardrail script tests

## Goal

Delete the two one-time `git diff --quiet` guards from `tests/charter_guardrail/script_tests/run.sh`, so the suite's verdict rests on file content and the suite passes while an unrelated edit to one of the guarded files sits uncommitted in the working tree.

## Context

Near its end, `tests/charter_guardrail/script_tests/run.sh` runs two guards that compare the working tree with the index:

- `git -C "$REPO_ROOT" diff --quiet -- deployment/deployment.conf`, which fails with "deployment.conf should remain unchanged";
- `git -C "$REPO_ROOT" diff --quiet --` over `plugins/ai_dev/skills/task_create/SKILL.md`, `plugins/ai_dev/skills/task_check/SKILL.md`, and `plugins/ai_dev/skills/task_implement/SKILL.md`, which fails with "Manual task-chain skills should remain unchanged by this hook task".

Both guards implement acceptance items of [the charter-hook task](task-family_charter-guardrail-for-autonomy.md), which required those files to stay unchanged from before that task while it shipped the charter hook. That task is finished, and neither guard protects a standing invariant today. `deployment/deployment.conf` no longer carries the Claude `disallow:**` rule the first guard was written for, and it has changed in several later commits. The guarantee behind the second guard, that the manual create, check, and implement chain gains no charter requirement, rests on presence-gated charter reading, which `tests/task/script_tests/contract_run.sh` already pins by asserting the hub sentence "When `CHARTER.md` exists at the project root, validate the task content against its boundaries and invariants".

The script's `fail()` helper aborts at the first failed assertion, so either guard stops the whole suite during any session that edits one of the guarded files, and the suite passes again only once the edit is staged or committed. On 2026-10-08 a run with an uncommitted `task_create` edit failed at the second guard, while a copy of the script with both guards removed ran to its closing `ok` line on the same tree.

## Approach

Delete both guard statements, each `git -C "$REPO_ROOT" diff --quiet` call together with its `|| fail` line, and keep every other assertion in the script as it stands, including the content checks "Claude plugin manifest should not declare a hooks key" and "task_charter skill should not exist".

## Acceptance

- `git diff -- tests/charter_guardrail/script_tests/run.sh` shows deleted lines only, and they are exactly the two guard statements: both `git -C "$REPO_ROOT" diff --quiet` calls with the `fail "deployment.conf should remain unchanged"` and `fail "Manual task-chain skills should remain unchanged by this hook task"` lines.
- With a temporary uncommitted whitespace edit to one of the formerly guarded files (`deployment/deployment.conf` or one of the task-chain skill files the second guard named), `bash tests/charter_guardrail/script_tests/run.sh` exits 0 and prints its closing `ok` line. Revert the temporary edit after the run.
