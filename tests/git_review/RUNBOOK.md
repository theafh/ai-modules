# git_review harness runbook

Operating notes for running this harness correctly. `README.md` has the layout
and what each surface covers.

## Run the script tests first

```bash
./tests/git_review/run_all.sh
```

About five seconds, no LLM cost. Every eval below assumes these pass: an eval
failure on top of a red script test is almost always the script, not the skill.

## Run one eval before running all of them

Forty-eight evals at up to ten minutes each is a long, expensive run. Validate a
fixture with a single eval first:

```bash
python3 tests/git_review/evals/run.py 1
```

Read `workspace/run-<ts>/1/response.txt` and `grading.txt` before widening. A
fixture-design bug caught on one eval costs minutes; the same bug caught across
a full run costs hours.

## Stage a fixture by hand to inspect it

```bash
eval "$(bash tests/git_review/evals/stage.sh 32 /tmp/gr32)"
echo "$sandbox_repo"   # the repo the skill reviews
echo "$prompt"         # the user prompt
echo "$gh_env"         # the stub-gh env file, empty for git-only evals
```

Staging prepares the fixture and an empty `$target/script_calls.log`, and it
stages no skill. During a run, `run.py` micro-deploys `git_review`,
`git_checkout`, `git_commit`, `git_refresh`, and the `guardrail` hub into a
per-eval scratch home and wraps every deployed bundled script in a logging
shim. Each shim appends its call to that
log and then runs an unshimmed copy of the deployed script kept in the same
scratch home, so a hand-staged fixture records no script calls.

For a forge eval, put the stub on `PATH` before running anything by hand:

```bash
set -a; . "$gh_env"; set +a
export PATH="$GH_STUB_BIN:$PATH"
gh pr view 7 --json body     # served from the fixture payloads
cat "$GH_STUB_LOG"           # every call the run made
```

## Grade an already-run sandbox

```bash
bash tests/git_review/evals/grade.sh 32 "$sandbox_repo" \
  tests/git_review/evals/workspace/run-<ts>/32/response.txt
```

`grade.sh` prints `PASS`/`FAIL` per check and `agent-attest` for the
expectations only a reading of the transcript settles. An `agent-attest` line is
not a pass: read it against `response.txt` before calling the eval green.

## The verdict cache

Verdicts live in `evals/.eval_cache/` (gitignored, like `workspace/`). The key
covers the `git_review` skill directory, the `git_checkout` and `git_commit`
skill directories it hands work to, the `git_refresh` skill directory whose
default-branch detection it follows, the `guardrail` skill directory whose
authority hierarchy it ranks findings by, the whole `evals/` harness, the
shared verdict helpers under `tests/lib` (`eval_cache.VERDICT_HELPERS`), the
worker model, the eval id, and the prompt. Change any of those and the eval re-runs.

- `--force` re-runs everything and refreshes the cache. Use it to resample the
  stochastic worker on unchanged inputs.
- `--no-cache` neither reads nor writes it.

## Timeouts

`--timeout` defaults to 600s, longer than the `git_commit` harness. A review
reads every changed file, and the `deep_file_defect` fixture is a whole-file
diff spanning several thousand lines by design; a fresh Cursor run of eval 18
measured about 52 seconds. If a run shows a transient single-eval timeout that
recovers on retry, raise the timeout rather than chasing the symptom.

Run these sequentially. Two review workers on one machine contend for the model
and both slow past the timeout; `run.py` already runs them in order.

## Reading a run

```text
tests/git_review/evals/workspace/run-<ts>/<id>/
├── response.txt    the worker's final response, the prose evidence
├── stderr.txt      worker stderr; a 401 here is an auth problem, not a regression
├── timing.json     duration and the CLI return code
├── gh_calls.log    (forge evals) every stub gh invocation, in order
├── grading.txt     grade.sh output
└── sandbox/        the staged fixture as the run left it
```

Check three things after any run: the runner's exit code, `grading.txt` per
eval, and `timing.json` for a non-zero `claude_rc`. A worker that did not
complete fails its eval regardless of what `grade.sh` found, because `grade.sh`
would then be reading partial sandbox state.

## The fixture that needs care

`unreadable_path` restages the sandbox as a blobless partial clone with
sparse-checkout that omits `src/locked.py`, then deletes that path's new blob
from both the clone and the bare origin so no git command and no file read can
produce the hidden content. Ordinary workspace removal is enough; the run
directory carries no chmod-000 files.
