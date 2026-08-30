# RUNBOOK — tests/task_create

## Full suite

```bash
python3 tests/task_create/evals/run.py
```

Runs every id in `evals/evals.json` on a pinned sonnet worker, one at a time,
and prints a per-eval PASS/FAIL plus a tally. Exit code is 0 only when every
worker completed cleanly *and* its deterministic grade passed.

## One eval

```bash
python3 tests/task_create/evals/run.py reconcile-recorded
```

## Re-running past the verdict cache

A verdict is cached under `evals/.eval_cache/` keyed on the `task_create` and
base `task` skill sources, this harness directory, the model, and the prompt.
Edit either skill and the cache invalidates on its own. To force a fresh run
anyway:

```bash
python3 tests/task_create/evals/run.py --force
```

```bash
python3 tests/task_create/evals/run.py --no-cache
```

## Reading a failure

Each run writes `evals/workspace/run-<ts>/<id>/`:

- `response.txt` — the worker's user-facing turn. This is the graded surface
  for the "surfaced to the user" half of the rule; read it when a
  `response surfaces the open decision` check fails.
- `grading.txt` — every PASS/FAIL line plus the agent-attest notes.
- `sandbox/proj/tasks/` — the task file the worker actually wrote.
- `stderr.txt`, `timing.json` — worker diagnostics.

A `worker did not complete` line means the grade cannot be trusted: the worker
timed out or crashed, and grade.sh saw partial state.

## Staging a sandbox by hand

```bash
bash tests/task_create/evals/stage.sh labeled-why-open /tmp/tc-sandbox
```

Then drive the skill yourself with `/tmp/tc-sandbox/proj` as the working
directory, and grade it:

```bash
RESPONSE_FILE=/tmp/tc-sandbox/response.txt bash tests/task_create/evals/grade.sh labeled-why-open /tmp/tc-sandbox/proj
```

Without `RESPONSE_FILE` the grader falls back to the runner's conventional
path, and the surface checks fail loudly rather than passing vacuously.
