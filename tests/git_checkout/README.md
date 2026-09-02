# git_checkout skill regression test harness

Two surfaces live under `tests/git_checkout/`:

| Surface | Where | What it tests | Runner |
| --- | --- | --- | --- |
| `script_tests/` | Bundled shell script (`checkout_branch.sh`) | Deterministic stdout, exit-code, and git-state assertions on staged repositories | `./tests/git_checkout/run_all.sh` |
| `evals/` | Skill agent behavior given `SKILL.md` | Whether the agent invokes the helper, reports the path it took, asks which remote to track instead of guessing, names the cause of a miss, and keeps a dirty worktree intact | Session-level skill-creator workflow |

The authored harness is committed; `tests/.gitignore` keeps run output out.

## script_tests

`script_tests/run.sh` stages fresh repositories under
`script_tests/scratch/<id>/`, runs the bundled helper, and checks the resulting
branch, upstream, refs, worktree, and report text. Every fixture pushes its
branches from a throwaway side clone, so the repository under test has never
fetched them and the run has to fetch before resolving.

The fourteen scenarios cover the remote-only checkout with an explicit
upstream, a branch pushed to a second remote after the clone's last fetch, a
stale remote-tracking ref surviving a successful checkout in a repository with
`fetch.prune = true`, the already-local switch, the multi-remote ambiguity hold
with its candidate list, the remote-qualified re-entry after that hold, a
remote-qualified argument selecting its remote without asking, a
remote-qualified miss that does not fall through to another remote carrying the
name, both miss causes (a restricted fetch refspec and a branch that exists
nowhere), both dirty-worktree branches (a conflicting change that blocks the
switch and a compatible change that carries across), a slashed branch name that
is not read as a remote-qualified argument, and argument handling.

Exit codes carry the outcome, so the scenarios assert them directly: `0` for a
completed switch, `3` for the ambiguity hold, `4` for a reported miss, `5` for a
switch git refused, and `1` for a usage error.

## evals

`evals/evals.json` follows the skill-creator-style schema:
`{id, prompt, expected_output, files, expectations[]}`. Fixture scripts under
`evals/fixtures/` stage the repositories for agent-driven behavioral checks, and
`evals/fixtures/_common.sh` holds the shared seeding helpers.

The seven evals cover the remote-only checkout with its fetch, the already-local
case, the bare-name ambiguity hold, the remote-qualified argument, the
restricted-refspec cause report, the nonexistent-branch cause report, and the
conflicting dirty worktree. Evals 3 and 4 share the `two_remotes_same_name`
fixture as the hold and its re-entry; eval 6 reuses the `remote_only_branch`
fixture with a name no remote carries.

The deterministic script tests are the required local check for this harness.
Behavioral evals require an agent run between staging and grading, so this
harness keeps those definitions local and ready for an explicit eval session.
