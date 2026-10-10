# git_commit skill evals (behavioral surface)

Behavioral evals for the git_commit skill. The mechanical surface
(bundled-script unit tests) lives next door in `script_tests/`.

This directory holds **eval definitions and tooling**. Eval *runs*
(staged sandboxes, post-run artifacts) go under
`tests/git_commit/workspace/` or any other dir you point `stage.sh`
at, which `tests/.gitignore` keeps out of git.

## Harness rule: skill-creator is read-only

The skill-creator skill, installed under
`~/.claude/plugins/cache/claude-plugins-official/skill-creator/<version>/skills/skill-creator/`,
is **read-only** for this harness. We never copy into it, overwrite
files inside it, or rely on patches to it. If a behavioral-eval need
arises that would otherwise require modifying the skill-creator skill,
solve it inside `tests/git_commit/` instead: extend `stage.sh`,
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
top-level RUNBOOK assumed otherwise. Both have been corrected.

The behavioral workflow described in skill-creator's own `SKILL.md`
("spawn with-skill and without-skill subagents per eval, capture
timing, run the grader, aggregate") is something a Claude **in a
session** orchestrates, not a CLI tool you can invoke directly.
The harness in this directory gives you the deterministic pieces of
that workflow (stage a fixture, grade the post-run sandbox) and
leaves the actual model-runs-the-skill step to be driven by whoever
is in the session.

## Layout

```text
tests/git_commit/evals/
├── README.md              # this file
├── evals.json             # canonical eval prompts + expectations
├── run.py                 # worker runner: stage → vendor worker → grade
├── stage.sh               # stage one fixture, return agent-ready inputs
├── grade.sh               # grade the post-run sandbox programmatically
└── fixtures/              # per-eval sandbox setup scripts
    ├── _common.sh
    ├── single_file/setup.sh
    ├── multi_file/setup.sh
    ├── mixed_state/setup.sh
    ├── large_changeset/setup.sh
    ├── script_failure/setup.sh     # stubbed prepare script, overlaid by run.py
    ├── concurrent_drift/setup.sh   # foreign drift — marker-gated writer, expects a pause
    ├── ambiguous_drift/setup.sh    # same-path drift — marker-gated writer, expects commit-all
    ├── obligation_skip/setup.sh    # pre-flight relevance test — expects a stated skip
    └── obligation_run/setup.sh     # pre-flight relevance test — expects the gate to run
```

## One-shot run (the default)

`run.py` drives all three phases for you, with one vendor-resolved worker
per eval. By default that is the Cursor worker (`agent -p` on model
`auto`), the project's measurement vendor. `--vendor claude` runs the
Claude worker (`claude -p` on the latest `sonnet` alias) where an eval
needs a Claude-specific feature or the operator asks for a Claude run, and
`--model` overrides either default (see `tests/CLAUDE.md`). On both
vendors the worker loads git_commit from the per-pass micro-deployment.
The deterministic `grade.sh` uses no model, and the prose-verdict
expectations stay for you to confirm by reading the captured
`response.txt`.

```bash
python3 tests/git_commit/evals/run.py                 # all evals (1..9), Cursor worker
python3 tests/git_commit/evals/run.py 2 5             # just evals 2 and 5
python3 tests/git_commit/evals/run.py 6 7             # just the drift-guard evals
python3 tests/git_commit/evals/run.py 8 9             # just the pre-flight relevance evals
python3 tests/git_commit/evals/run.py --vendor claude # Claude worker, where a test needs it
python3 tests/git_commit/evals/run.py --model ''      # inherit the CLI default instead
```

Evals 6 and 7 exercise the drift guard with a **marker-gated detached
writer** that stands in for a concurrent session editing the same tree
mid-run, with no real second agent. Each fixture stages a
`skill_under_test/` copy whose `prepare_commit_context.sh` touches
`.eval/baseline_captured` (outside the repo) after a successful real
prepare, and `run.py` copies that wrapper onto the micro-deployed skill
the worker loads. The writer polls the marker and only then writes. Eval 6
expects the skill to **pause** on the new outside-baseline file (no
commit lands); eval 7 expects **commit-all** on an ambiguous same-path
edit. Optional knobs: `GIT_COMMIT_DRIFT_MARKER_TIMEOUT` (default 240s)
and `GIT_COMMIT_DRIFT_POST_MARKER_DELAY` (default 0).

Evals 8 and 9 exercise `<prepare_worktree>`'s **relevance test** and are a
matched pair: each sandbox plants one agent-directed pre-commit obligation in
its own `AGENTS.md`, backed by a gate script that records having run by writing
its epoch second under `.eval/markers/`. Eval 8's gate governs the Python
package under `src/` while the commit changes `docs/handbook.md`, so the skill
must **skip** it and say why; eval 9's gate lints Markdown under `docs/` against
that same change, so the skill must **run** it before the commit lands. Run them
together, because eval 9 is eval 8's control, and a skip that came from ignoring
`AGENTS.md` altogether shows up as an eval 9 failure.

Per eval it writes `workspace/run-<ts>/<id>/{response.txt, stderr.txt,
timing.json, grading.txt}` and exits 0 only if every eval's grade
passed. The manual three-phase workflow below is what `run.py`
automates. Reach for it when debugging a single eval by hand.

## The manual workflow

Three phases. Phases 1 and 3 are deterministic shell. Phase 2 is the
agent running the skill against the staged sandbox.

### 1. Stage

```bash
eval "$(bash tests/git_commit/evals/stage.sh <eval_id> [target_dir])"
# eval_id: 1..9
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

`run.py` does this with the worker it resolved, the Cursor `agent -p`
worker by default or the Claude `claude -p` worker under
`--vendor claude`, pointed at the micro-deployed skill. When driving it by
hand instead, point the worker at `$skill_path`, `$sandbox_repo`, and
`$prompt`. A hand-driven run loads `$skill_path` directly rather than a
micro-deployment, so the skills deployed on your machine stay in the
worker's view. That makes it a debugging aid rather than a measurement:

- **Cursor `agent -p` (the `run.py` default).** Run `agent -p --force
  --sandbox disabled --workspace "$sandbox_repo" --model auto` from
  `$sandbox_repo` with a prompt that says to read and follow
  `$skill_path`.
- **Claude `claude -p` (`run.py --vendor claude`).** Run `claude -p
  --model sonnet --permission-mode bypassPermissions` from
  `$sandbox_repo` with the same prompt.
- **Subagent.** Launch a subagent from your agent session with a
  self-contained prompt pointing at `$skill_path`, `$sandbox_repo`, and
  `$prompt`.
- **In-session.** Tell the current agent session to read `$skill_path`
  and apply it to `$sandbox_repo`. Convenient for a quick look, but it
  runs on the inherited session model rather than a pinned vendor
  worker, so it's for debugging, not for a measurement run.

Whichever shape you use, the contract is: when this phase ends, the
agent has either left a new commit at HEAD of `$sandbox_repo` (good)
or left it untouched (the eval will FAIL grading).

### 3. Grade

```bash
bash tests/git_commit/evals/grade.sh <eval_id> "$sandbox_repo"
# Exit 0 if every programmatic check passed; 1 otherwise.
```

`grade.sh` prints PASS/FAIL per check. Some expectations cannot be
verified from filesystem state alone: "the skill did NOT use the
Write tool to create a commit-message file", "the skill consulted
references/manual_fallback.md after the non-zero exit". Those are
printed as `agent-attest` lines for the operator to confirm
manually from the agent's transcript.

## What `grade.sh` checks

| Check kind | Source of truth |
| --- | --- |
| New commit landed, HEAD^ is the staged baseline, working tree clean | `git rev-parse`, `git status` |
| Commit message shape (subject line, blank line 2, "file -> change" body lines) | `git log -1 --format=%B HEAD` |
| HEAD diff covers the expected file set | `git show --name-only HEAD` |
| No `git_commit_context.*` straggler in TMPDIR | `find $TMPDIR -newer <marker>` |
| Pre-flight gate ran or skipped an obligation | presence and epoch second of `.eval/markers/<gate>` |

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
- Eval 7: the skill did not pause on the ambiguous same-path edit. The
  commit-all tiebreaker swept `seed.txt`'s latest content in.
- Eval 8: the skill discovered the `AGENTS.md` obligation and stated the
  grounds for skipping it. The gate governs `src/` while the commit
  changes `docs/handbook.md`. (Deterministic half: the gate's marker is
  absent and the commit still landed.)
- Eval 9: the skill ran the obligation because the changed paths intersect
  the subject matter it governs. (Deterministic half: the marker exists and
  its epoch second is no later than the commit's.)

## Fixtures

Each fixture is a tiny shell script that stages a sandbox repo at
the path it's given. Run a fixture standalone for debugging:

```bash
bash tests/git_commit/evals/fixtures/single_file/setup.sh /tmp/sandbox-debug
```

Eval 5's fixture (`script_failure/setup.sh`) stages `repo/` and a
`skill_under_test/` copy of the git_commit plugin skill, then overwrites
`skill_under_test/scripts/prepare_commit_context.sh` with a failing stub.
The worker loads the micro-deployed git_commit, so `run.py` passes that
copy to `micro_deploy.overlay_fixture_edits()`, which copies every file the
copy adds or changes onto the deployed skill. The worker therefore meets
the stub at the deployed path, and `timing.json` lists the overlaid files
under `fixture_overlay`. An operator-driven run can still load
`skill_under_test/SKILL.md` directly. Only the git_commit plugin skill is
copied, so the "skill-creator is read-only" rule above still holds.

Evals 8 and 9 (`obligation_skip/`, `obligation_run/`) share the
`plant_obligation_scaffold` helper in `_common.sh`, which writes and commits
the sandbox's `AGENTS.md`, its `tools/<gate>.sh`, `docs/handbook.md`,
`src/app.py`, and a `.gitignore` covering `.eval/`. Committing the scaffold
leaves the fixture's own edit as the only dirty path, so the changed path set
the relevance test reads is unambiguous, and gitignoring `.eval/` keeps the
gate's marker out of both `git status` and the commit.

Evals 6 and 7 (`concurrent_drift/`, `ambiguous_drift/`) each stage a
`skill_under_test/` copy with prepare wrapped to touch
`.eval/baseline_captured`, then launch a **marker-gated detached writer**
(`nohup ... &`) before returning. `run.py` overlays the wrapper onto the
deployed skill the same way it overlays eval 5's stub. Running one
standalone spawns a process that writes into the sandbox only after you
invoke the wrapped prepare (or after the marker-wait timeout). Debug them
against a throwaway sandbox:

```bash
bash tests/git_commit/evals/fixtures/concurrent_drift/setup.sh /tmp/drift-debug
bash /tmp/drift-debug/skill_under_test/scripts/prepare_commit_context.sh
# writer fires on the marker; foreign file appears under repo/
sleep 1 && git -C /tmp/drift-debug/repo status --short --untracked-files=all
```

## Why under tests/ and not inside the skill

Skill-creator's default is `evals/` inside the skill directory. We
deviate on location only, keeping these under `tests/` because:

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
