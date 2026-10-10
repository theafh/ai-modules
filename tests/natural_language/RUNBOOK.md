# RUNBOOK: tests/natural_language/

Operational guide for the natural-language style harness. Design and the load
route live in `README.md`.

## Pre-flight

The runner probes the CLI login once, then stages the marker style
`nl_load_marker` and aborts when that marker is missing on a CLI that is not
newer than 2.1.226. A trailing-comma settings file aborts on its own:

```bash
python3 tests/natural_language/evals/test_run.py
python3 tests/natural_language/evals/test_grade.py
python3 tests/natural_language/evals/run.py --preflight malformed
```

The route unit test covers the marker-present route and both marker-missing
version branches. The wrap unit test grades the faithful and flattened samples
with prose wrapped at 72 columns. The malformed-settings command exits before
any scenario pass and starts no worker, so these three checks spend no model
call.

## The recorded measurement

Every scenario run below runs on Claude, and each command names
`--vendor claude` so that stays visible: run one where a change to the style
needs the measurement, in the foreground.

```bash
python3 tests/natural_language/evals/run.py --vendor claude --run-label baseline \
  --style /path/to/style-before-the-edit.md
python3 tests/natural_language/evals/run.py --vendor claude --run-label refined
```

The default style is `styles/natural-language.md`. The runner's own default
is Claude as well, and `--vendor cursor` stops with an error because this
harness exercises Claude output-style selection.
The default `--workers` value is `vendor.DEFAULT_PARALLEL_WORKERS`. `--passes`
changes the denominator and the report records the value that ran. There is
no verdict cache.

```bash
python3 tests/natural_language/evals/run.py --vendor claude connected_rewrite --passes 1
python3 tests/natural_language/evals/run.py --vendor claude --skip-judge --passes 1
```

## Reading the result

```text
tests/natural_language/results/run-<ts>.{json,md}
tests/natural_language/workspace/run-<ts>/<scenario>/pass-<n>/
```

The report records the CLI version and the preflight result. A scenario below
the bar lists its measured rate and the diverging assertions and leaves the
disposition to the operator. A baseline run that passes every
`connected_rewrite` assertion says the fixture does not discriminate, and that
sentence is in the baseline report.
