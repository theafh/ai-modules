# git_commit skill evals (behavioral surface)

Behavioral evals for the git_commit skill. The mechanical surface
(bundled-script unit tests) lives next door in `script_tests/`.

This directory holds **eval definitions and tooling**. Eval *runs*
(staged sandboxes, post-run artifacts) go under
`tests/git_commit/workspace/` or any other dir you point `stage.sh`
at, which `tests/.gitignore` keeps out of git.

## Harness rule: skill-creator is read-only

The skill-creator skill — installed under
`~/.claude/plugins/cache/claude-plugins-official/skill-creator/.../skill-creator/`
— is **read-only** for this harness. We never copy into it, overwrite
files inside it, or rely on patches to it. If a behavioral-eval need
arises that would otherwise require modifying the skill-creator skill,
solve it inside `tests/git_commit/` instead — extend `stage.sh`,
extend `grade.sh`, add a per-fixture mechanism, or document an
in-session manual step. This keeps the harness portable across
machines where skill-creator may be at different versions or paths,
and it keeps the surface area of "things that can break the eval"
bounded to this directory.

## What `scripts.run_eval` actually does (not what an older README claimed)

`python -m scripts.run_eval` inside the skill-creator skill is the
**trigger evaluator** for description optimization. It consumes
`{query, should_trigger}` items and tests how often a Claude session
loads the skill in response. It does NOT spawn the model to execute
the skill against fixtures, has no `--workspace` argument, and does
not understand the `{id, prompt, expected_output, expectations}`
schema in `evals.json`. An older version of this README and the
top-level RUNBOOK assumed otherwise — both have been corrected.

