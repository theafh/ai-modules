# guardrail_audit parallel-workers windows

Measured on 2026-11-05 against `tests/guardrail_audit/evals/run.py` after the
runner moved onto `tests/lib/eval_runner` at `--workers` (default 4). The
window below comes from one `--workers 4 --force` run of all six uncached
evals, so every `timing.json` carries `started_at` and `ended_at` beside
`duration_s`.

## Command

```bash
python3 tests/guardrail_audit/evals/run.py --workers 4 --force
```

- Vendor: Cursor (`agent -p`, model `auto`)
- Run dir: `tests/guardrail_audit/workspace/run-20261105-232114-45172`
- Graded summary: 5/6 passed, 0 from cache

## Windows

| Eval | `started_at` | `ended_at` | `duration_s` |
| --- | --- | --- | --- |
| `presence_gate` | 2026-11-05T23:21:22.254 | 2026-11-05T23:22:48.296 | 86.0 |
| `doc_vs_doc` | 2026-11-05T23:21:22.254 | 2026-11-05T23:22:23.702 | 61.4 |
| `doc_vs_code` | 2026-11-05T23:21:22.254 | 2026-11-05T23:22:40.306 | 78.1 |
| `direction_target` | 2026-11-05T23:21:22.254 | 2026-11-05T23:22:54.813 | 92.6 |
| `missing_testing` | 2026-11-05T23:22:24.204 | 2026-11-05T23:23:42.180 | 78.0 |
| `nature_mismatch` | 2026-11-05T23:22:40.888 | 2026-11-05T23:23:51.979 | 71.1 |

The first four jobs start within a millisecond of one another, and
`missing_testing` / `nature_mismatch` start as those slots free. The run's
wall clock spans 23:21:22 to 23:23:51 (about 150s) while the six durations sum
to about 467s, so the pool overlapped the staged fixtures.

## Overlaps

Every pair of windows overlaps except the pairs below, which are disjoint only
because a later job started after an earlier short job finished:

- `doc_vs_doc` and `missing_testing`
- `doc_vs_doc` and `nature_mismatch`
- `doc_vs_code` and `nature_mismatch`

Measured overlap for representative pairs:

| Pair | Overlap |
| --- | --- |
| `presence_gate` & `direction_target` | 86.0s |
| `presence_gate` & `doc_vs_code` | 78.1s |
| `direction_target` & `doc_vs_code` | 78.1s |
| `direction_target` & `doc_vs_doc` | 61.4s |
| `missing_testing` & `nature_mismatch` | 61.3s |
| `direction_target` & `missing_testing` | 30.6s |
| `missing_testing` & `presence_gate` | 24.1s |
| `doc_vs_code` & `missing_testing` | 16.1s |
| `direction_target` & `nature_mismatch` | 13.9s |
| `nature_mismatch` & `presence_gate` | 7.4s |

## Note on the failing eval

`direction_target` failed one response marker, "response offers no softening or
deletion of the target". The worker's closing question offered "bring the doc
back to the code" for an unrelated header-casing finding, and the grader's
`lacks_unnegated` check matches that phrase without scoping it to the
`## Direction` target. The worker's direction paragraph explicitly says
"Softening or deleting the target to match today's code is not offered." This
is a pre-existing grader false positive triggered by model phrasing, outside
this task's parallelization change; the summary over all six ids still printed
as the acceptance requires.
