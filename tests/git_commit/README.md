# git_commit skill regression test harness

Two surfaces, each in its own directory under
`tests/git_commit/`:

| Surface | Where | What it tests | Runner |
| --- | --- | --- | --- |
| `script_tests/` | Bundled shell scripts (`prepare_commit_context.sh`, `commit_with_message.sh`) | Deterministic stdout / exit-code / git-state assertions on real working trees | `./tests/git_commit/run_all.sh` |
| `evals/` | Skill agent behavior given `SKILL.md` | Whether the agent runs the primary workflow correctly, composes a policy-conformant commit message, and obeys fallback discipline | local `stage.sh` + `grade.sh` around an in-session agent run — see `evals/README.md` |

The authored harness is committed; `tests/.gitignore` keeps run output out.
The Makefile's lint targets prune the same run-output subtrees, so lint
covers the committed harness and nothing else.

## Why two surfaces

The git_commit skill ships *prose policy* (commit-message format,
scope rules, fallback discipline) **and** *bundled scripts* (the two
shell programs). These can regress independently:

- A bug in `prepare_commit_context.sh`'s NUL-safe path parsing breaks
  the script's correctness, regardless of what the skill prose says.
  Caught by `script_tests/`.
- A drift in the SKILL.md prose can make the agent skip the primary
  workflow or compose a malformed commit message, even when the
  scripts are perfect. Caught by `evals/`.

`script_tests/` runs fast (~1 sec, no LLM cost) and catches the
mechanical regressions. `evals/` runs out-of-band via the
in-`tests/`-only harness (`stage.sh` + agent run + `grade.sh`) and
catches the behavioral regressions. Note: the installed skill-creator
skill is **read-only** for this harness — nothing in
`tests/git_commit/` copies into or modifies it. See
`evals/README.md` for the rule and the workflow.

## script_tests/ — bundled-script unit tests

`script_tests/run.sh` stages fresh temporary git repos under
`scratch/<id>/repo/`, runs one of the bundled scripts, and asserts on
stdout + exit code + git-state. Bash + git only — no LLM calls.

Eighteen scenarios cover:

`prepare_commit_context.sh` — clean tree, one untracked text file,
one modified tracked file, mixed staged/unstaged/untracked, binary
file, 50-file changeset with a wall-clock perf bound (proves the
numstat caching works), path containing space + tab (proves NUL-safe
parsing works), `--help`, unknown flag → exit 2, run outside any git
repo → non-zero.

`commit_with_message.sh` (v3.4.0 stdin contract) — staged change +
valid message via stdin, untracked file picked up by `git add -A`,
empty stdin → exit 1, whitespace-only stdin → exit 1, `--help` flag
prints usage, multi-line message body preserved verbatim, context
file cleaned up on successful commit, context file preserved on
commit failure.

Add a scenario by appending a body function and a `scenario` line at
the bottom of `script_tests/run.sh`.

## evals/ — behavioral evals

See `evals/README.md` for the workflow, the harness rule (skill-creator
is read-only), and the deliberate departure from the older
"skill-creator runs the evals via `scripts.run_eval`" framing (that
runner is the trigger evaluator for description optimization — it
does not execute behavioral evals; the older README claimed
otherwise and has been corrected).

Five evals, each with a fixture script that stages a sandbox git
repo:

| ID | Eval | What it proves |
| --- | --- | --- |
| 1 | single-file commit | Single-line `file -> change` format; bundled scripts both invoked |
| 2 | multi-file commit | Summary sentence + N `file -> change` lines |
| 3 | mixed staged/unstaged/untracked | Stages every untracked file; commits whole state; no scope confirmation prompt |
| 4 | 60-file changeset | Still uses the script — large changesets do NOT trigger panic-fallback (the rule hardened in skill 3.2.0) |
| 5 | simulated script failure | Fallback fires only on non-zero exit; agent consults `references/manual_fallback.md`; one commit still lands |

Eval definitions use the skill-creator-style schema documented in
`skill-creator/references/schemas.md` — `{id, prompt, expected_output,
files, expectations[]}`. Grading is split between a programmatic
`grade.sh` (filesystem state) and operator-driven agent-attest notes
(process-level expectations like "no Write tool used for the message").

## How to run

```bash
# Bundled-script unit tests (fast, deterministic, no LLM cost)
./tests/git_commit/run_all.sh

# Behavioral evals: three phases — stage, agent runs the skill,
# grade. See evals/README.md for the full recipe.
eval "$(bash tests/git_commit/evals/stage.sh <eval_id>)"
# … now have an agent run the skill at $skill_path against $sandbox_repo
# with the prompt $prompt …
bash tests/git_commit/evals/grade.sh <eval_id> "$sandbox_repo"
```

## File reference

```text
tests/git_commit/
├── README.md
├── RUNBOOK.md
├── run_all.sh                          # bundled-script unit tests entrypoint
├── results/
│   └── layer1.log                      # latest script_tests transcript
├── script_tests/
│   ├── run.sh                          # 16 deterministic scenarios
│   └── scratch/<id>/                   # transient per-scenario git repos
└── evals/                              # behavioral eval definitions + tooling
    ├── README.md                       # workflow + harness rule
    ├── evals.json                      # canonical schema
    ├── stage.sh                        # stage one fixture, print agent inputs
    ├── grade.sh                        # grade post-run sandbox programmatically
    └── fixtures/                       # per-eval sandbox setup scripts
        ├── _common.sh
        ├── single_file/setup.sh
        ├── multi_file/setup.sh
        ├── mixed_state/setup.sh
        ├── large_changeset/setup.sh
        └── script_failure/setup.sh   # self-contained — copies a stubbed skill
```

## Scope discipline

Don't expand this harness in the same session that ships a skill
change — land the skill change first with a tight new scenario for
it, run `./tests/git_commit/run_all.sh` to confirm no regression,
commit. Test growth lives in its own session per `CLAUDE.md`'s
versioning rule.
