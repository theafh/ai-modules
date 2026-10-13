# git_commit skill regression test harness

Two surfaces, each in its own directory under
`tests/git_commit/`:

| Surface | Where | What it tests | Runner |
| --- | --- | --- | --- |
| `script_tests/` | Bundled shell scripts (`prepare_commit_context.sh`, `commit_with_message.sh`) | Deterministic stdout / exit-code / git-state assertions on real working trees | `./tests/git_commit/run_all.sh` |
| `evals/` | Skill agent behavior given `SKILL.md` | Whether the agent runs the primary workflow correctly, composes a policy-conformant commit message, and obeys fallback discipline | `python3 tests/git_commit/evals/run.py` (stage, Cursor worker by default, grade; see `evals/README.md`) |

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

`script_tests/` runs fast (~15 sec, no LLM cost) and catches the
mechanical regressions. `evals/` runs out-of-band through
`evals/run.py`, which stages each fixture, runs a vendor worker, and
grades the sandbox, and catches the behavioral regressions. Note: the installed skill-creator
skill is **read-only** for this harness. Nothing in
`tests/git_commit/` copies into or modifies it. See
`evals/README.md` for the rule and the workflow.

## script_tests/: bundled-script unit tests

`script_tests/run.sh` stages a fresh temporary git repo per scenario
under `scratch/<id>/repo/`, runs one or both of the bundled scripts in
it, and asserts on stdout + exit code + git-state. Bash + git only, no
LLM calls.

Thirty scenarios cover:

`prepare_commit_context.sh`: clean tree, one untracked text file,
one modified tracked file, mixed staged/unstaged/untracked, binary
file, 50-file changeset with a wall-clock perf bound (proves the
numstat caching works), path containing space + tab (proves NUL-safe
parsing works), `--help`, unknown flag → exit 2, run outside any git
repo → non-zero, and the three stdout lines (the context file's path,
its byte size, and a harness-neutral consumption directive).

`commit_with_message.sh` (v3.4.0 stdin contract): staged change +
valid message via stdin, untracked file picked up by `git add -A`,
empty stdin → exit 1, whitespace-only stdin → exit 1, `--help` flag
prints usage, multi-line message body preserved verbatim, context
file cleaned up on successful commit, context file preserved on
commit failure, a body-bearing message without a blank line 2 → exit
4, foreign drift outside the reviewed baseline → exit 3,
`--accept-drift` committing the drifted path anyway, pass-through when
nothing drifted or the same path was re-edited, and commit-all when
the baseline is missing because there is no context file or the
context file lacks the baseline block.

The bash 3.2 floor: four scenarios run through an explicit
`/bin/bash` rather than the bash the scripts' shebang resolves on
`PATH`, and each logs the first line of `/bin/bash --version` to
`results/layer1.log`. A modifications-only tree and a new-files-only
tree, which empty the staged and the unstaged diff list in turn, each
run the prepare script and then commit through
`commit_with_message.sh` with the printed context path. A copy of the
prepare script with an unbound-variable reference injected directly
after its EXIT trap exits non-zero with empty stdout. On a host whose
`/bin/bash` is 3.2, the same injection into the pre-fix stub
`prepare_commit_context_pre_fix_trap.sh` exits 0, which shows the
scenario detects the masked exit status. A copy with the reference
injected directly before the script's final statement also exits
non-zero, which pins the completion flag `_prepare_completed=1` as
that final statement.

Add a scenario by appending a body function and a `scenario` line at
the bottom of `script_tests/run.sh`.

## evals/: behavioral evals

See `evals/README.md` for the workflow, the harness rule (skill-creator
is read-only), and the deliberate departure from the older
"skill-creator runs the evals via `scripts.run_eval`" framing (that
runner is the trigger evaluator for description optimization and
does not execute behavioral evals; the older README claimed
otherwise and has been corrected).

Nine evals, each with a fixture script that stages a sandbox git
repo:

| ID | Eval | What it proves |
| --- | --- | --- |
| 1 | single-file commit | Single-line `file -> change` format; bundled scripts both invoked |
| 2 | multi-file commit | Subject line, blank line 2, then N `file -> change` body lines |
| 3 | mixed staged/unstaged/untracked | Stages every untracked file; commits whole state; no scope confirmation prompt |
| 4 | 60-file changeset | Still uses the script. Large changesets do NOT trigger panic-fallback (the rule hardened in skill 3.2.0) |
| 5 | simulated script failure | Fallback fires only on non-zero exit; agent consults `references/manual_fallback.md`; one commit still lands |
| 6 | concurrent foreign drift | A new file another session drops after the baseline is caught at the commit-time re-check; the agent pauses and asks, and no commit lands |
| 7 | ambiguous same-path drift | A concurrent re-edit of a path already in the baseline adds no new path, so the agent commits everything with no pause and drops no file |
| 8 | pre-flight obligation skipped | A standing pre-commit gate over code the commit does not touch is skipped with its grounds stated, and the commit still lands |
| 9 | pre-flight obligation run | Eval 8's control: the gate governs the changed docs, so it runs before the commit lands |

Eval definitions use the skill-creator-style schema documented in
`skill-creator/references/schemas.md`: `{id, prompt, expected_output,
files, expectations[]}`. Grading is split between a programmatic
`grade.sh` (filesystem state) and operator-driven agent-attest notes
(process-level expectations like "no Write tool used for the message").

## How to run

```bash
# Bundled-script unit tests (fast, deterministic, no LLM cost)
./tests/git_commit/run_all.sh

# Behavioral evals: run.py stages each fixture, runs a Cursor worker by
# default, and grades the result. See evals/README.md for its options.
python3 tests/git_commit/evals/run.py

# The same three phases by hand: stage, an agent runs the skill, grade.
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
│   ├── run.sh                          # 30 deterministic scenarios
│   ├── prepare_commit_context_pre_fix_trap.sh  # pre-fix EXIT-trap stub
│   └── scratch/<id>/                   # transient per-scenario git repos
└── evals/                              # behavioral eval definitions + tooling
    ├── README.md                       # workflow + harness rule
    ├── evals.json                      # canonical schema
    ├── run.py                          # worker runner: stage, vendor worker, grade
    ├── stage.sh                        # stage one fixture, print agent inputs
    ├── grade.sh                        # grade post-run sandbox programmatically
    └── fixtures/                       # per-eval sandbox setup scripts
        ├── _common.sh
        ├── single_file/setup.sh
        ├── multi_file/setup.sh
        ├── mixed_state/setup.sh
        ├── large_changeset/setup.sh
        ├── script_failure/setup.sh   # stubbed prepare script, overlaid by run.py
        ├── concurrent_drift/setup.sh # foreign drift, expects a pause
        ├── ambiguous_drift/setup.sh  # same-path drift, expects commit-all
        ├── obligation_skip/setup.sh  # pre-flight gate skipped with grounds
        └── obligation_run/setup.sh   # pre-flight gate runs
```

## Scope discipline

A skill change lands with the tight scenarios that prove its own new
behaviour, and `./tests/git_commit/run_all.sh` runs before the commit
to confirm no regression. Only unbounded harness growth, such as
backfilling coverage of behaviour that shipped earlier, belongs in its
own session. `TESTING.md`'s `## Coverage Expectations` is the standing
rule this follows.
