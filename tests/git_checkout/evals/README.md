# git_checkout skill evals (behavioral surface)

Behavioral evals for the `git_checkout` skill. The mechanical surface
(bundled-script unit tests) lives next door in `script_tests/`.

This directory holds **eval definitions and fixtures**. Eval *runs* go into
whatever directory you hand a fixture's `setup.sh`; keep those under
`tests/git_checkout/workspace/`, which `tests/.gitignore` keeps out of git.

## How these run

There is no CLI that executes a behavioral eval. The workflow skill-creator
describes ("spawn with-skill and without-skill subagents per eval, capture
timing, grade, aggregate") is something a Claude session orchestrates. This
directory supplies the deterministic pieces, a staged repository per eval and a
written expectation list, and leaves the model-runs-the-skill step to whoever is
in the session. Do not confuse this with skill-creator's
`python -m scripts.run_eval`, which is the *trigger* evaluator for description
optimization and understands neither this schema nor these fixtures.

One eval therefore runs like this:

```bash
bash tests/git_checkout/evals/fixtures/<name>/setup.sh /tmp/git-checkout-eval
```

Each `setup.sh` prints the path of the staged clone as its last line. Run the
`git_checkout` skill against that clone using the eval's `prompt`, then check
the repository state and the agent's response against the eval's
`expectations[]`.

## Schema

`evals.json` follows the skill-creator-style shape used across the Pattern A
harnesses in this repo:

```text
{ skill_name, evals: [ { id, prompt, expected_output, files, expectations[] } ] }
```

`files` names the fixture stager for that eval, relative to
`tests/git_checkout/`.

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
