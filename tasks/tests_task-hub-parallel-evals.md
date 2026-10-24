---
description: Parallelize isolated task-hub evals at default 4 workers via Pattern A with per-eval host-tasks fail-safes under overlap, and keep the Approach serial nested-loop set sequential in-run.
scope: tests/task/evals
created: 2026-10-04T22:11:10
updated: 2026-10-24T00:44:27
status: ready
reported-by: Andreas Hoffmann
---

# Parallelize isolated task-hub evals without mixing host-tree fail-safes and keep the Approach serial nested-loop set sequential

## Goal

`python3 tests/task/evals/run.py` runs every isolated eval
concurrently at default 4 workers, then runs the Approach serial nested-loop set
one at a time in the same invocation. Each eval still fails if one of its own
fixture names appears, moves, or is newer than that eval's marker in the host
`tasks/` tree, and concurrent sandboxed workers do not trip that check for each
other. Cursor is the measurement vendor. The user-visible outcome: every isolated
eval (every eval outside the Approach serial nested-loop set) overlaps, while
that serial nested-loop set still runs one id at a time after the isolated pool.

## Context

`tests/task/evals/run.py` is sequential `# Sequential on purpose: keeps each worker's sandbox isolation checks unambiguous and the host filesystem quiet.` `evals/grade.sh` checks
the host tree through `host_fixture_writes_clean` in
`tests/lib/host_tasks_guard.sh`, which compares the live `tasks/` tree with the
isolated copy `stage.sh` takes, only for the sandbox's own fixture names and
against the marker `stage.sh` stamps at `$target/.eval_started_at`. `WORKSPACE` is
`tests/task/evals/workspace`. Ids already come from `evals.json` via
`_all_eval_ids()`. `evals/test_run.py` calls the runner's `stage()` for the
declaration/stage-guard surface that `tests/task/run_all.sh` drives.

Sandboxed workers that never write the host tree can overlap. The fail-safe
stays per-eval, marker-scoped, and fixture-scoped: an operator edit of a task
the sandbox does not name stays outside the comparison, as `tests/CLAUDE.md`
documents under the heading "Host `tasks/` during a task-family run".

This task consumes [the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md).
Sibling harnesses with the same fail-safe are
[task_create](tests_task-create-parallel-evals.md) and
[task_fix](tests_task-fix-parallel-evals.md).

## Approach

Rewrite `evals/run.py` onto the shared helper. Split the run set by one serial nested-loop set — `auto_check_boundary`, `fix_coherence_reconcile_escalated`, `fix_coherence_reconcile_inline_staleness`: isolated evals go through the pool at default `--workers` 4 with workspace `tests/task/workspace` and per-job `TMPDIR`; that serial set runs with effective workers 1 after that pool, never overlapping another serial-set job. When each uncached job writes `timing.json` (via `eval_runner.write_run_artifacts` or equivalent), that file keeps every field the current writer already records there—including `skill_name`, `artefacts_read_from_micro_deployment`, `checkout_unread`, and `duration_s`—and adds wall-clock `started_at` and `ended_at` beside `duration_s`. Keep `grade.sh`'s fixture-scoped host
check as the escape guard. The helper's before/after hooks only serialize
snapshots, so any hook this harness adds uses the job index the helper passes
to claim only that eval's fixture names. Keep the staging-time stamp `stage.sh` writes at `$target/.eval_started_at`; do not restamp before the worker starts. Rewrite the sequential comment and the harness RUNBOOK. In `tests/task/evals/README.md`, rewrite the callout that begins `` **The `fix_coherence*` evals are the other slow group.** `` in place so it names that Approach serial nested-loop set and states that those ids run sequentially after the isolated pool while the rest of the suite uses the default 4 workers. In `tests/CLAUDE.md` under `### Parallel workers: default 4 only where each job has its own sandbox`, and in `tests/AGENTS.md` under `### Parallel workers`, rewrite both sections in place to their target form while keeping each section's already-shipped `task_auto_check` serial nested-loop exception prose: drop `task` from the Pattern A runners that stay sequential (leave `task_create` and `task_fix` in that list), add `tests/task/evals/run.py` among the Pattern A runners on `eval_runner` at `vendor.DEFAULT_PARALLEL_WORKERS` beside the existing `tests/task_auto_check/evals/run.py` entry, and name that Approach serial nested-loop set as `tests/task/evals/run.py`'s sequential exception after the isolated pool beside the existing `task_auto_check` serial nested-loop exception.

