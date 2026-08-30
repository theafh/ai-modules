# task_auto_check behavioral evals

These eval definitions cover the model-mediated behavior of
`task_auto_check`. They use the same Pattern A convention as the other
newer harnesses in this repo: `evals.json` carries prompts and
expectations, and `fixtures/*/setup.sh` stages sandboxes for an agent to
run in.

The deterministic `script_tests/` surface verifies static packaging and
registration. These evals verify loop behavior when a worker actually
loads the skill and operates on staged tasks.

```bash
python3 tests/task_auto_check/evals/run.py
python3 tests/task_auto_check/evals/run.py already_ready repair_to_ready
```

The runner captures each worker transcript and deterministic grade under
`../workspace/run-*/<eval-id>/`.
