# Layer 2 shared-pool run record

Recorded 2026-11-26 for `tests_wiki-layer2-runner-dedup`: the runner now drives
its scenario pool through `tests/lib/eval_runner.run_jobs` instead of a private
`ThreadPoolExecutor`.

## Plumbing run

`python3 tests/wiki/layer2/run.py --scenario L2-1 --passes 1 --workers 1`

- Run dir: `tests/wiki/layer2/workspace/run-20261126-225519`
- `L2-1` pass 1: **100.0%**, worker rc 0
- Restaged into an outside-checkout sandbox root, recorded
  `checkout_unread.passed: true`, graded, and wrote `grading_summary.json`,
  `benchmark.json`, `benchmark.md`, and `report.html`.

## Overlap subset

`python3 tests/wiki/layer2/run.py --scenario L2-1,L2-4 --passes 1 --workers 2`

- Run dir: `tests/wiki/layer2/workspace/run-20261126-225710`
- Both scenarios were submitted together at run start.
- `L2-1` pass 1 ran 185.7 s and `L2-4` pass 1 ran 40.3 s, so `L2-4`'s whole
  window sits inside `L2-1`'s: the two scenarios overlapped under the shared
  pool.
- Both recorded `checkout_unread.passed: true`; both graded.

The run output lives under `tests/wiki/layer2/workspace/` (gitignored); this
note is the tracked record.
