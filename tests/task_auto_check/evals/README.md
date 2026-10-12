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

## Frozen commitments and isolated gates

| Eval | Evidence graded |
| :--- | :--- |
| `committed_rule_deletion_routed` | All frozen rules remain verbatim; gate issues name both unproven preservation promises; verifier records route deletions or add proof |
| `last_call_ready_refuted` | The second gate reaches ready under max rounds 2, followed by citation verification; a refutation receives one re-gate and no body repair |
| `regate_isolated` | A decoy earlier verdict cannot hide the planted proof gap; gate prompts contain only admitted inputs and every gate confirms isolation |
| `repair_to_ready` | A ready before the cap has no citation-mode relay return |

`relay_checks.py` grades these saved prompt and return files. Its deterministic
self-tests exercise passing evidence and mutations that violate each property.
The runner derives `DEFAULT_IDS` from `evals.json`, so new entries join the
ordinary suite automatically.
