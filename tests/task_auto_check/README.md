# task_auto_check regression harness

Regression coverage for the `task_auto_check` skill and its helper agents.
The harness is committed and runs locally; it does not ship inside the
plugin.

## Surfaces

| Surface | Where | What it tests |
| :--- | :--- | :--- |
| `script_tests/` | Deterministic shell assertions | Published artefact shape, family registration, gate delegation, loop boundaries, agent naming, and metadata wiring |
| `evals/` | Behavioral eval definitions | Staged task scenarios for the autonomous readiness loop: already-ready with mechanical lint cleanup, freeze-time intent drift routing, repair-to-ready, split-stuck, fidelity guard, no verified fix, cap override, agent-failure user stops (gate, drift, and verifier helper failures each stop with a clear error, options, and a user decision with zero auto-recovery), and guard re-baselining after the gate's own stamp |

The authored harness is committed; `tests/.gitignore` keeps run output out.
These tests do not ship inside the plugin, since `make deploy` copies only
the skill directory.

## Commands

```bash
./tests/task_auto_check/run_all.sh
python3 tests/task_auto_check/evals/run.py
```

Behavioral evals live in `evals/evals.json`. `evals/run.py` stages a
fresh sandbox per case, spawns a pinned worker to load
`plugins/ai_dev/skills/task_auto_check/SKILL.md`, captures the response
under `workspace/run-*/`, and grades the filesystem-verifiable
expectations with `evals/grade.sh`.
