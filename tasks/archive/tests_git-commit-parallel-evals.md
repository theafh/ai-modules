---
description: Isolate git_commit eval TMPDIR per job, run the suite at default 4 workers through the shared Pattern A helper, and prove that path on the default vendor.
scope: tests/git_commit/evals
created: 2026-10-04T22:11:10
updated: 2026-10-21T18:04:41
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Parallelize the git_commit behavioral evals behind a per-job TMPDIR

## Goal

`python3 tests/git_commit/evals/run.py` runs isolated evals concurrently with
`--workers` defaulting to 4. Each worker's straggler `find` reads that job's
`TMPDIR`. A run on the default vendor, Cursor, grades the suite. The
user-visible outcome: the sweep of the ids `## Approach` derives from
`evals.json` runs concurrently through the helper at
`vendor.DEFAULT_PARALLEL_WORKERS`.

## Context

`tests/git_commit/evals/run.py` walks evals sequentially on purpose: `grade.sh`
scans `${TMPDIR:-/tmp}` with `find "$tmpdir" -maxdepth 1` for `git_commit_context.*` files newer than
`$target/.eval_started_at`. Two concurrent workers writing those files under a
shared `TMPDIR` cross-talk. `DEFAULT_IDS` is a frozen `"1"`..`"9"` list.
`WORKSPACE` is `tests/git_commit/evals/workspace`, unlike harnesses that write
`tests/<skill>/workspace`.

This task consumes [the shared Pattern A eval runner](tests_shared-pattern-a-eval-runner.md)
and follows it. Host-instruction isolation stays with
[the language_humanizer isolation task](tests_language-humanizer-worker-isolation.md).

## Approach

Rewrite `evals/run.py` to import the shared helper, `tests/lib/eval_runner.py`: derive ids
from `evals.json`, put run output under `tests/git_commit/workspace`, pass
`--workers` defaulting to `vendor.DEFAULT_PARALLEL_WORKERS`, and give every job
the helper's per-job `TMPDIR`. Keep the vendor path on `vendor.add_vendor_arguments`
/ `vendor.resolve`, the run's `micro_deploy.preflight_auth`, and each pass's
`micro_deploy.micro_deploy` with `micro_deploy.run_worker`. Rewrite the sequential comment rather than leaving it
beside the pool.

Rewrite the straggler scan in `evals/grade.sh` so the `find` uses the job's `TMPDIR` and keeps `-maxdepth 1` beside `-name 'git_commit_context.*'` and `-newer "$marker"`, where `marker` is `$target/.eval_started_at`, and still fails when that eval left a `git_commit_context.*` file newer than that marker. The eval 6 early return that exits before this scan stays. The job callable receives the helper's environment mapping and, before it returns, copies `TMPDIR`, `TEMP`, and `TMP` onto the micro-deploy environment the worker runs with and passes that same mapping to the `grade.sh` subprocess, as `tests/task_auto_check/evals/run.py` does with `_apply_job_temp` and `grade_env`. Rewrite `evals/README.md` and `RUNBOOK.md` to match. In `tests/CLAUDE.md` under `### Parallel workers: default 4 only where each job has its own sandbox`, and in `tests/AGENTS.md` under `### Parallel workers`, rewrite the sentence `` `task_auto_check` is the runner on `eval_runner` `` in place so each file reads `` `task_auto_check` and `tests/git_commit/evals/run.py` are the runners on `eval_runner` at `vendor.DEFAULT_PARALLEL_WORKERS`. `` The sequential-runner list stays, and only its `git_commit` shared-`TMPDIR` entry is superseded.

Prove the isolation with a hermetic script-test under `tests/git_commit/script_tests` that runs the git_commit straggler scan on two overlapping dummy `TMPDIR` trees, so a `git_commit_context.*` file in one tree stays invisible to the scan of the other. Register that same test as a body function plus a `scenario` line in `tests/git_commit/script_tests/run.sh`, the registration `## Adding a scenario` in `tests/git_commit/RUNBOOK.md` names for a bundled-script test, so `./tests/git_commit/run_all.sh` runs it. Rewrite these four scope statements in place so each names that straggler-scan isolation scenario beside `prepare_commit_context.sh` and `commit_with_message.sh`, and the prior statement that limits the directory to those two scripts is superseded: the `Scope:` comment at the top of `tests/git_commit/script_tests/run.sh` (`Scope: the two shell scripts shipped with the skill`), the `script_tests/` surface comment in `tests/git_commit/run_all.sh`, the `script_tests/` row under `## tests/git_commit/: Pattern A, skill-creator-aligned` in `tests/CLAUDE.md`, and the `script_tests/` row of the surface table in `tests/git_commit/README.md`. Then run the live suite.

