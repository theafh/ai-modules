# git_checkout runbook

## Run the deterministic surface

```bash
./tests/git_checkout/run_all.sh
```

The command writes the latest script-test transcript to
`tests/git_checkout/results/layer1.log`.

## Stage a behavioral eval fixture

```bash
bash tests/git_checkout/evals/fixtures/two_remotes_same_name/setup.sh /tmp/git-checkout-eval
```

Each `setup.sh` prints the path of the staged clone as its last line. Then run
the `git_checkout` skill against that clone using the prompt from
`evals/evals.json`, and inspect the repository plus transcript against the
listed expectations.

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
