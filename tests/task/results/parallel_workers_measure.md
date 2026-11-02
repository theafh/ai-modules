# Parallel workers measurement: task hub

## Run

- Command: `python3 tests/task/evals/run.py --workers 4 --force`
- Vendor: `cursor` (the default; no `--vendor` flag)
- Model: `auto`
- Run directory: `tests/task/workspace/run-20261102-174912`
- Log: `tests/task/results/parallel_workers_measure.log`
- First job `started_at`: 2026-11-02T17:49:37.900+01:00
- Last job `ended_at`: 2026-11-02T18:25:12.583+01:00
- Evals: 46 (every id in `evals.json`, in file order)
- Outcomes: 42/46 evals passed, 0 cached

## Per-eval windows and outcomes

| eval id | started_at | ended_at | duration_s | outcome |
| --- | --- | --- | --- | --- |
| `create` | 2026-11-02T17:49:37.900+01:00 | 2026-11-02T17:50:53.589+01:00 | 75.7 | PASS |
| `check` | 2026-11-02T17:49:37.900+01:00 | 2026-11-02T17:50:48.741+01:00 | 70.8 | PASS |
| `standing_rules_create` | 2026-11-02T17:49:37.900+01:00 | 2026-11-02T17:51:04.865+01:00 | 87.0 | PASS |
| `standing_rules_check` | 2026-11-02T17:49:37.900+01:00 | 2026-11-02T17:53:34.465+01:00 | 236.6 | FAIL |
| `standing_rules_check_control` | 2026-11-02T17:50:53.924+01:00 | 2026-11-02T17:52:57.627+01:00 | 123.7 | PASS |
| `explain` | 2026-11-02T17:50:59.314+01:00 | 2026-11-02T17:51:22.502+01:00 | 23.2 | PASS |
| `select` | 2026-11-02T17:51:09.800+01:00 | 2026-11-02T17:51:44.096+01:00 | 34.3 | PASS |
| `implement` | 2026-11-02T17:51:27.289+01:00 | 2026-11-02T17:52:21.104+01:00 | 53.8 | PASS |
| `implement_dep_gate` | 2026-11-02T17:51:48.944+01:00 | 2026-11-02T17:52:11.667+01:00 | 22.7 | PASS |
| `select_inbound_dep` | 2026-11-02T17:52:17.316+01:00 | 2026-11-02T17:52:50.922+01:00 | 33.6 | PASS |
| `select_dep_regression` | 2026-11-02T17:52:26.182+01:00 | 2026-11-02T17:53:06.893+01:00 | 40.7 | PASS |
| `audit_gaps` | 2026-11-02T17:52:55.913+01:00 | 2026-11-02T17:53:48.494+01:00 | 52.6 | PASS |
| `audit_clean` | 2026-11-02T17:53:02.397+01:00 | 2026-11-02T17:53:45.430+01:00 | 43.0 | PASS |
| `audit_reopen` | 2026-11-02T17:53:11.770+01:00 | 2026-11-02T17:53:55.669+01:00 | 43.9 | PASS |
| `finish` | 2026-11-02T17:53:39.251+01:00 | 2026-11-02T17:54:35.233+01:00 | 56.0 | PASS |
| `fix` | 2026-11-02T17:53:50.912+01:00 | 2026-11-02T17:55:46.987+01:00 | 116.1 | PASS |
| `fix_quote_description` | 2026-11-02T17:53:55.063+01:00 | 2026-11-02T17:55:09.721+01:00 | 74.7 | PASS |
| `query` | 2026-11-02T17:54:00.751+01:00 | 2026-11-02T17:54:25.983+01:00 | 25.2 | PASS |
| `update` | 2026-11-02T17:54:31.227+01:00 | 2026-11-02T17:54:58.822+01:00 | 27.6 | PASS |
| `update_contract` | 2026-11-02T17:54:40.458+01:00 | 2026-11-02T17:55:33.083+01:00 | 52.6 | PASS |
| `triage` | 2026-11-02T17:55:04.507+01:00 | 2026-11-02T17:55:35.441+01:00 | 30.9 | PASS |
| `lossless_split` | 2026-11-02T17:55:14.762+01:00 | 2026-11-02T17:56:56.050+01:00 | 101.3 | PASS |
| `lossless_single` | 2026-11-02T17:55:38.475+01:00 | 2026-11-02T17:57:02.352+01:00 | 83.9 | PASS |
| `check_boundary_contradiction` | 2026-11-02T17:55:42.664+01:00 | 2026-11-02T17:56:51.820+01:00 | 69.2 | PASS |
| `check_boundary_clean` | 2026-11-02T17:55:52.210+01:00 | 2026-11-02T17:57:07.575+01:00 | 75.4 | PASS |
| `implement_boundary_cross` | 2026-11-02T17:56:57.067+01:00 | 2026-11-02T17:57:51.434+01:00 | 54.4 | PASS |
| `implement_boundary_agree` | 2026-11-02T17:57:01.170+01:00 | 2026-11-02T17:57:55.424+01:00 | 54.3 | PASS |
| `create_scope_trim` | 2026-11-02T17:57:06.848+01:00 | 2026-11-02T17:58:23.588+01:00 | 76.7 | PASS |
| `create_regroup_owner_account` | 2026-11-02T17:57:12.197+01:00 | 2026-11-02T17:58:27.130+01:00 | 74.9 | PASS |
| `auto_check_boundary` | 2026-11-02T18:05:56.759+01:00 | 2026-11-02T18:11:57.806+01:00 | 361.0 | PASS |
| `check_exclusion_requirement` | 2026-11-02T17:57:56.311+01:00 | 2026-11-02T18:00:16.728+01:00 | 140.4 | PASS |
| `check_exclusion_requirement_control` | 2026-11-02T17:58:00.440+01:00 | 2026-11-02T17:59:46.993+01:00 | 106.6 | PASS |
| `check_exclusion_waiver` | 2026-11-02T17:58:28.462+01:00 | 2026-11-02T17:59:53.677+01:00 | 85.2 | PASS |
| `check_exclusion_waiver_control` | 2026-11-02T17:58:32.783+01:00 | 2026-11-02T18:02:15.732+01:00 | 222.9 | FAIL |
| `check_commit_proof_surface` | 2026-11-02T17:59:53.080+01:00 | 2026-11-02T18:00:56.400+01:00 | 63.3 | PASS |
| `check_commit_proof_surface_control` | 2026-11-02T17:59:58.467+01:00 | 2026-11-02T18:01:31.896+01:00 | 93.4 | PASS |
| `check_count_stable` | 2026-11-02T18:00:21.261+01:00 | 2026-11-02T18:03:05.592+01:00 | 164.3 | PASS |
| `finish_arch_extended` | 2026-11-02T18:01:00.922+01:00 | 2026-11-02T18:01:52.504+01:00 | 51.6 | PASS |
| `finish_arch_declined` | 2026-11-02T18:01:36.475+01:00 | 2026-11-02T18:02:12.219+01:00 | 35.7 | PASS |
| `finish_arch_absent` | 2026-11-02T18:01:57.080+01:00 | 2026-11-02T18:02:45.632+01:00 | 48.6 | PASS |
| `fix_coherence` | 2026-11-02T18:02:17.197+01:00 | 2026-11-02T18:05:49.762+01:00 | 212.6 | FAIL |
| `fix_coherence_reconcile_escalated` | 2026-11-02T18:12:02.577+01:00 | 2026-11-02T18:21:22.813+01:00 | 560.2 | FAIL |
| `fix_coherence_reconcile_inline_staleness` | 2026-11-02T18:21:35.082+01:00 | 2026-11-02T18:25:12.583+01:00 | 217.5 | PASS |
| `fix_coherence_selector_scope` | 2026-11-02T18:02:21.207+01:00 | 2026-11-02T18:04:56.086+01:00 | 154.9 | PASS |
| `fix_coherence_selector_explicit_list` | 2026-11-02T18:02:50.299+01:00 | 2026-11-02T18:05:25.091+01:00 | 154.8 | PASS |
| `fix_coherence_selector_whole_tree` | 2026-11-02T18:03:10.145+01:00 | 2026-11-02T18:05:16.843+01:00 | 126.7 | PASS |