**Out of scope:** Adding evals. Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `tests/git_commit/evals/run.py --help` shows `--workers` defaulting to 4.
- `tests/git_commit/evals/run.py` sets the `--workers` default to `vendor.DEFAULT_PARALLEL_WORKERS`, through `eval_runner.add_workers_argument` or an equivalent `default=` naming that constant.
- `tests/git_commit/evals/run.py` imports `eval_runner` and dispatches jobs through `eval_runner.run_jobs`.
- The straggler `find` in `grade.sh` runs against `$TMPDIR` and keeps `-maxdepth 1 -name 'git_commit_context.*' -newer "$marker"` with `marker="$target/.eval_started_at"`, and eval id `6` still returns before that `find`.
- `tests/git_commit/evals/run.py` copies `TMPDIR`, `TEMP`, and `TMP` from the helper's job mapping onto the micro-deploy environment passed to `micro_deploy.run_worker`, and passes that same mapping as the environment of the `grade.sh` subprocess.
- The hermetic script-test under `tests/git_commit/script_tests` runs the git_commit straggler `find` against two overlapping dummy `TMPDIR` trees and passes only when a `git_commit_context.*` file newer than that tree's `.eval_started_at` marker in one tree is invisible to the other tree's scan; the test fails when that newer file is visible across trees.
- That same hermetic script-test under `tests/git_commit/script_tests` fails the straggler scan of a dummy `TMPDIR` when that scanned tree itself contains a `git_commit_context.*` file newer than its `.eval_started_at` marker, and passes that case only when the scan reports the file.
- That same hermetic script-test is the body function of a `scenario` line in `tests/git_commit/script_tests/run.sh`. `./tests/git_commit/run_all.sh` runs that scenario.
- In each of these four passages, the statement that limits `script_tests/` to `prepare_commit_context.sh` and `commit_with_message.sh` is superseded, and the remaining statement names the straggler-scan isolation scenario beside those two scripts: the `Scope:` comment at the top of `tests/git_commit/script_tests/run.sh`, the `script_tests/` surface comment in `tests/git_commit/run_all.sh`, the `script_tests/` row under `## tests/git_commit/: Pattern A, skill-creator-aligned` in `tests/CLAUDE.md`, and the `script_tests/` row of the surface table in `tests/git_commit/README.md`.
- Default ids come from `evals.json`, so adding an eval runs it without editing
  a frozen list.
- A graded run from `python3 tests/git_commit/evals/run.py` writes its `run-<ts>` directory under the run root named in `## Approach`, `tests/git_commit/workspace`, and `evals/run.py` names that path as the sole run root in place of `WORKSPACE = THIS / "workspace"`.
- `python3 tests/git_commit/evals/run.py` (the default vendor, `--workers 4` by
  default) and the same command with `--workers 1` both print a graded summary
  over every id.
- `tests/git_commit/evals/run.py` imports `eval_runner` and calls `vendor.add_vendor_arguments`, `vendor.resolve`, `micro_deploy.preflight_auth`, and `micro_deploy.micro_deploy` with `micro_deploy.run_worker`.
- Each uncached `timing.json` from one `--workers 4` `--force` run of at least two uncached evals records `started_at` and `ended_at` beside `duration_s`. `tests/git_commit/results/parallel-tmpdir-windows.md` records those windows. When two windows overlap, that file records that overlap. When no two windows overlap, that file records the windows, the change stays incomplete, and the follow-up is one rerun of that same command once the pool overlaps.
- `evals/README.md` and `RUNBOOK.md` each name `tests/git_commit/workspace` as the only `run.py` run root. The prior root `tests/git_commit/evals/workspace` is superseded in both. In `evals/README.md` under `## One-shot run (the default)`, the sentence that writes per-eval output names `tests/git_commit/workspace/run-<ts>/<id>/{response.txt, stderr.txt, timing.json, grading.txt}` as that path, and the bare `workspace/run-<ts>` output path in that sentence is superseded.
- `evals/README.md` and `RUNBOOK.md` each describe the straggler `find` as running against `$TMPDIR`.
- In `tests/CLAUDE.md` under `### Parallel workers: default 4 only where each job has its own sandbox`, and in `tests/AGENTS.md` under `### Parallel workers`, the sentence `` `task_auto_check` is the runner on `eval_runner` `` is rewritten in place to `` `task_auto_check` and `tests/git_commit/evals/run.py` are the runners on `eval_runner` at `vendor.DEFAULT_PARALLEL_WORKERS`. `` The sequential-runner list that opens with "Pattern A runners that stay sequential" and "(plus permanent isolation exceptions)" remains, and its prior `git_commit` shared-`TMPDIR` entry is superseded.
- The comment in `tests/git_commit/evals/run.py` that sits beside the pool states the per-job `TMPDIR` reason. The passage that begins `# Sequential on purpose: grade.sh's TMPDIR straggler check would` is superseded.
