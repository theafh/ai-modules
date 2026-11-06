# agent_spinner parallel eval windows

Measurement of the `agent_spinner` behavioral evals running in the shared
`tests/lib/eval_runner.py` pool at the default 4 workers, with the per-eval
owned-name host guard. Vendor: Cursor (`agent -p`, model `auto`), the
project's measurement vendor, with no `--vendor` flag.

## Forced two-eval draw at 4 workers

```bash
python3 tests/agent_spinner/evals/run.py --workers 4 --force \
  smoke_inline_body smoke_withheld_shell
```

- Run dir: `tests/agent_spinner/workspace/run-20261106-230911`
- Pool: 4 workers (run header: `workers: 4`)
- Graded summary: `graded: 2/2 evals passed (0 from cache)` — `--force` made
  both evals uncached, so both windows are real worker time.

| id | started_at (local) | ended_at (local) | duration_s |
| --- | --- | --- | --- |
| `smoke_inline_body` | 2026-11-06 23:09:11 | 2026-11-06 23:10:06 | 55.2 |
| `smoke_withheld_shell` | 2026-11-06 23:09:11 | 2026-11-06 23:12:30 | 198.3 |

Both jobs open at 23:09:11, so their windows overlap for **55.2 s**, from
23:09:11 to 23:10:06 (the shorter window's full extent). Each `timing.json`
carries `started_at` and `ended_at` beside `duration_s`, and both evals grade
clean, so overlapping jobs keep their verdicts apart.

## Host status

`git status --porcelain` was captured immediately before the run and again
immediately after the last eval exited, before this file was written. The two
records were byte-identical: the run added no host path. Both snapshots
carried the same seven modified paths, all of them this change's own
uncommitted edits:

```text
 M tests/AGENTS.md
 M tests/CLAUDE.md
 M tests/README.md
 M tests/agent_spinner/README.md
 M tests/agent_spinner/evals/README.md
 M tests/agent_spinner/evals/run.py
 M tests/agent_spinner/evals/test_run.py
```

The run's own guard reported no escape for either eval, and this file is
written after that final snapshot.

## Guard attribution

The live draw proves the pool and the clean host. The attributable-escape half
is proven hermetically, without a model call, by
`tests/agent_spinner/evals/test_run.py`'s `owned-name host escape guard` case:
two overlapping stub jobs run through `run.py`'s own `HostEscapeGuard` hooks,
one job writes a canary into a throwaway host mirror whose basename its sandbox
owns, and only that job's verdict fails while its sibling stays `PASS`.

## Reading the numbers

`started_at` and `ended_at` are `time.time()` epoch seconds in `timing.json`;
the table above renders them as local wall-clock time. `duration_s` is
`ended_at - started_at` and covers the micro-deployment, the worker run, and
the provenance capture for that eval.
