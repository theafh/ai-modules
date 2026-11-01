# git_review parallel worker windows

Measured 2026-11-01 on the default Cursor vendor (`agent -p`, model `auto`),
no `--vendor` flag.

Command:

```bash
python3 tests/git_review/evals/run.py --workers 4 --force 18 41 2
```

Run dir: `tests/git_review/workspace/run-20261101-004055`.

## Overlapping wall-clock windows

Each row reads `started_at` and `ended_at` from that eval's `timing.json`.

| Eval | Fixture | `started_at` | `ended_at` | `duration_s` | `tmpdir` |
| --- | --- | --- | --- | --- | --- |
| 18 | `deep_file_defect` | 2026-11-01T00:41:10 | 2026-11-01T00:43:16 | 125.554 | `/var/folders/xz/gtfzzwqs2hxdb3s2zgqtqfzr0000gp/T/eval_runner_jjlw89ht` |
| 41 | `push_approval` | 2026-11-01T00:41:10 | 2026-11-01T00:43:57 | 166.474 | `/var/folders/xz/gtfzzwqs2hxdb3s2zgqtqfzr0000gp/T/eval_runner_c20wd0wa` |
| 2 | `clean_change` | 2026-11-01T00:41:10 | 2026-11-01T00:42:45 | 95.017 | `/var/folders/xz/gtfzzwqs2hxdb3s2zgqtqfzr0000gp/T/eval_runner_669po52a` |

All three jobs start at the same second and finish at three different times,
so the three windows overlap across their whole shortest duration. The three
`tmpdir` values are distinct. For evals 18 and 2, the read paths recorded in
`timing.json` put the collector's `git_review.*` scratch directory under that
job's own `tmpdir`, which shows the job environment reached the worker. Eval
41's fixture points `TMPDIR` at its own target by design, so its job `tmpdir`
does not hold the collector scratch.

## Graded summary

```text
graded: 2/3 evals passed (0 from cache)
  eval-18: PASS
  eval-41: FAIL
  eval-2: PASS
```

Eval 41 failed on the `warning was emitted before the push ran` check while its
worker completed with rc 0. That is a skill/grader disagreement, not an
incomplete run: the worker wrote its `report.md` under a bare `mktemp -d`
directory outside the fixture target (`/tmp` and the macOS user temp dir in the
two samples), while `grade.sh` finds the draft under the fixture target. The
fixture's `TMPDIR` reached the Cursor process, because `target/tmp`, where
`push_approval`'s `gh_env` points it, holds the Cursor agent logs, but the
worker's shell scratch directory landed outside it. A serial
`--workers 1 --force 41` retry (`run-20261101-004525`, `duration_s` 188.070)
reproduced the same failure, so parallelism does not cause it. A
`--no-cache` run of eval 41 with the sequential `run.py` from commit `5504360`
(`run-20261101-092937-at-5504360`, Cursor CLI 2026.10.22, `duration_s` 155.602)
failed the same check with its `report.md` under `/tmp/git_review_evidence_*`,
so this task's runner change does not cause it either. Every passing eval 41
run under the old run root used Cursor CLI 2026.10.01 or 2026.10.14, so the
failure follows the Cursor side: the CLI upgrade or the `auto` model behind it,
which one sample cannot separate. Evals 18 and 2 pass and their windows
overlap, which is the parallelism signal this file records.

## Second `--force` pair

The three-job sample above already provides overlapping windows across three
jobs. A later `--force` pair of ids 18 and 2 at the default worker count
(`run-20261101-010447`) overlapped again: both jobs started at
2026-11-01T01:05:01, eval 2 ended at 01:06:21 and eval 18 at 01:10:14, and
both passed. The serial retry of eval 41 is recorded in `timeout-band.md` as a
latency sample, not as overlap evidence.
