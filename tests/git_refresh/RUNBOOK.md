# git_refresh runbook

## Run the deterministic surface

```bash
./tests/git_refresh/run_all.sh
```

The command writes the latest script-test transcript to
`tests/git_refresh/results/layer1.log`.

## Stage a behavioral eval fixture

```bash
bash tests/git_refresh/evals/fixtures/default_branch_master/setup.sh /tmp/git-refresh-eval
```

Then run the `git_refresh` skill against the staged repository using the prompt
from `evals/evals.json`, and inspect the repository plus transcript against the
listed expectations.