## Measurement conditions

### Isolated windows overlap

43 isolated evals produced 116 overlapping pairs. Concrete examples:

- `create` and `check` overlapped from 2026-11-02T17:49:37.900+01:00 to 2026-11-02T17:50:48.741+01:00 (70.8s).
- `create` and `standing_rules_create` overlapped from 2026-11-02T17:49:37.900+01:00 to 2026-11-02T17:50:53.589+01:00 (75.7s).
- `create` and `standing_rules_check` overlapped from 2026-11-02T17:49:37.900+01:00 to 2026-11-02T17:50:53.589+01:00 (75.7s).
- `check` and `standing_rules_create` overlapped from 2026-11-02T17:49:37.900+01:00 to 2026-11-02T17:50:48.741+01:00 (70.8s).
- `check` and `standing_rules_check` overlapped from 2026-11-02T17:49:37.900+01:00 to 2026-11-02T17:50:48.741+01:00 (70.8s).

Verdict: MET. Isolated windows overlap.

### Serial nested-loop tail

- `auto_check_boundary`: 2026-11-02T18:05:56.759+01:00 to 2026-11-02T18:11:57.806+01:00.
- `fix_coherence_reconcile_escalated`: 2026-11-02T18:12:02.577+01:00 to 2026-11-02T18:21:22.813+01:00.
- `fix_coherence_reconcile_inline_staleness`: 2026-11-02T18:21:35.082+01:00 to 2026-11-02T18:25:12.583+01:00.

