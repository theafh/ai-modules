# skill_doctor parallel eval windows

Measurement of the `skill_doctor` behavioral evals running in the shared
`tests/lib/eval_runner.py` pool at the default 4 workers. Vendor: Cursor
(`agent -p`, model `auto`), the project's measurement vendor, with no
`--vendor` flag.

## Run 1: default suite, default worker count

```bash
python3 tests/skill_doctor/evals/run.py
```

- Run dir: `tests/skill_doctor/workspace/run-20261106-222840`
- Pool: 4 workers (run header: `workers: 4`)
- Graded summary: `graded: 8/8 evals passed (0 from cache)`

| id | started_at (local) | ended_at (local) | duration_s |
| --- | --- | --- | --- |
| `scope_single_skill_clean` | 2026-11-06 22:28:47 | 2026-11-06 22:30:05 | 78.7 |
| `discovery_risky_sibling` | 2026-11-06 22:28:47 | 2026-11-06 22:29:48 | 61.8 |
| `scope_hub_family` | 2026-11-06 22:28:47 | 2026-11-06 22:29:47 | 60.6 |
| `scope_prefix_only` | 2026-11-06 22:28:47 | 2026-11-06 22:29:41 | 54.3 |
| `scope_whole_repo` | 2026-11-06 22:29:41 | 2026-11-06 22:30:45 | 64.1 |
| `scope_unresolvable_selector` | 2026-11-06 22:29:47 | 2026-11-06 22:30:14 | 26.1 |
| `registration_no_manifest` | 2026-11-06 22:29:49 | 2026-11-06 22:30:38 | 49.2 |
| `verification_repo_checks` | 2026-11-06 22:30:06 | 2026-11-06 22:31:04 | 58.2 |

Maximum concurrency: **4** — the pool width. The first four evals open
together at 22:28:47 and the remaining four backfill as slots free. The
last four also overlap: `scope_whole_repo` ∩ `scope_unresolvable_selector`
runs 22:29:47 → 22:30:14 (26.1 s), `scope_whole_repo` ∩
`registration_no_manifest` runs 22:29:49 → 22:30:38 (49.2 s), and
`verification_repo_checks` overlaps `scope_whole_repo` from 22:30:06 to
22:30:45 (39.6 s).

## Run 2: forced two-eval draw at 4 workers

```bash
python3 tests/skill_doctor/evals/run.py --workers 4 --force \
  scope_hub_family scope_prefix_only
```

- Run dir: `tests/skill_doctor/workspace/run-20261106-223115`
- Pool: 4 workers (run header: `workers: 4`)
- Graded summary: `graded: 2/2 evals passed (0 from cache)` — both evals
  were uncached, so both windows are real worker time.

| id | started_at (local) | ended_at (local) | duration_s |
| --- | --- | --- | --- |
| `scope_prefix_only` | 2026-11-06 22:31:22 | 2026-11-06 22:32:22 | 60.1 |
| `scope_hub_family` | 2026-11-06 22:31:22 | 2026-11-06 22:32:26 | 63.7 |

Both jobs start at the same instant, so the two windows overlap for
**60.1 s**, from 2026-11-06 22:31:22 to 2026-11-06 22:32:22 (the shorter
window's full extent). Each `timing.json` carries `started_at` and
`ended_at` beside `duration_s`, and both runs grade clean, so the isolated
sandbox roots and the per-eval checksum manifest keep concurrent verdicts
apart.

## Reading the numbers

`started_at` and `ended_at` are `time.time()` epoch seconds in
`timing.json`; the tables above render them as local wall-clock time.
`duration_s` is `ended_at - started_at` and covers the micro-deployment,
the worker run, and the provenance capture for that eval.
