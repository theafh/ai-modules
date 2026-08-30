# git_refresh skill regression test harness

Two surfaces live under `tests/git_refresh/`:

| Surface | Where | What it tests | Runner |
| --- | --- | --- | --- |
| `script_tests/` | Bundled shell script (`refresh_repo.sh`) | Deterministic stdout, exit-code, and git-state assertions on staged repositories | `./tests/git_refresh/run_all.sh` |
| `evals/` | Skill agent behavior given `SKILL.md` | Whether the agent invokes the helper, reports the default run, asks the gated follow-up only when candidates exist, and gates force-delete actions | Session-level skill-creator workflow |

The authored harness is committed; `tests/.gitignore` keeps run output out.

## script_tests

`script_tests/run.sh` stages fresh repositories under
`script_tests/scratch/<id>/`, runs the bundled helper, and checks the resulting
branch, commit, and worktree state.

Scenarios cover default-branch detection on `master`, fast-forward-only update,
diverged upstream handling, safe merged-branch deletion, preservation of
upstream-gone branches with unique commits during the default run, conditional
follow-up reporting, protected branch handling, dirty-worktree blocking, gated
upstream-gone pruning with `git branch -d`, and force-delete confirmation before
`git branch -D`.

## evals

`evals/evals.json` follows the skill-creator-style schema:
`{id, prompt, expected_output, files, expectations[]}`. Fixture scripts under
`evals/fixtures/` stage the repositories for agent-driven behavioral checks.

The deterministic script tests are the required local check for this harness.
Behavioral evals require an agent run between staging and grading, so this
harness keeps those definitions local and ready for an explicit eval session.
