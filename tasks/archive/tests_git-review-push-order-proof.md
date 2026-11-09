---
description: Log the push in the git_review push_approval fixture and keep the run's report draft in the sandbox, so eval 41 grades warning-before-push and post-push re-reads deterministically.
scope: tests/git_review
created: 2026-10-02T08:23:20Z
updated: 2026-10-03T19:09:02Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Grade the git_review push-warning order from logs

## Goal

Eval 41 in the `git_review` harness proves the order the parent task's push-approval acceptance item names: the warning about the at-risk approval exists before the push runs, and the checks and the merge state are read after it. The grader reads both facts from artifacts the run leaves behind, a push line in `gh_calls.log` and the report draft's modification time, so neither one stays an `agent-attest` line.

## Context

The fixture `tests/git_review/evals/fixtures/push_approval/setup.sh` stages an approved pull request, a ruleset with `dismiss_stale_reviews_on_push`, and one unpushed commit. The stub `gh` logs every forge call to `gh_calls.log`, but the push itself travels to the fixture's bare origin through an `insteadOf` rewrite and leaves no line in any log. The `41)` case in `tests/git_review/evals/grade.sh` counts check reads and leaves the warning order as an attest line.

The skill's `<draft_the_report_to_a_file>` writes `report.md` into the collector's evidence directory before any side-effecting stage, a push included. The collector creates that directory with `mktemp` under `${TMPDIR:-/tmp}`, outside the eval target, so the grader cannot find it. `tests/git_review/evals/run.py` folds every line of a fixture's `gh_env` file into the worker environment. One audited run on 2026-10-01 shows the signal is there to read: its `report.md`, carrying the warning, was written three seconds before the origin ref moved.

The harness runner is already vendor-aware. Fresh proof runs use `--vendor cursor` per `TESTING.md`.

## Approach

Install a `post-receive` hook in the fixture's bare origin that appends one line per updated ref to the fixture-root `gh_calls.log` that `write_gh_env` sets as `GH_STUB_LOG`. The hook does not inherit `gh_env`, so it appends to `$GIT_DIR/../gh_calls.log`. Each line is `push <ref> <epoch>` with `<epoch>` a Python float from `python3` `time.time()`, for example `push refs/heads/feature/export <epoch>`. Have the fixture add a `TMPDIR` line to its `gh_env` that points into the eval target, so the evidence directory and `report.md` land inside the sandbox for this eval alone.

Rewrite the `41)` case in `grade.sh` in place, replacing the attest line and the count-based checks-reread with three checks. The log carries a line matching the prefix `push` plus a trailing space. A checks read and a merge-state read (mergeable or `mergeStateStatus`) both follow that line in the log. A `report.md` under the eval target contains the dismissal warning, and `grade.sh` obtains both that file's `st_mtime` and the push line's epoch through `python3` as floats and passes the warning-order check when `st_mtime` is strictly less than the epoch. Rewrite the eval 41 expectations in `evals.json`, its entry in `tests/git_review/evals/README.md`, and the `push_approval` fixture row in place to match.

## Acceptance

- A push to a staged `push_approval` origin appends one line matching `push refs/heads/feature/export` plus a trailing space and a `python3` `time.time()` float epoch to `gh_calls.log`, after the forge calls made before it.
- A collector run inside an eval 41 worker environment writes its evidence directory under the eval target.
- Grading a staged sandbox whose log has no checks read after the push line fails the re-read check, grading one whose log has no merge-state read after the push line fails the re-read check, and grading one whose `report.md` lacks the dismissal warning or whose `report.md` `st_mtime` is not strictly less than the push-line epoch fails the warning-order check.
- Eval 41 passes on a fresh `python3 tests/git_review/evals/run.py --vendor cursor 41` run with the three Approach checks in place of both `attest "the warning was emitted before the push ran"` and the count-based checks-reread.
- The eval 41 expectations in `evals.json`, the ### 41 entry in `tests/git_review/evals/README.md`, and the `push_approval` fixture-table row each name the `gh_calls.log` push line and the `report.md` modification time as the order proofs, and prior agent-attest wording is gone.
- The warning-order check in the `41)` case of `tests/git_review/evals/grade.sh` requires that a `report.md` under the eval target contains the dismissal warning, obtains both that file's `st_mtime` and the push-line epoch through `python3` as floats, and passes when `st_mtime` is strictly less than the epoch.
