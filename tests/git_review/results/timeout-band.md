# git_review timeout band

Measured 2026-11-01 on the default Cursor vendor (`agent -p`, model `auto`),
no `--vendor` flag. The headroom formula is the one in
`tests/task_auto_check/RUNBOOK.md` under `## Timing-band re-measurement`: raise
the harness default to the observed upper bound plus 300 seconds.

## Sample

```bash
python3 tests/git_review/evals/run.py --workers 4 --force 18 41 2
```

Run dir: `tests/git_review/workspace/run-20261101-004055`.

| Eval | Fixture | `duration_s` |
| --- | --- | --- |
| 18 | `deep_file_defect` | 125.554 |
| 41 | `push_approval` | 166.474 |
| 2 | `clean_change` | 95.017 |

A serial `--workers 1 --force 41` latency sample in
`run-20261101-004525` measured 188.070s. A later `--force` pair of ids 18 and 2
at the default worker count (`run-20261101-010447`) measured eval 18 at
312.555s and eval 2 at 79.234s.

## Outcome: leave `--timeout` at 600

The three-id parallel sample's upper bound is 166.474s, the serial eval 41
retry took 188.070s, and the highest 2026-11-01 reading is 312.555s (eval 18
in the later pair). All stay clear of the 600s default, so `run.py` keeps
`--timeout` at 600 and this harness's RUNBOOK keeps its 600s default.
`--workers 1` remains the latency reading.
