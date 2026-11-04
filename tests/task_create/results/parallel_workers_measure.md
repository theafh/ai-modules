# Parallel workers measurement: task_create

## Run

- Command: `python3 tests/task_create/evals/run.py --workers 4 --force`
- Vendor: `cursor` (the default; no `--vendor` flag)
- Model: `auto`
- Run directory: `tests/task_create/workspace/run-20261104-123523`
- Log: `tests/task_create/results/parallel_workers_measure.log`
- First job `started_at`: 2026-11-04T12:35:34.108+01:00
- Last job `ended_at`: 2026-11-04T12:38:02.018+01:00
- Evals: 4 (every id in `evals.json`, in file order)
- Outcomes: 2/4 evals passed, 0 cached

## Per-eval windows and outcomes

| eval id | started_at | ended_at | duration_s | outcome |
| --- | --- | --- | --- | --- |
| `reconcile-recorded` | 2026-11-04T12:35:34.413+01:00 | 2026-11-04T12:37:33.306+01:00 | 118.9 | PASS |
| `labeled-why-open` | 2026-11-04T12:35:34.108+01:00 | 2026-11-04T12:37:20.576+01:00 | 106.5 | PASS |
| `guardrail-bound-surface` | 2026-11-04T12:35:34.108+01:00 | 2026-11-04T12:38:02.018+01:00 | 147.9 | FAIL |
| `related-precedent-novel` | 2026-11-04T12:35:34.342+01:00 | 2026-11-04T12:37:06.769+01:00 | 92.4 | FAIL |

## Measurement conditions

### Windows overlap

All four evals started within 0.3s of one another and produced 6 overlapping
pairs out of 6 possible. Examples:

- `reconcile-recorded` and `labeled-why-open` overlapped from
  2026-11-04T12:35:34.413+01:00 to 2026-11-04T12:37:20.576+01:00 (106.2s).
- `labeled-why-open` and `guardrail-bound-surface` overlapped from
  2026-11-04T12:35:34.108+01:00 to 2026-11-04T12:37:20.576+01:00 (106.5s).
- `guardrail-bound-surface` and `related-precedent-novel` overlapped from
  2026-11-04T12:35:34.342+01:00 to 2026-11-04T12:37:06.769+01:00 (92.4s).

Verdict: MET. The windows overlap.

### Host `tasks/` tree

`git status --porcelain -- tasks` was empty (0 lines) before the run and empty
after it, so the run left the host `tasks/` tree unchanged. Every eval's
isolation check printed `PASS  isolation: no writes to the real repo's tasks/
tree`.

Verdict: MET.

### Timing fields

All four `timing.json` records carry `eval_id`, `skill_name`, `duration_s`,
`worker_rc`, `claude_rc`, `model`, `artefacts_read_from_micro_deployment`,
`checkout_unread`, `started_at`, and `ended_at`; missing fields: none.

Verdict: MET.

### Summary and denominator

The closing line is `graded: 2/4 evals passed (0 from cache)`. It printed four
rows in `evals.json` order (`reconcile-recorded`, `labeled-why-open`,
`guardrail-bound-surface`, `related-precedent-novel`), and the run directory
holds four `timing.json` records.

Verdict: MET.

### Default invocation

A subsequent `python3 tests/task_create/evals/run.py` with no flags replayed
the four cached verdicts at the default worker count and printed
`graded: 2/4 evals passed (4 from cache)` with one row per id in `evals.json`
order, in `tests/task_create/workspace/run-20261104-123835`.

Verdict: MET.

### Per-job TMPDIR

`tests/task_create/evals/run.py:319` calls
`eval_runner.run_jobs(jobs, workers=workers, on_error=on_error)`.
`tests/lib/eval_runner.py:198` gives each job a fresh
`tempfile.mkdtemp(prefix="eval_runner_")`, and `_job_env` at
`tests/lib/eval_runner.py:177-185` sets `TMPDIR`, `TEMP`, and `TMP` to that
directory; `_apply_job_temp` at `tests/task_create/evals/run.py:157` copies them
into the worker deployment environment.

Verdict: MET.

### Hermetic planted-file proof

`python3 tests/task_create/evals/test_run.py` passed 19 of 19 checks. Its
deterministic record, `tests/task_create/results/run-parallel_workers_hermetic.md`,
shows two overlapping jobs leaving the temporary host mirror's `tasks/`
signature unchanged, and the planted newer
`tasks/sandbox-only-reconcile-recorded.md` failing `reconcile-recorded`'s
isolation check while the overlapping `related-precedent-novel` eval, whose
fixture name omits that file, stayed PASS. The real `tasks/` tree was never
written by the test.

Verdict: MET.

## Behavioral failures in this run

The two FAIL outcomes are skill/grader disagreements, not measurement-condition
misses: both workers exited 0 with a response, and every eval's isolation check
passed. `guardrail-bound-surface` failed its `the label names both crossing
paths (rich / non-rich styling)` check; `related-precedent-novel` failed its
`Context links the archived related precedent` check. `reconcile-recorded` and
`labeled-why-open` passed every deterministic check.

## Verdict

All measurement conditions required by the task are MET: the four windows
overlap in every pair, the host `tasks/` tree is unchanged, every timing record
keeps the pre-existing fields and adds `started_at`/`ended_at`, the default
worker count dispatched all four evals through `eval_runner.run_jobs`, and the
hermetic planted-file case shows the expected fail/pass split.
