# git_refresh runbook

## Run the deterministic surface

```bash
./tests/git_refresh/run_all.sh
```

The command writes the latest script-test transcript to
`tests/git_refresh/results/layer1.log`.

## Run the behavioral evals

```bash
python3 tests/git_refresh/evals/run.py            # every eval, default Cursor worker
python3 tests/git_refresh/evals/run.py 2 3        # a subset by id
python3 tests/git_refresh/evals/run.py --force    # re-run despite cached verdicts
```

The runner stages each eval into its own sandbox root, runs one worker per eval
four at a time (`--workers 1` serializes), grades the repository with
`evals/grade.sh`, and prints a graded summary naming every eval and its
verdict. An eval whose inputs are unchanged replays its cached verdict without
a worker; `--no-cache` re-runs without reading or writing the cache.
`evals/README.md` has the full run options and what each grade asserts.

Each eval's run directory, `tests/git_refresh/workspace/run-<ts>-<pid>/<id>/`,
holds `response.txt`, `timing.json`, `grading.txt`, and a `sandbox/` copy of
the staged repositories after the run, including `script_calls.log`, where
the runner's logging shim records each `refresh_repo.sh` call in order. Confirm
the `response` lines `grade.sh` prints against `response.txt`, since they
cover what neither the repository nor that log can show, such as the follow-up
question.

To debug one eval by hand, stage it, run the skill yourself, and grade:

```bash
eval "$(bash tests/git_refresh/evals/stage.sh 1 /tmp/git-refresh-eval)"
# load $skill_path and apply $prompt inside $sandbox_repo
bash tests/git_refresh/evals/grade.sh 1 "$sandbox_repo"
```

Staging leaves an empty `script_calls.log` beside the clone, and only the
runner's shim writes to it. Before grading eval 3 by hand, append one
`refresh_repo.sh <args>` line per helper call you made, or its two log checks
fail.

## Read a fixture before blaming the skill

A default run that reports a divergence instead of a fast-forward, or keeps a
branch the eval expects gone, usually points at the staged history rather than
the skill. Compare the clone with its origin before the run:

```bash
cd /tmp/git-refresh-eval/repo
git log --oneline --graph --all
git ls-remote --heads origin
```

The bundled helper's own report is the quickest cross-check: running
`plugins/ai_dev/skills/git_refresh/scripts/refresh_repo.sh` inside a freshly
staged clone shows what a correct run of the skill does to that fixture.
