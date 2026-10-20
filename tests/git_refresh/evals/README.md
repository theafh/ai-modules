# git_refresh skill evals (behavioral surface)

Behavioral evals for the `git_refresh` skill. The mechanical surface
(bundled-script unit tests) lives next door in `script_tests/`.

This directory holds the eval definitions, their fixtures, and the runner that
drives them. Run output lands under `tests/git_refresh/workspace/`, which
`tests/.gitignore` keeps out of git.

## Layout

```text
tests/git_refresh/evals/
├── README.md        # this file
├── evals.json       # canonical eval prompts, fixtures, and expectations
├── run.py           # worker runner: stage → vendor worker → grade
├── stage.sh         # stage one eval's fixture, print the agent-ready inputs
├── grade.sh         # grade the post-run repository programmatically
└── fixtures/        # per-eval repository stagers plus _common.sh
```

## How these run

`python3 tests/git_refresh/evals/run.py` runs every eval in `evals.json`; name
ids (`run.py 2 3`) to run a subset. Each eval is one job in the shared pool
from `tests/lib/eval_runner.py`, which runs four jobs at once by default and
gives each its own `TMPDIR`; `--workers 1` serializes them. A job stages its
fixture with `stage.sh` into a fresh sandbox root outside the checkout,
micro-deploys the skill into a scratch home, wraps the deployed
`refresh_repo.sh` in a logging shim, runs one print-mode worker on the default
Cursor vendor (`agent -p`, model `auto`), and grades the clone with
`grade.sh`. The shim appends one `refresh_repo.sh <args>` line per call to the
sandbox root's `script_calls.log` and then runs an unshimmed copy of the
deployed helper. A stage that fails or names no sandbox repository stops the
eval as a harness fault before any worker starts. Each eval leaves `response.txt`, `stderr.txt`, `timing.json`,
`grading.txt`, and a copy of its sandbox under
`tests/git_refresh/workspace/run-<ts>-<pid>/<id>/`, and the run closes with a
graded summary naming every eval and its verdict.

An eval passes when its worker completed with a response, both read checks in
`timing.json` (`artefacts_read_from_micro_deployment` and `checkout_unread`)
passed, and `grade.sh` passed. The verdict cache in `evals/.eval_cache/`
replays an eval whose inputs are unchanged without spawning a worker, and a run
that replays every verdict also skips the auth probe. `--force` re-runs every
eval and refreshes its stored verdict; `--no-cache` re-runs without reading or
writing the cache. `--vendor claude` (`claude -p`, model `sonnet`) runs only
where an eval needs a Claude-specific feature or the operator asks for a Claude
run, as the model policy in `tests/CLAUDE.md` states.

`grade.sh` asserts what the repository shows after the run: the branch `HEAD`
ends on, the default-branch tip after the fast-forward, which local branches
are gone or survive, and the uncommitted content eval 4 must keep. It compares
against the snapshots `stage.sh` takes under `<target>/.eval/` before the run.
Eval 3 also reads `script_calls.log`, because its default run already deletes
`gone-merged` before any opt-in and the repository looks the same with or
without the gated follow-up: the log must record a default run with no
arguments and a later `--prune-gone` call. The expectations that speak only
about the response, and which helper ran in evals 1, 2, and 4, print as
`response` lines; confirm those by reading `response.txt`.

The three phases also run by hand for debugging:

```bash
# 1. Stage one eval; prints shell-safe sandbox_repo, skill_path, prompt lines
eval "$(bash tests/git_refresh/evals/stage.sh <eval_id>)"

# 2. Have an agent load $skill_path and apply $prompt inside $sandbox_repo.

# 3. Grade the post-run repository
bash tests/git_refresh/evals/grade.sh <eval_id> "$sandbox_repo"
```

Only the runner's shim writes `script_calls.log`, so a hand run of eval 3 fails
its two log checks unless you append one `refresh_repo.sh <args>` line per
helper call you made to `$sandbox_repo/../script_calls.log`.

## Schema

`evals.json` follows the skill-creator-style shape used across the Pattern A
harnesses in this repo:

```text
{ skill_name, evals: [ { id, prompt, expected_output, files, expectations[] } ] }
```

`files` names the fixture stager for that eval, relative to
`tests/git_refresh/`. `stage.sh` reads both the stager and the prompt from this
file, so `evals.json` stays the one source of each eval's inputs.

## The evals

| id | Fixture | What it exercises |
| --- | --- | --- |
| 1 | `default_branch_master` | A repository whose default branch is `master`, whose origin gained an upstream commit after the clone's last fetch, and which holds a cleanly merged local branch: detect `master` from `origin/HEAD`, fast-forward it to the upstream commit, delete `merged-topic` with `git branch -d`, and report every action. |
| 2 | `safe_default_run` | A clean worktree on an upstream-gone branch that carries a unique commit, beside a cleanly merged branch: the default run deletes only `merged-topic`, keeps `gone-unique`, and offers the gated cleanup with that unique commit listed. |
| 3 | `gated_prune_gone` | Two upstream-gone branches, one fully merged into `main` and one with a unique commit, with the opt-in in the prompt: the default run comes first, the gated `--prune-gone` follows, `gone-merged` is gone, and `gone-unique` survives because it needs force-delete confirmation. |
| 4 | `dirty_worktree` | An untracked file on a feature branch: report the dirty worktree, skip the switch and fast-forward, and leave the branch and the uncommitted file untouched with no stash. |

## Fixtures

`fixtures/_common.sh` holds the shared helpers. `init_remote_repo` stages a bare
origin plus a clone of it with one seed commit pushed and `origin/HEAD` set to
the default branch, so the default-branch detection resolves from the remote
HEAD the way it does on a real clone. Each fixture then shapes the branches its
eval needs: `default_branch_master` publishes the merged topic before a side
clone under `upstream/` pushes the upstream commit, so that commit stays a
fast-forward of local `master`; the two upstream-gone fixtures push a branch
and then delete it on origin, so the run's `git fetch --prune` reports its
upstream as gone.
