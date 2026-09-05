# skill_doctor harness runbook

## Script tests

```bash
./tests/skill_doctor/run_all.sh
# or
./tests/skill_doctor/script_tests/run.sh
```

Expect every scenario to PASS. Failures print under `Failed ids:`.

## Evals

```bash
python3 tests/skill_doctor/evals/run.py
```

One sonnet-pinned `claude -p` worker per eval, graded deterministically by
`evals/grade.sh`, with the shared verdict cache on by default (`--force`
resamples, `--no-cache` bypasses). Results land in
`workspace/run-<ts>/`, and `summary.json` there is the verdict of record.

`evals/README.md` carries the manual stage-run-grade path and explains why
skill-creator's `scripts.run_eval` is the wrong runner for these: it is a
trigger evaluator, not a behavioral one.

## Reading a result

Trust the ground-truth files over anything that flickers through the
session's notification stream:

1. `run.py`'s exit code.
2. `workspace/run-<ts>/summary.json`.
3. Per-eval `grading.txt` and `timing.json` (`claude_rc` non-zero means the
   worker died, so its grade reflects partial state).
