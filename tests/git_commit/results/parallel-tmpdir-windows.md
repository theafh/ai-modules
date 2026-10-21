# Parallel TMPDIR windows

Recorded evidence that `tests/git_commit/evals/run.py` runs its evals
concurrently through `tests/lib/eval_runner`, each with its own `TMPDIR`.

- **Vendor:** Cursor default (`agent -p`, model `auto`), no `--vendor`.
- **Command:** `python3 tests/git_commit/evals/run.py --workers 4 --force`
- **Run dir:** `tests/git_commit/workspace/run-20261021-164358`
- **Result:** `graded: 8/9 evals passed (0 from cache)`. All nine evals ran
  uncached, and every worker exited with `worker_rc` 0.

## Windows

Unix epoch seconds from each eval's `timing.json`, which records
`started_at` and `ended_at` beside `duration_s`. The job `TMPDIR` column
names the per-job directory under the system temporary directory that
`eval_runner` handed out, read from the context-file path the worker wrote
and the directory `grade.sh` scanned.

| Eval | started_at | ended_at | duration_s | worker_rc | Job `TMPDIR` | Grade |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| 1 | 1792593848.542866 | 1792593896.920551 | 48.4 | 0 | `eval_runner_3hhb3t0a` | PASS |
| 2 | 1792593848.794326 | 1792593908.710911 | 59.9 | 0 | `eval_runner_soo2ea4w` | PASS |
| 3 | 1792593848.952377 | 1792593890.140117 | 41.2 | 0 | `eval_runner_q59f2dtd` | PASS |
| 4 | 1792593848.985833 | 1792593902.353920 | 53.4 | 0 | `eval_runner__hozq07w` | PASS |
| 5 | 1792593891.008092 | 1792593976.429334 | 85.4 | 0 | `eval_runner__q1kbz2j` | FAIL |
| 6 | 1792593897.902707 | 1792593936.901264 | 39.0 | 0 | `eval_runner_z46au9tx` | PASS |
| 7 | 1792593903.257353 | 1792593950.778296 | 47.5 | 0 | `eval_runner_1elqeb8p` | PASS |
| 8 | 1792593909.557016 | 1792593949.540473 | 40.0 | 0 | `eval_runner_wyibr2x1` | PASS |
| 9 | 1792593937.804992 | 1792593974.633907 | 36.8 | 0 | `eval_runner_mfyd3kpl` | PASS |

## Overlap

The windows overlap. Of the 36 eval pairs, 21 overlap: 1–2, 1–3, 1–4, 1–5,
2–3, 2–4, 2–5, 2–6, 2–7, 3–4, 4–5, 4–6, 5–6, 5–7, 5–8, 5–9, 6–7, 6–8, 7–8,
7–9, and 8–9. Evals 1 to 4 ran all at once from 1792593848.985833, the last
of their starts, to 1792593890.140117, the first of their ends, which is the
pool at its default of four workers. Each eval used a different job
`TMPDIR`, so no two overlapping evals shared the directory the straggler scan
reads.

## The eval 5 failure

Eval 5 failed only `grade.sh`'s context-file cleanup check. Its scan found two
`git_commit_context.*` files in `eval_runner__q1kbz2j`, eval 5's own job
`TMPDIR`, which no other job wrote into. Eval 5 stubs the prepare script to
fail, so the worker builds its context through the manual fallback; its
response reports retrying that step with an explicit `PATH`, and the files
from the earlier attempts stayed behind after the commit landed. This is the
worker's own cleanup miss in the fallback eval, and the same check failed on
eval 5 on 2026-09-05 and 2026-10-15 under the sequential runner with a shared
`TMPDIR`. It is no cross-talk from a concurrent eval.

## Companion runs

- `python3 tests/git_commit/evals/run.py` (default 4 workers, uncached) in
  `tests/git_commit/workspace/run-20261021-164042`: `graded: 9/9 evals passed
  (0 from cache)`. Evals 1 to 4 started together, and each worker's context
  file and each grader's scan used that eval's own job `TMPDIR`.
- `python3 tests/git_commit/evals/run.py --workers 1` in
  `tests/git_commit/workspace/run-20261021-164333`: `graded: 9/9 evals passed
  (9 from cache)`, replaying the verdicts the default run had just recorded.
