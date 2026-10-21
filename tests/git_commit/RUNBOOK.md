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
# Bundled-script unit tests (fast, deterministic, ~15 sec, no LLM cost)
./tests/git_commit/run_all.sh

# Behavioral evals (LLM cost). run.py drives all three phases with a
# Cursor worker by default, over every id in evals/evals.json, four
# evals at a time; see evals/README.md for its options.
python3 tests/git_commit/evals/run.py
python3 tests/git_commit/evals/run.py --workers 1   # one eval at a time

# The same three phases by hand:
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
  parallel-tmpdir-windows.md          # recorded overlap of a --workers 4 run
tests/git_commit/script_tests/scratch/<id>/
                                      # transient per-scenario git repos
tests/git_commit/workspace/run-<ts>/<id>/
                                      # run.py per-eval records (response, timing, grade)
<target_dir>/                         # whatever stage.sh was given (or mktemp)
├── repo/                              the sandbox git repo
├── skill_under_test/                  (evals 5 to 7) edited skill copy, overlaid by run.py
└── .eval_started_at                   staged HEAD SHA marker
```

`tests/git_commit/workspace` is the only run root `run.py` writes. Each
`timing.json` there records the worker's `started_at` and `ended_at`
beside `duration_s`, so the windows of one run show whether its evals
overlapped.

## Parallel evals and the TMPDIR straggler scan

`run.py` runs its evals through the shared pool in
`tests/lib/eval_runner.py`, `--workers 4` by default. Every job gets
its own `TMPDIR` (with `TEMP` and `TMP`), and `run.py` hands that same
directory to the worker and to `grade.sh`. The skill's
`prepare_commit_context.sh` writes its `git_commit_context.*` file
under `$TMPDIR`, and `grade.sh`'s straggler `find` runs against
`$TMPDIR` with
`-maxdepth 1 -name 'git_commit_context.*' -newer "$marker"`,
where `marker` is `$target/.eval_started_at`. A concurrent
eval's context file therefore sits in its own job's directory and never
reaches this eval's scan. Eval 6 returns before the scan, because its
paused run legitimately leaves the context file behind. A hand-run
`grade.sh` with `TMPDIR` unset scans `/tmp`, the prepare script's own
fallback. The `g1` scenario in `script_tests/run.sh` proves the
isolation on two sibling dummy `TMPDIR` trees.

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
