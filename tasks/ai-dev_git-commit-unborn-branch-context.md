---
description: Make git_commit's prepare context succeed on an unborn branch by guarding recent-commits log, auditing sibling HEAD-dependent calls, and adding a durable unborn-branch script-test.
scope: plugins/ai_dev/skills/git_commit
created: 2026-10-14T16:21:22
updated: 2026-10-15T16:10:46
status: checked
reported-by: Andreas Hoffmann
---

# Fix git_commit context on an unborn branch

## Goal

`prepare_commit_context.sh` completes on a repository whose current branch has no commits yet (an unborn branch, before the root commit): it exits 0, prints the three stdout lines, and writes a context file whose `<recent_commits>` block carries a `(no commits yet)` placeholder instead of failing. The same root-commit case is audited across `commit_with_message.sh` and every other `git log` / `HEAD`-dependent call in the skill, and a durable script-test scenario proves the prepare path on a throwaway-shaped tree (one staged file, no commits). This is the point-fix for the unborn-branch failure that forced the skill's manual fallback on 2026-10-14 during a new repository's first commit.

## Context

**Failure.** On an unborn branch, `prepare_commit_context.sh` exits non-zero and prints `fatal: your current branch '…' does not have any commits yet`. The skill's `<fallback_trigger>` then opens `references/manual_fallback.md`. The unguarded call is the `print_command_output "recent_commits"` block that runs `git --no-pager log --oneline -8` under `set -euo pipefail`, so a failing `git log` aborts the whole script. Staged diffs already work there: `git diff --cached` compares against the empty tree when `HEAD` is absent.

**Source of truth.** The skill lives at `plugins/ai_dev/skills/git_commit/` in this repository. Harness skill directories under a user's home are deployed copies, not the edit surface; fix the source here so the next deployment does not overwrite a local patch.

**Sibling surfaces.** `commit_with_message.sh` uses `git rev-parse --show-toplevel` and `git commit -F -`, which already create a root commit on an unborn branch; audit it anyway for any other `git log` / `HEAD` assumption. `references/manual_fallback.md` lists the same `git --no-pager log --oneline -8` recent-commits step, so an agent that already fell back meets the same fatal on an unborn branch unless that step is guarded the same way.

**Harness helper today.** `tests/git_commit/script_tests/run.sh`'s `fresh_repo` always seeds one commit so `HEAD` exists; the unborn case needs a separate fixture shape.

## Approach

1. **Guard recent commits in prepare.** Rewrite the `print_command_output "recent_commits"` call in `plugins/ai_dev/skills/git_commit/scripts/prepare_commit_context.sh` so that when `git rev-parse --verify -q HEAD` fails, the `<recent_commits>` block still opens and closes and its body is the single line `(no commits yet)`; when `HEAD` exists, keep writing `git --no-pager log --oneline -8` as today. Keep the rest of the context blob unchanged.

2. **Audit the rest of the skill.** Walk `commit_with_message.sh`, `SKILL.md`, and `references/manual_fallback.md` for every `git log` / `HEAD`-dependent call that would fail on an unborn branch. Change each one that fails, using the same `git rev-parse --verify -q HEAD` gate and the same placeholder where a recent-commits listing is the intent. Leave calls that already succeed without `HEAD` (for example `git rev-parse --show-toplevel`, `git diff --cached`, and a root `git commit`) alone.

3. **Prove with a durable script scenario.** In `tests/git_commit/script_tests/run.sh`, add a scenario that builds a throwaway-shaped repository (`git init`, one staged file, no commits), runs `prepare_commit_context.sh`, and asserts exit 0, the three stdout lines, an existing context file, and a `<recent_commits>` body of `(no commits yet)`. Extend that scenario through `commit_with_message.sh` when the audit leaves that script's root-commit path unchanged, asserting the piped message becomes `HEAD`. Register the scenario in the harness's scenario list the same way its neighbors are.

**Out of scope:**

- Changing the skill's commit-message format, drift guard, or pre-flight obligations.
- Editing only a deployed harness copy under a user's home without updating this repository's source.
- Operator redeploy messaging and version bumps after the source fix lands — the standing repo deploy and versioning rules own that; this task delivers the source fix and script-test only.

## Acceptance

- In a temporary directory, `git init`, create and `git add` one file, leave the branch with no commits, and run `plugins/ai_dev/skills/git_commit/scripts/prepare_commit_context.sh` from that tree: the script exits 0, prints three stdout lines (context path, byte size, consumption directive), and the context file at the printed path contains a `<recent_commits>` … `</recent_commits>` block whose body is exactly `(no commits yet)`.
- `grep -n 'git --no-pager log --oneline -8' plugins/ai_dev/skills/git_commit/scripts/prepare_commit_context.sh` either returns no match, or every remaining match sits behind a `git rev-parse --verify -q HEAD` success path so an unborn branch never executes that log.
- Every `git log` / unguarded `HEAD` call the Approach audit finds in `commit_with_message.sh`, `SKILL.md`, and `references/manual_fallback.md` either already succeeds without `HEAD` or is rewritten behind the same gate; an unborn-branch run of `commit_with_message.sh` with a non-empty piped message and a valid context path from prepare exits 0 and advances `HEAD` to a root commit carrying that message.
- Under `bash tests/git_commit/run_all.sh`, the new unborn-branch script-test scenario passes with the assertions in Approach step 3.
- Existing `tests/git_commit/script_tests` scenarios that already seed a commit still pass under the same `run_all.sh` invocation.
