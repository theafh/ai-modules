# task-family regression — quick reference

For the full design, see `README.md`. This is the operator's quick-ref.

## Harness rule

All harness logic lives under `tests/task/`. The skills under test are
read-only to the harness — fixtures stage their own sandboxes and never
patch the deployed or source skills. Every behavioral eval also asserts
an isolation fail-safe (no writes to the real repo's `tasks/` tree), so
the suite is safe to run on the operator's real filesystem.

## Common commands

```bash
# Both deterministic runners (fast, ~1 sec, no LLM cost). run_all.sh drives
# script_tests/run.sh then script_tests/contract_run.sh and aggregates their
# exit codes, so one failing surface still leaves the other's verdict visible.
./tests/task/run_all.sh

# Either surface alone while debugging it
bash tests/task/script_tests/run.sh           # lint.py / discover / init units
bash tests/task/script_tests/contract_run.sh  # family prose-contract assertions

# Behavioral evals (LLM cost). Three phases per eval id
# (create | check | implement | audit_gaps | audit_clean | finish | fix
#  | query | update | triage | lossless_split | lossless_single
#  | check_exclusion_requirement[_control] | check_exclusion_waiver[_control]
#  | ... — `evals/README.md` has the full table):
#   1. stage:  bash evals/stage.sh <id> -> shell-safe name=value output
#   2. run:    an agent loads $skill_path (or invokes the deployed Skill
#              $skill_name) and applies it to $sandbox_proj with $prompt,
#              RUN WITH $sandbox_proj AS THE WORKING DIRECTORY
#   3. grade:  bash evals/grade.sh <id> "$sandbox_proj"
eval "$(bash tests/task/evals/stage.sh finish)"
#   ... agent runs here, in $sandbox_proj ...
bash tests/task/evals/grade.sh finish "$sandbox_proj"

# Trigger evals (LLM cost) — family routing
python3 tests/trigger_evals/run.py \
  --eval-set tests/trigger_evals/task.json \
  --skill task --skill-path plugins/ai_dev/skills/task \
  --model claude-sonnet-4-6 --runs-per-query 3 --timeout 45 --workers 10
# Keep --skill-path: without it the family degenerates to ['task'] and the
# family metric stops meaning anything (precise scoring is unaffected).
```

## Output

```text
tests/task/results/
  script_tests.log                    # latest script_tests transcript
tests/task/script_tests/scratch/<id>/
                                      # transient per-scenario tasks trees
<target_dir>/                         # whatever stage.sh was given (or mktemp)
├── proj/                              the sandbox project (proj/tasks/ is the backlog)
└── .eval_started_at                   run-start epoch marker
tests/trigger_evals/results/task/<ts>/
  results.json, run.log               # precise/family routing verdict
```

## Adding a scenario

- **Bundled-script test**: add a body function + `scenario` line to
  `script_tests/run.sh`. Reuse the helpers (`fresh_tasks`, `write_task`,
  `emit`, `run_lint`, `run_discover_in`, `run_init`, `assert_*`).
- **Family contract assertion**: add an `assert_contains` /
  `assert_not_contains` / `assert_count` line to
  `script_tests/contract_run.sh`, using a literal from the live skill
  prose. When a skill reworks the wording a needle pins, refresh the
  needle to the new prose in the same change — the failure is the drift
  signal working.
- **Behavioral eval**: add an entry to `evals/evals.json`
  (`id`, `skill`, `prompt`, `expected_output`, `files`, `expectations`),
  a fixture `setup.sh` under `evals/fixtures/<id>/`, and the case
  branches in `evals/stage.sh` and `evals/grade.sh`. Grade on
  filesystem/git/suite state; leave verdict-string checks to
  `expectations[]` (agent-attest).
- **Trigger query**: add a `{query, expected_skill}` to
  `../trigger_evals/task.json`.

## Safety

Each `script_tests` scenario stages a fresh per-scenario tree; the
`d*`/`i*` discover/init scenarios stage outside the repo via `mktemp` so
the surrounding git tree never shadows the logic under test. Behavioral
fixtures stage under whatever path you pass to `stage.sh` (or a fresh
`mktemp -d`), and `grade.sh` asserts nothing was written to the real
repo's `tasks/`. If you see noise touching files outside the sandbox,
that's a harness bug, not a real test result.
