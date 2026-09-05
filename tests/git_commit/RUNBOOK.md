# git_commit skill regression: quick reference

For the full design, see `README.md`. This is the operator's
quick-ref.

## Harness rule

The installed skill-creator skill is **read-only** for this harness.
Nothing under `tests/git_commit/` copies into, overwrites, or patches
it. All harness logic lives in this directory. See
`evals/README.md` for the rule and the rationale.

## Common commands

```bash
# Bundled-script unit tests (fast, deterministic, ~1 sec, no LLM cost)
./tests/git_commit/run_all.sh

# Behavioral evals (LLM cost). Three phases:
#   1. stage:  bash evals/stage.sh <id> -> shell-safe name=value output
#   2. run:    an agent applies $skill_path to $sandbox_repo with $prompt
#   3. grade:  bash evals/grade.sh <id> "$sandbox_repo"
#
# Example end-to-end smoke (a real run replaces the manual git commit
# with the agent loading $skill_path and applying it):
eval "$(bash tests/git_commit/evals/stage.sh 1)"
( cd "$sandbox_repo"
  ctx="$(bash "$(dirname "$skill_path")/scripts/prepare_commit_context.sh" | head -n 1)"
  printf 'seed.txt -> tweak baseline\n' \
    | bash "$(dirname "$skill_path")/scripts/commit_with_message.sh" "$ctx" )
bash tests/git_commit/evals/grade.sh 1 "$sandbox_repo"
```

## Output

```text
tests/git_commit/results/
  layer1.log                          # latest script_tests transcript
tests/git_commit/script_tests/scratch/<id>/
                                      # transient per-scenario git repos
<target_dir>/                         # whatever stage.sh was given (or mktemp)
├── repo/                              the sandbox git repo
├── skill_under_test/                  (eval 5 only) per-sandbox stubbed skill
└── .eval_started_at                   staged HEAD SHA marker
```

There is no `workspace/iteration-N/` tree. That was inherited from
an aspirational skill-creator runner that doesn't actually exist for
this kind of eval. The harness now stages each run wherever you
point it.

## Adding a scenario

- **Bundled-script test**: add a body function + `scenario` line to
  `script_tests/run.sh`. Use the existing helpers (`fresh_repo`,
  `run_commit`, `run_prepare`, `run_prepare_content`, `assert_*`).
- **Behavioral eval**: add an entry to `evals/evals.json`
  (`id`, `prompt`, `expected_output`, `files`, `expectations`), a
  fixture `setup.sh` under `evals/fixtures/<name>/`, and the case
  branches in `stage.sh` and `grade.sh`.

## Safety

Every script_tests scenario stages a *fresh* per-scenario temp git
repo under `script_tests/scratch/<id>/` and operates only on that
tree. The runner never invokes git commands against the host repo's
working tree. If you see scenario noise touching files outside
`tests/git_commit/`, that's a harness bug, not a real test result.

Eval fixtures stage their sandbox under whatever path you pass to
`stage.sh` (or a fresh `mktemp -d` if you don't). The fixtures
themselves do not touch the host repo.
