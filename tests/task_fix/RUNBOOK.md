# RUNBOOK: tests/task_fix

## Full suite

```bash
python3 tests/task_fix/evals/run.py
```

Runs every id in `evals/evals.json` on the default Cursor worker, one at a time,
and prints a per-eval PASS/FAIL plus a tally. Exit code is 0 only when every
worker completed cleanly *and* its deterministic grade passed.

## One eval

```bash
python3 tests/task_fix/evals/run.py regroup_live_skip_archived
```

## Re-running past the verdict cache

A verdict is cached under `evals/.eval_cache/` keyed on the `task_fix` skill,
the base `task` skill, the `auto_*_task` agents, this harness directory, the
model, and the prompt. Edit the react protocol or any of those artefacts and
the cache invalidates on its own. To force a fresh run anyway:

```bash
python3 tests/task_fix/evals/run.py --force
```

```bash
python3 tests/task_fix/evals/run.py --no-cache
```

## Reading a failure

Each run writes `workspace/run-<ts>-<pid>/<id>/`:

- `response.txt`: the run's report. This is the graded surface for every
  disposition-line check; read it when a `the report carries …` check fails.
- `grading.txt`: every PASS/FAIL line plus the agent-attest notes.
- `sandbox/proj/tasks/`: the tree as the run left it.
- `stderr.txt`, `timing.json`: worker diagnostics.

A `worker did not complete` line means the grade cannot be trusted: the worker
timed out or crashed, and grade.sh saw partial state.

## Reading the failure shapes that matter

A **regroup that dropped a link instead of gathering** shows up as a cleared
warn with `the gathered account sits in ## Context only` failing, because the
account is still narrated twice with one link. On `regroup_state_and_edit_site`
the same shortcut fails `no other section restates the page's current state` or
`no other section restates the edit outside Acceptance`. A **run that keeps the
repeat** shows up there as `the repeated-link warn is cleared` and `the report's
line for this finding reads regrouped` failing, with `no disposition line for
this finding reads kept` naming the retired disposition: the run judged each
link on its own instead of reorganizing the body.

On `regroup_same_paragraph` the repeat sits inside one paragraph, so the
correct edit names the sibling again in plain text there. A **run that leaves
the paragraph alone** fails `the repeated-link warn is cleared` and `no line
for this finding reads kept or surfaced`, and a **run that moves material out
of the paragraph** fails `## Goal, ## Approach, and ## Acceptance read as
staged`.

## Staging a sandbox by hand

```bash
bash tests/task_fix/evals/stage.sh regroup_state_and_edit_site /tmp/tf-sandbox
```

Then drive the skill yourself with `/tmp/tf-sandbox/proj` as the working
directory, and grade it:

```bash
RESPONSE_FILE=/tmp/tf-sandbox/response.txt bash tests/task_fix/evals/grade.sh regroup_state_and_edit_site /tmp/tf-sandbox/proj
```

Without `RESPONSE_FILE` the grader falls back to the runner's conventional
path, and the report checks fail loudly rather than passing vacuously.