The behavioral workflow described in skill-creator's own `SKILL.md`
("spawn with-skill and without-skill subagents per eval, capture
timing, run the grader, aggregate") is something a Claude **in a
session** orchestrates — it isn't a CLI tool you can invoke directly.
The harness in this directory gives you the deterministic pieces of
that workflow (stage a fixture, grade the post-run sandbox) and
leaves the actual model-runs-the-skill step to be driven by whoever
is in the session.

## Layout

```text
tests/git_commit/evals/
├── README.md              # this file
├── evals.json             # canonical eval prompts + expectations
├── run.py                 # sonnet worker-runner: stage → claude -p → grade
├── stage.sh               # stage one fixture, return agent-ready inputs
├── grade.sh               # grade the post-run sandbox programmatically
└── fixtures/              # per-eval sandbox setup scripts
    ├── _common.sh
    ├── single_file/setup.sh
    ├── multi_file/setup.sh
    ├── mixed_state/setup.sh
    ├── large_changeset/setup.sh
    ├── script_failure/setup.sh     # self-contained — copies a stubbed skill
    ├── concurrent_drift/setup.sh   # foreign drift — detached writer, expects a pause
    └── ambiguous_drift/setup.sh    # same-path drift — detached writer, expects commit-all
```

## One-shot run (the default)

`run.py` drives all three phases for you and pins the skill under test
to **sonnet** — the worker model the repo's test policy standardizes on
(see `tests/CLAUDE.md`). The deterministic `grade.sh` it calls uses no
model; the prose-verdict expectations stay for you to confirm from the
captured `response.txt` on the inherited session model.

```bash
python3 tests/git_commit/evals/run.py            # all evals (1..7)
python3 tests/git_commit/evals/run.py 2 5        # just evals 2 and 5
python3 tests/git_commit/evals/run.py 6 7        # just the drift-guard evals
python3 tests/git_commit/evals/run.py --model '' # inherit the CLI default instead
```

Evals 6 and 7 exercise the drift guard with a **detached, delayed writer**
that stands in for a concurrent session editing the same tree mid-run — no
real second agent. They are timing-based: the writer's fixed delay
(`GIT_COMMIT_DRIFT_DELAY`, default 20s) must land its write after the agent
runs `prepare_commit_context.sh` but before its commit-time drift re-check.
Eval 6 expects the skill to **pause** on the new outside-baseline file (no
commit lands); eval 7 expects **commit-all** on an ambiguous same-path edit.
If eval 6 shows the agent committed instead of pausing, the write likely fell
outside that window — retry or tune `GIT_COMMIT_DRIFT_DELAY`.

Per eval it writes `workspace/run-<ts>/<id>/{response.txt, stderr.txt,
timing.json, grading.txt}` and exits 0 only if every eval's grade
passed. The manual three-phase workflow below is what `run.py`
automates — reach for it when debugging a single eval by hand.

## The manual workflow

Three phases. Phases 1 and 3 are deterministic shell. Phase 2 is the
agent running the skill against the staged sandbox.

### 1. Stage

```bash
eval "$(bash tests/git_commit/evals/stage.sh <eval_id> [target_dir])"
# eval_id: 1..7
# target_dir: optional; if omitted, mktemp -d is used
#
# After eval, three shell variables are set:
#   $sandbox_repo  absolute path of the git repo the skill should commit in
#   $skill_path    absolute path of the SKILL.md the agent should load
#   $prompt        the user prompt to give the agent
```

The marker file `<target_dir>/.eval_started_at` is also written; it
records the staged HEAD SHA so `grade.sh` can verify exactly one new
commit landed.

### 2. Run the skill against the sandbox (agent step)

`run.py` does this by spawning a sonnet `claude -p` worker (the policy
default). When driving it by hand instead, point the worker at
`$skill_path`, `$sandbox_repo`, and `$prompt`:

- **`claude -p` (matches `run.py`).** Run `claude -p --model
  claude-sonnet-4-6 --permission-mode bypassPermissions` from
  `$sandbox_repo` with a prompt that says to read and follow
  `$skill_path`. Reproducible and on the pinned worker model.
- **Subagent.** Launch a `claude` Agent with a self-contained prompt
  pointing at `$skill_path`, `$sandbox_repo`, and `$prompt`.
- **In-session.** Tell the current Claude session to read `$skill_path`
  and apply it to `$sandbox_repo`. Convenient for a quick look, but it
  runs on the inherited session model — not the pinned sonnet worker —
  so it's for debugging, not for a measurement run.

Whichever shape you use, the contract is: when this phase ends, the
agent has either left a new commit at HEAD of `$sandbox_repo` (good)
or left it untouched (the eval will FAIL grading).

### 3. Grade

```bash
bash tests/git_commit/evals/grade.sh <eval_id> "$sandbox_repo"
# Exit 0 if every programmatic check passed; 1 otherwise.
```

`grade.sh` prints PASS/FAIL per check. Some expectations cannot be
verified from filesystem state alone — "the skill did NOT use the
Write tool to create a commit-message file", "the skill consulted
references/manual_fallback.md after the non-zero exit". Those are
printed as `agent-attest` lines for the operator to confirm
manually from the agent's transcript.

## What `grade.sh` checks

| Check kind | Source of truth |
| --- | --- |
| New commit landed, HEAD^ is the staged baseline, working tree clean | `git rev-parse`, `git status` |
| Commit message shape ("file -> change" lines, summary sentence) | `git log -1 --format=%B HEAD` |
| HEAD diff covers the expected file set | `git show --name-only HEAD` |
| No `git_commit_context.*` straggler in TMPDIR | `find $TMPDIR -newer <marker>` |

And these are marked `agent-attest` (not auto-checked):

- The skill did NOT use the `Write` tool to create an intermediate
  commit-message file. The v3.4.0 stdin contract pipes the message
  directly into `commit_with_message.sh`.
- Eval 3: the skill did NOT pause for scope confirmation about the
  dirty tree or pre-existing staged changes.
- Eval 4: the skill did NOT fall back to the manual workflow just
  because the changeset is large.
- Eval 5: the skill saw the non-zero exit, consulted
  `references/manual_fallback.md`, and returned to the primary
  workflow for the commit step.
- Eval 6: the skill surfaced the outside-baseline file
  (`concurrent_reorg.txt`) and paused to ask, rather than sweeping it
  into the commit. (Deterministic half: no new commit landed and the
  file is present-but-uncommitted.)
- Eval 7: the skill did not pause on the ambiguous same-path edit — the
  commit-all tiebreaker swept `seed.txt`'s latest content in.

## Fixtures

Each fixture is a tiny shell script that stages a sandbox repo at
the path it's given. Run a fixture standalone for debugging:

```bash
bash tests/git_commit/evals/fixtures/single_file/setup.sh /tmp/sandbox-debug
```

Eval 5's fixture (`script_failure/setup.sh`) is self-contained: it
stages `repo/` and a `skill_under_test/` copy of the git_commit
plugin skill, overwrites `skill_under_test/scripts/prepare_commit_context.sh`
with a failing stub, and lets the agent load the stubbed skill
naturally. No runner-side wiring is required, which is what the
"skill-creator is read-only" rule above demands.

Evals 6 and 7 (`concurrent_drift/`, `ambiguous_drift/`) each launch a
**detached background writer** (`nohup ... &`) before returning, so running
one standalone spawns a process that writes into the sandbox after the delay
(`GIT_COMMIT_DRIFT_DELAY`, default 20s). Debug them against a throwaway
sandbox and expect the drift file to appear a few seconds later:

```bash
GIT_COMMIT_DRIFT_DELAY=3 \
  bash tests/git_commit/evals/fixtures/concurrent_drift/setup.sh /tmp/drift-debug
sleep 4 && git -C /tmp/drift-debug status --short --untracked-files=all
```

## Why under tests/ and not inside the skill

Skill-creator's default is `evals/` inside the skill directory. We
deviate on location only — keeping these under `tests/` because:

1. The repo's deploy pipeline (`make deploy`) copies the skill into
   vendor config dirs. Holding the evals outside the skill directory
   keeps them out of every deployed installation, which needs the skill
   itself but none of its test inputs. Their being committed does not
   change this: `make deploy` copies the skill directory, not `tests/`.
2. The repo keeps one harness tree under `tests/`; mixing a skill's
   evals into its own directory would split that pattern.

The eval schema (`{id, prompt, expected_output, files, expectations[]}`)
matches the skill-creator convention. Only the on-disk path differs,
and the runner is locally-grown rather than skill-creator-provided.