Pairwise non-overlap: MET.

Every serial window starts at or after every isolated `ended_at`: MET. The latest isolated `ended_at` is 2026-11-02T18:05:49.762+01:00, and the earliest serial `started_at` is 2026-11-02T18:05:56.759+01:00.

### Summary and denominator

The closing line is `graded: 42/46 evals passed (0 from cache)`. It printed 46 rows in `evals.json` order, matching all 46 ids, and the run directory holds 46 `timing.json` records, so the denominator equals the record count. Verdict: MET.

### Timing fields

All 46 records carry `eval_id`, `skill_name`, `duration_s`, `worker_rc`, `claude_rc`, `model`, `artefacts_read_from_micro_deployment`, `checkout_unread`, `started_at`, `ended_at`; missing fields: none. Verdict: MET.

### Per-job TMPDIR

`tests/task/evals/run.py:395` calls `eval_runner.run_jobs(jobs, workers=workers, on_error=on_error)`. `tests/lib/eval_runner.py:198` gives each job a fresh `tempfile.mkdtemp(prefix="eval_runner_")`, and `_job_env` at `tests/lib/eval_runner.py:177-185` sets `TMPDIR`, `TEMP`, and `TMP` to that directory; `run.py:231` copies them into the worker deployment environment. Verdict: MET.

### Staging marker

`tests/task/evals/stage.sh:341` writes `$target/.eval_started_at` once at stage time. `tests/task/evals/run.py` contains no `.eval_started_at` reference, so the marker is not rewritten between staging and worker start; `python3 tests/task/evals/test_run.py` asserts that property. Verdict: MET.

### Hermetic planted-file case

`tests/task/results/run-parallel_workers_hermetic.md` records both outcomes from the deterministic proof: the `check` eval's isolation check fails on the planted newer host file carrying its own fixture name (`api_make-it-better.md`), while the overlapping `query` eval, whose fixture names omit that file, stays PASS. Verdict: MET.

### Host tasks tree

`git status --porcelain -- tasks` was empty before and after the run. Verdict: MET.

## Behavioral failures in this run

The four FAIL outcomes are skill/grader disagreements, not measurement-condition misses. No isolation check failed in the measurement run.

- `standing_rules_check`: `status stamped ready because a faithful copy is a note`.
- `check_exclusion_waiver_control`: `status stamped ready for the carve-out control`.
- `fix_coherence`: `(a) the double-owned severity_label edit is an alter finding`.
- `fix_coherence_reconcile_escalated`: `(a) one owner is named and the counterpart verifies or follows in order`.

## Verdict

All required measurement conditions are MET: isolated windows overlap, the serial nested-loop tail is pairwise non-overlapping and starts after every isolated eval, the summary has one row per id in `evals.json` order with a denominator equal to the `timing.json` count, every timing field is present, the staging marker is untouched, the hermetic planted-file case shows the expected fail/pass split, and the host `tasks/` tree is unchanged.
