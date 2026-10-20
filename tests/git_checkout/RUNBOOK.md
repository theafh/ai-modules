# git_checkout runbook

## Run the deterministic surface

```bash
./tests/git_checkout/run_all.sh
```

The command writes the latest script-test transcript to
`tests/git_checkout/results/layer1.log`.

## Run the behavioral evals

```bash
python3 tests/git_checkout/evals/run.py            # every eval, default Cursor worker
python3 tests/git_checkout/evals/run.py 3 4        # a subset by id
python3 tests/git_checkout/evals/run.py --force    # re-run despite cached verdicts
```

The runner stages each eval into its own sandbox root, runs one worker per eval
four at a time (`--workers 1` serializes), grades the repository with
`evals/grade.sh`, and prints a graded summary naming every eval and its
verdict. An eval whose inputs are unchanged replays its cached verdict without
a worker; `--no-cache` re-runs without reading or writing the cache.
`evals/README.md` has the full run options and what each grade asserts.

Each eval's run directory, `tests/git_checkout/workspace/run-<ts>-<pid>/<id>/`,
holds `response.txt`, `timing.json`, `grading.txt`, and a `sandbox/` copy of
the staged repositories after the run. Confirm the `response` lines
`grade.sh` prints against `response.txt`, since they cover what the
repository cannot show.

To debug one eval by hand, stage it, run the skill yourself, and grade:

```bash
eval "$(bash tests/git_checkout/evals/stage.sh 3 /tmp/git-checkout-eval)"
# load $skill_path and apply $prompt inside $sandbox_repo
bash tests/git_checkout/evals/grade.sh 3 "$sandbox_repo"
```

## Read a fixture before blaming the skill

Every fixture pushes its branches from a throwaway side clone, so the staged
repository deliberately starts without the remote-tracking refs. A run that
reports the branch as nonexistent when the fixture meant it to be found is
usually a fetch that did not happen, not a missing branch. Confirm the fixture
first:

```bash
cd /tmp/git-checkout-eval/repo
git for-each-ref --format '%(refname:short)' refs/heads refs/remotes
git ls-remote --heads origin
```

The first command shows what the clone can see without fetching, and the second
shows what the remote actually carries. `restricted_refspec` is the one fixture
where the gap between them is the point: the branch stays invisible however
often the clone fetches, because the single-branch clone's refspec never maps
it.

## Distinguish an outcome from a failure

The helper reports its outcome through its exit code, so a non-zero status is
often the expected result rather than a broken run:

| Code | Meaning |
| --- | --- |
| 0 | the repository is on the requested branch |
| 1 | usage or environment error |
| 3 | a bare name resolved on several remotes; the run asked which to track |
| 4 | the name resolved nowhere; the run reported the cause |
| 5 | git refused the switch because local changes would be overwritten |

Codes 3, 4, and 5 leave the repository untouched by design. Treat the
`references/manual_fallback.md` path as reachable only for code 1 and for a
missing script file.
