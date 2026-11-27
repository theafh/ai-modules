# update_features harness

Deterministic and behavioural coverage for the `update_features` skill, which
maintains a repository-root `FEATURES.md` behaviour ledger from the codebase.

## Layout

```text
tests/update_features/
├── README.md              # this file
├── run_all.sh             # deterministic entrypoint (`make test` runs it)
├── script_tests/run.sh    # script unit tests for the bundled helper
├── script_tests/scratch/  # transient per-scenario sandboxes (gitignored)
└── evals/
    ├── evals.json         # skill-creator-aligned behavioural evals
    ├── grade.sh           # deterministic grader for a produced ledger
    └── fixtures/
        ├── ledger-fixture/          # one built capability and one declared target
        └── ledger-fixture-refresh/  # the same repo after the declared target shipped
```

## What runs where

- `run_all.sh` runs `script_tests/run.sh`, the deterministic surface the
  aggregate `tests/run_all.sh` gate discovers. It covers the bundled
  `scan_features_sources.sh` helper (surface enumeration, declared-target
  markers, determinism, non-git fallback) and the skill's independence: no
  `tasks/` dependency, and a task lifecycle that requires no `FEATURES.md`.
- `evals/evals.json` carries the behavioural evals. They grade an agent's
  composed ledger, so they run out of band; `evals/grade.sh <eval-id>
  <FEATURES.md> [<pre-run FEATURES.md>]` is the deterministic grader for the
  file those runs produce. `script_tests` exercises the grader in both
  directions (t8 accepts a conforming ledger, t9 rejects a stale one).
- `evals/fixtures/ledger-fixture/expected-FEATURES.md` is the recorded ledger a
  conforming eval-1 run produces; `t8` grades it.

## Adding a scenario

Add the deterministic case to `script_tests/run.sh` as one `tN_` function with
a matching call line, using `fresh <id>` for its sandbox. Add a behavioural
case to `evals/evals.json` with its fixture under `evals/fixtures/`.
