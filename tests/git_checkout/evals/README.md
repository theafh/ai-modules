# git_checkout skill evals (behavioral surface)

Behavioral evals for the `git_checkout` skill. The mechanical surface
(bundled-script unit tests) lives next door in `script_tests/`.

This directory holds the eval definitions, their fixtures, and the runner that
drives them. Run output lands under `tests/git_checkout/workspace/`, which
`tests/.gitignore` keeps out of git.

## Layout

```text
tests/git_checkout/evals/
├── README.md        # this file
├── evals.json       # canonical eval prompts, fixtures, and expectations
├── run.py           # worker runner: stage → vendor worker → grade
├── stage.sh         # stage one eval's fixture, print the agent-ready inputs
├── grade.sh         # grade the post-run repository programmatically
└── fixtures/        # per-eval repository stagers plus _common.sh
```

## How these run

`python3 tests/git_checkout/evals/run.py` runs every eval in `evals.json`;
name ids (`run.py 3 4`) to run a subset. Each eval is one job in the shared
pool from `tests/lib/eval_runner.py`, which runs four jobs at once by default
and gives each its own `TMPDIR`; `--workers 1` serializes them. A job stages
its fixture with `stage.sh` into a fresh sandbox root outside the checkout,
micro-deploys the skill into a scratch home, runs one print-mode worker on the
default Cursor vendor (`agent -p`, model `auto`), and grades the clone with
`grade.sh`. Each eval leaves `response.txt`, `stderr.txt`, `timing.json`,
`grading.txt`, and a copy of its sandbox under
`tests/git_checkout/workspace/run-<ts>-<pid>/<id>/`, and the run closes with a
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
ends on, the upstream it tracks and the tip it points at, that `HEAD` stays a
symbolic ref, which local branches exist, whether the worktree was left as
found, and the uncommitted content eval 7 must keep. It compares against the
snapshots `stage.sh` takes under `<target>/.eval/` before the run. The
expectations that speak only about the response or about which helper ran
print as `response` lines; confirm those by reading `response.txt`.

The three phases also run by hand for debugging:

```bash
# 1. Stage one eval; prints shell-safe sandbox_repo, skill_path, prompt lines
eval "$(bash tests/git_checkout/evals/stage.sh <eval_id>)"

# 2. Have an agent load $skill_path and apply $prompt inside $sandbox_repo.

# 3. Grade the post-run repository
bash tests/git_checkout/evals/grade.sh <eval_id> "$sandbox_repo"
```

Skill-creator's `python -m scripts.run_eval` is a different tool: the
*trigger* evaluator for description optimization, which understands neither
this schema nor these fixtures.

## Schema

`evals.json` follows the skill-creator-style shape used across the Pattern A
harnesses in this repo:

```text
{ skill_name, evals: [ { id, prompt, expected_output, files, expectations[] } ] }
```

`files` names the fixture stager for that eval, relative to
`tests/git_checkout/`. `stage.sh` reads both the stager and the prompt from
this file, so `evals.json` stays the one source of each eval's inputs.

## The evals

| id | Fixture | What it exercises |
| --- | --- | --- |
| 1 | `remote_only_branch` | A branch that lives only on `origin` and was pushed after the clone's last fetch: fetch before resolving, create the local branch with an explicit upstream, report the created branch, its upstream, and the previous branch. |
| 2 | `already_local` | A branch this clone already has: switch to it, create nothing, report it as already present with no tracking branch created. |
| 3 | `two_remotes_same_name` | A bare name carried by two remotes: list both candidates, ask which remote to track, create nothing and switch nowhere. |
| 4 | `two_remotes_same_name` | The same fixture with the remote named in the prompt: track that remote's branch without asking, and stay on a named local branch. |
| 5 | `restricted_refspec` | A single-branch clone whose fetch refspec never maps the branch: name that cause, show the refspec, offer the widening remedy. |
| 6 | `remote_only_branch` | A name no remote advertises: report it as nonexistent, create nothing, and keep it distinct from the refspec case. |
| 7 | `dirty_conflict` | An uncommitted edit to a file the target branch rewrites: surface the blocking path, keep the change, run no stash. |

Evals 3 and 4 share one fixture as the hold and its re-entry. Eval 6 reuses the
eval 1 fixture with a branch name nothing carries, so the two miss causes are
graded against different repositories.

## Fixtures

`fixtures/_common.sh` holds the shared helpers. `seed_bare` creates a bare
repository with one commit so later clones never see an empty repository,
`init_remote_repo` stages a bare origin plus a clone of it, and
`push_branch_from_side` pushes a branch from a throwaway clone so the
repository under test has never fetched it. That last helper is what makes the
pre-resolution fetch load-bearing: without a fetch, the branch every fixture
targets is invisible.
