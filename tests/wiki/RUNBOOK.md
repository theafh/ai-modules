# Wiki skill regression: quick reference

For the full design, philosophy, and gotchas, see `README.md`. This is
the operator's quick-ref.

## Common commands

```bash
# Layer 1 only (deterministic, no LLM calls)
./tests/wiki/run_all.sh

# Layer 1 + Layer 2 (full regression; one vendor worker per pass, Cursor by default)
./tests/wiki/run_all.sh --layer2

# Single Layer 2 scenario while debugging
python3 ./tests/wiki/layer2/run.py --scenario L2-2

# A targeted subset — one run dir, one grading pass, one comparable benchmark
python3 ./tests/wiki/layer2/run.py --scenario AS-13,AS-14,AS-15

# Re-grade / re-render an existing run after assertion or evals.json edits
python3 ./tests/wiki/layer2/normalize.py tests/wiki/layer2/workspace/run-<ts>/
python3 ./tests/wiki/layer2/grade.py     tests/wiki/layer2/workspace/run-<ts>/
python3 ./tests/wiki/layer2/aggregate.py tests/wiki/layer2/workspace/run-<ts>/
python3 ./tests/wiki/layer2/render_report.py tests/wiki/layer2/workspace/run-<ts>/
```

## Output

```text
tests/wiki/layer2/workspace/run-<timestamp>/
  L2-*/pass-N/                         # per scenario × pass
    prompt.md      response.txt
    report.md      timing.json
    grading.json   sandbox-snapshot/
  grading_summary.json
  benchmark.json   benchmark.md        # regression compare lives here
  report.html                          # self-contained interactive viewer
```

Open `report.html` in a browser. The runner prints the scenario set, pass
count, vendor/model, and worker count at launch, and `benchmark.json` lists
the scenarios the run actually covered. Read that printed summary and the
`benchmark.json` scenario list to tell what a `run-<timestamp>/` directory covered;
the timestamp-only directory name does not identify the run kind.

The aggregator compares against the most recent prior `benchmark.json`, names
that baseline run and its shape (scenario count and ids), and prints an
explicit narrowing warning when the baseline does not cover every scenario in
the current run, including when it covered fewer. The warning does not change
exit status. The aggregator returns
non-zero only when an assertion that was 100% in the prior run is now <100%,
or a scenario that was clean across all passes now has a fail.

## Adding a scenario

1. Layer 1: edit `layer1/run.sh` to add a body function and a
   `scenario` invocation.
2. Layer 2: add a sandbox block in `layer2/setup_scenarios.sh` and a
   scenario block in `layer2/evals.json`.

See `README.md` § "Adding a scenario" for assertion type reference.

## Safety

Every Layer 2 scenario asserts `real_home_wiki_absent` and
`no_files_outside_sandbox`. Those are the fail-safes that justify
running on the operator's real filesystem rather than a container.