Prove with a hermetic case that two overlapping jobs whose sandboxes stay
inside their targets leave host `tasks/` untouched, and that a deliberate newer
file carrying one eval's fixture name under host `tasks/` fails that eval while
an overlapping eval with other fixture names stays green.

Rewrite `evals/test_run.py` so its `runner.stage(...)` call passes a job `env`
(matching Pattern A siblings such as `tests/task_auto_check/evals/run.py`),
because the Pattern A `stage` signature requires that mapping; do not leave the
current two-arg `stage(eval_id, target)` call standing after `run.py` moves onto
the shared helper.

**Out of scope:** The `script_tests/` and `contract_run.sh` surfaces. Deep
`task_auto_check` repair loops, which
[the auto_check parallel task](archive/tests_task-auto-check-parallel-evals.md) owns.
Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4.
- In `tests/CLAUDE.md` under `### Parallel workers: default 4 only where each job has its own sandbox`, and in `tests/AGENTS.md` under `### Parallel workers`, the Pattern A runners on `eval_runner` at `vendor.DEFAULT_PARALLEL_WORKERS` name `tests/task/evals/run.py` beside the already-shipped `tests/task_auto_check/evals/run.py` entry, and the prior sequential entry that lists `task`, `task_create`, and `task_fix` together is superseded so that list names only `task_create` and `task_fix` among those three; both sections still name the already-shipped `task_auto_check` serial nested-loop exception and name the Approach serial nested-loop set as `tests/task/evals/run.py`'s sequential exception after the isolated pool beside it.
- `python3 tests/task/evals/run.py` at the default worker count prints a
  graded summary over every id from `evals.json`.
- A graded run from `python3 tests/task/evals/run.py` writes its `run-<ts>` directory under the run root named in `## Approach`, `tests/task/workspace`, and `evals/run.py` obtains that path through `eval_runner.resolve_workspace` as the sole run root in place of `WORKSPACE = THIS / "workspace"`.
- `RUNBOOK.md` and any harness README that still names the prior root each name `tests/task/workspace` as the only `run.py` run root; the prior root `tests/task/evals/workspace` and the sequential-only framing are superseded in each, and one canonical statement remains. The passage in `evals/run.py` that begins `# Sequential on purpose:` is superseded by the concurrent-pool-plus-serial-tail framing Approach requires. The callout in `tests/task/evals/README.md` that begins `**The \`fix_coherence*\` evals are the other slow group.**` names only the Approach serial nested-loop set as the sequential deep ones and states that the rest of the hub suite uses the default 4 workers.
- Each uncached isolated job's `timing.json` from a `--workers 4 --force` run of at least two uncached isolated evals keeps every field the current writer already records there—including `skill_name`, `artefacts_read_from_micro_deployment`, `checkout_unread`, and `duration_s`—and carries `started_at` and `ended_at` beside `duration_s`; those isolated windows overlap; that run leaves `git status --porcelain` of host `tasks/` unchanged; the `tests/task/results/` record shows those windows; when the isolated windows do not overlap, that record states the miss and parallelization is not shipped.
- In that same measurement's workspace `timing.json` records, the Approach serial nested-loop evals have pairwise non-overlapping windows; the recorded measurement evidence under `tests/task/results/` shows those windows; when any pair overlaps, that record states the miss and parallelization is not shipped.
- In that same measurement's workspace `timing.json` records, every Approach serial nested-loop eval has `started_at` at or after every isolated eval's `ended_at` (the isolated pool finishes before any serial nested-loop window begins); the recorded measurement evidence under `tests/task/results/` shows that order; when any serial window starts before an isolated window ends, that record states the miss and parallelization is not shipped.
- `grade.sh` still fails an eval when one of that eval's fixture names is newer
  than its marker in the host `tasks/` tree.
- After `stage.sh` stamps `$target/.eval_started_at` for an uncached job, that marker's mtime and content are unchanged when the worker starts; `evals/run.py` performs no rewrite of the marker between staging and worker start.
- Under that same planted newer host `tasks/` file, an overlapping eval whose fixture names omit that file stays PASS; both outcomes of the planted-file case are recorded under `tests/task/results/`.
- A `--workers 4 --force` run of at least two uncached evals shows distinct per-job `TMPDIR` values, or `evals/run.py` invokes `eval_runner.run_jobs` (which always installs them).
- `evals/test_run.py` calls `stage` with a job `env` (three-argument form), so the declaration/stage-guard surface `tests/task/run_all.sh` drives still runs after `run.py` takes the Pattern A `stage` signature; the prior two-arg `stage(eval_id, target)` call is superseded.
