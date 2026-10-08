---
description: Isolate git_commit eval TMPDIR per job, run the suite at default 4 workers through the shared Pattern A helper, and prove both vendors on that path.
scope: tests/git_commit/evals
created: 2026-10-04T22:11:10
updated: 2026-10-08T22:06:22
status: open
reported-by: Andreas Hoffmann
---

# Parallelize the git_commit behavioral evals behind a per-job TMPDIR

## Goal

`python3 tests/git_commit/evals/run.py` runs isolated evals concurrently with
`--workers` defaulting to 4. `grade.sh`'s `git_commit_context.*` straggler check
sees only that eval's `TMPDIR`, so two workers cannot fail each other. A Cursor
run at the default, and a Claude compatibility run, both grade the suite. The
user-visible outcome: a nine-eval sweep no longer waits in single file for a
shared `/tmp` scan.

## Context

`tests/git_commit/evals/run.py` walks evals sequentially on purpose: `grade.sh`
scans `${TMPDIR:-/tmp}` for `git_commit_context.*` files newer than
`$target/.eval_started_at`. Two concurrent workers writing those files under a
shared `TMPDIR` cross-talk. `DEFAULT_IDS` is a frozen `"1"`..`"9"` list.
`WORKSPACE` is `tests/git_commit/evals/workspace`, unlike harnesses that write
`tests/<skill>/workspace`.

This task consumes [the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md)
and follows it. Host-instruction isolation stays with
[the language_humanizer isolation task](tests_language-humanizer-worker-isolation.md).

## Approach

Rewrite `evals/run.py` to import the shared helper, `tests/lib/eval_runner.py`: derive ids
from `evals.json`, put run output under `tests/git_commit/workspace`, pass
`--workers` defaulting to `vendor.DEFAULT_PARALLEL_WORKERS`, and give every job
the helper's per-job `TMPDIR`. Keep the vendor path on `vendor.add_vendor_arguments`
/ `vendor.resolve` / `vendor.preflight_auth` / `vendor.stage_skill_tree` /
`vendor.build_print_cmd`. Rewrite the sequential comment rather than leaving it
beside the pool.

Rewrite the straggler scan in `evals/grade.sh` so it uses the job's `TMPDIR`
(the helper sets it) and still fails when that eval left a `git_commit_context.*`
file behind. Rewrite `evals/README.md` and `RUNBOOK.md` to match. Drop this
harness from the sequential lists in `tests/CLAUDE.md` and `tests/AGENTS.md`,
which still name it until this per-job `TMPDIR` conversion lands.

Prove the isolation with a hermetic script-test or helper test that two overlapping
dummy `TMPDIR` trees cannot see each other's `git_commit_context.*` files, then
run the live suite.

**Out of scope:** Adding evals. Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `tests/git_commit/evals/run.py --help` shows `--workers` defaulting to 4.
- `grade.sh` greps no shared `/tmp` without `TMPDIR`; the straggler `find` runs
  against `$TMPDIR`.
- Default ids come from `evals.json`, so adding an eval runs it without editing
  a frozen list.
- `python3 tests/git_commit/evals/run.py --vendor cursor --workers 4` (or the
  default) and the same command with `--workers 1` both print a graded summary
  over every id; prefer Cursor per `TESTING.md`. A `--vendor claude` pass at
  `--workers 1` or 4 remains a compatibility sample.
- Two overlapping `timing.json` `duration_s` windows exist in a `--workers 4`
  `--force` run of at least two uncached evals, proving concurrency, recorded
  in the harness `results/` notes this change adds.
