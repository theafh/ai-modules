# task_fix parallel workers: live measurement

Measured 2026-11-05 on the default Cursor vendor (`agent -p`, model `auto`)
with no `--vendor` flag.

## Command and run

```bash
python3 tests/task_fix/evals/run.py --workers 4 --force
```

Run directory: `tests/task_fix/workspace/run-20261105-073044-34294/`. Every id
in `evals.json` was uncached (the run printed `0 from cache`), the runner
graded `4/4 evals passed`, and it exited 0.

## Per-eval windows

Every uncached `timing.json` carries `started_at` and `ended_at` beside
`duration_s`; the times below are those fields in local time (`+01:00`).

| Eval | `started_at` | `ended_at` | `duration_s` | Outcome |
| --- | --- | --- | --- | --- |
| `regroup_live_skip_archived` | 2026-11-05T07:30:52+01:00 | 2026-11-05T07:32:37+01:00 | 104.9 | PASS (`worker_rc` 0) |
| `regroup_state_and_edit_site` | 2026-11-05T07:30:52+01:00 | 2026-11-05T07:32:13+01:00 | 81.2 | PASS (`worker_rc` 0) |
| `surfaced_acceptance_contract` | 2026-11-05T07:30:52+01:00 | 2026-11-05T07:35:11+01:00 | 258.9 | PASS (`worker_rc` 0) |
| `regroup_same_paragraph` | 2026-11-05T07:30:52+01:00 | 2026-11-05T07:32:56+01:00 | 124.2 | PASS (`worker_rc` 0) |

The four start epochs span 0.0016 s, and all six eval pairs satisfy
`started_at < other.ended_at` in both directions. The pool therefore ran the
four evals concurrently rather than serializing them; the run's wall clock was
258.9 s, equal to the longest single eval.

## Host `tasks/` evidence

`git status --porcelain -- tasks` produced no lines immediately before and
immediately after the run, and the two outputs were identical. Every eval's
`grade.sh` also reported both host-tree checks PASS:

```text
PASS  isolation: no writes to the real repo's tasks/ tree
PASS  isolation: the real repo's tasks/ tree is unmoved
```

for each of the four graded evals.

## Default worker-count run

`python3 tests/task_fix/evals/run.py` (no `--force`) then printed the graded
summary over every id:

```text
graded: 4/4 evals passed (4 from cache)
```

## Verdict

Met. Two or more eval windows overlap (all four do), the host `tasks/` tree is
unchanged, and every uncached `timing.json` records `started_at` and `ended_at`
beside `duration_s`. The change is complete.
