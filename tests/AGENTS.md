# AGENTS.md: running the local test harnesses

Operational guide for everything under `tests/` when the host is Cursor
Agent (or any agent that reads `AGENTS.md`). The authored harness is
committed, including this file; `tests/.gitignore` keeps every regenerated
subtree local. `tests/README.md` has the layout split. `tests/CLAUDE.md`
is the Claude Code twin of this file — keep the two in lockstep when the
operator policy changes, including the parallel-workers rule.

Per-harness design docs live in each subdirectory's `README.md` and
`RUNBOOK.md`. Use those for *what* the tests cover; use this file for
*how* to run them from a Cursor session and *how* to read the results.

## Vendor switch

Every behavioral runner that spawns a worker shares `tests/lib/vendor.py`
and accepts:

```text
--vendor {claude,cursor}   # default: cursor; claude in the Claude-only harnesses
--model MODEL              # override worker model; '' inherits the CLI default
--worker-bin PATH          # override binary; --claude-bin is a deprecated alias
--judge-model MODEL        # every harness that ships evals/judge.py, including natural_language; '' inherits
```

| Role | `--vendor claude` | `--vendor cursor` |
| --- | --- | --- |
| Worker binary | `claude -p` | `agent -p` |
| Worker model | `sonnet` (latest alias, not a dated pin) | `auto` |
| Judge / meta LLM | inherit (omit `--model`) | `auto` |
| Permissions | `--permission-mode bypassPermissions` | `--force --sandbox disabled` |
| Workspace | subprocess `cwd` | `--workspace <sandbox>` plus `cwd` |

Deterministic graders (`grade.sh`, `grade.py`, pure Python scoring) stay
model-free on both vendors.

Run every eval that needs no Claude-specific feature without `--vendor`: the
default is Cursor, the project's measurement vendor, because Cursor runs are
cheaper and faster, so develop and iterate on it and rely on its results
without a matching Claude run. A test that exercises a Claude-specific feature
names it and runs on Claude with `--vendor claude` in its command, which keeps
the Claude run visible and is also how a task's acceptance asks for such a
run. The flag goes on the Claude-only harnesses too, although they default to
Claude and stop with an error on an explicit `--vendor cursor`. Any other
Claude run, such as a whole suite on Claude as a compatibility sample, happens
only after the operator explicitly asks for one in the current session. An
agent never runs Claude tests in the background.

### Claude-only harnesses

These default to Claude and stop with a clear error on an explicit
`--vendor cursor` until a Cursor equivalent exists, so they run on Claude
wherever a change needs them, in the foreground, with `--vendor claude` in the
command:

- `trigger_evals/` — inspects Claude `Skill(...)` / stream-json load evidence
- `natural_language/` exercises Claude output-style selection through
  `outputStyle` in a sandbox `.claude/settings.json`.

### Auth

- **Claude:** nested `claude -p` needs a live CLI login (or
  `CLAUDE_CODE_OAUTH_TOKEN` / keychain `claude-headless-token`). See
  `tests/lib/vendor.py` / `worker_auth.py`.
- **Cursor:** run `agent login` in an interactive terminal once, then verify
  with `agent -p --model auto --force 'Reply with exactly: AUTO_OK'`.
  Backgrounded login scripts do not complete OAuth. `CURSOR_API_KEY` is the
  CI/headless alternative, not the preferred local path.

### Skill and agent loading

Workers load skills, agents, and styles only from the per-pass
micro-deployment in `tests/lib/micro_deploy.py`: the repository's deploy
script installs the declared artefacts into a scratch home (and the sandbox
project for types that load only at project scope), so the version under test
is what the worker sees and the user's deployed copies stay out of each
vendor's discovery. On Cursor the scratch home also holds login profiles that
put back the PATH the worker was launched with. Cursor runs shell commands
from a login-shell snapshot taken under that home, which would otherwise skip
the operator's own profile, and on macOS `bash` would then resolve to the
stock 3.2. Prompts that name a skill, agent, or style path take it from that
pass's path map. Each pass records
`artefacts_read_from_micro_deployment` with the paths the worker read, a
spawned helper's reads included, and a read of any skill, agent, or style file
outside the scratch home and sandbox project fails the pass, whether it is a
copy in the user's home or a source under the checkout's `plugins/` or
`styles/`. Claude's stream carries a helper's tool calls, but Cursor keeps them
out of the parent's stream, so on Cursor the check also reads the chat
transcripts the CLI writes under the scratch home. The check expands shell paths
against the worker's own environment, so `~` is the scratch home on Cursor but
the real home on Claude, and it reads each command left to right: a variable
that an earlier statement of the command assigns expands its later paths, and
a relative path after the command's own `cd` resolves against that directory.
A prefix assignment such as `HOME=<fake home> bash x.sh` stays with its own
command, as the shell scopes it. A vendor-layout path that
keeps a variable the command never assigns fails closed. A `plugins/` or
`styles/` path behind such a variable stays unchecked, because a sandbox
fixture tree can share its shape. Each run probes authentication once inside a
micro-deployment environment before its first pass.

Each runner declares the artefacts its workers may load once, as an
`ARTEFACTS` list or an `artefacts_for()` function. Those names feed the deploy
script's `--only` list and, in every runner with a verdict cache,
`source_roots_for()` through `micro_deploy.source_roots_for()`, so what a pass
deploys and what its cache key hashes stay one list. TESTING.md's
`## Test Design Principles` states the rule. When a change makes a skill reach
another skill, agent, or style, by name or through a path the prompt names,
add that name to the declaration of every runner whose evals load the skill,
in the same change. A missing name shows up only when the worker reads a copy
from outside the deployment, as that path under `out_of_set` in the pass's
`artefacts_read_from_micro_deployment` record; a worker that runs without the
artefact passes unnoticed. A declaration names only artefacts the deploy
script discovers, and `micro_deploy()` stops on any other name. A fixture
artefact, such as a fixture agent or `natural_language`'s marker style, stays
out of the declaration, and the runner writes it into the sandbox project
after the micro-deployment returns. A fixture that edits a declared skill,
such as `git_commit`'s stubbed prepare script, stages an edited copy of it.
The runner then passes that copy to `micro_deploy.overlay_fixture_edits()`,
which copies every file the copy adds or changes onto the deployed skill, so
the worker still loads the path from the path map.

## Running under Cursor

```bash
# Script surfaces (no LLM)
bash tests/git_commit/run_all.sh
bash tests/task/run_all.sh
# …

# Behavioral evals on the default vendor, Cursor auto (no --vendor)
python3 tests/git_commit/evals/run.py
python3 tests/guardrail_audit/evals/run.py --force
python3 tests/language_humanizer/evals/run.py   # the recorded measurement

# Claude (latest sonnet worker, inherited judge): an eval that needs a
# Claude-specific feature, or a suite the operator explicitly asks for
python3 tests/git_commit/evals/run.py --vendor claude
python3 tests/language_humanizer/evals/run.py --vendor claude   # judge inherits on Claude
```

Pass `--force` to ignore the verdict cache; `--no-cache` to neither read nor
write it.

### Parallel workers

Isolated-sandbox evals that use `tests/lib/eval_runner` default to **4**
concurrent jobs (`DEFAULT_PARALLEL_WORKERS` in `tests/lib/vendor.py`). Each
job gets its own `TMPDIR`. Pass `--workers 1` to serialize. A harness keeps
a sequential subset only when its jobs share a resource the helper cannot
isolate. Today those are the `task_auto_check` repair-class nested loops and
an escape guard that reads the whole host checkout, such as `agent_spinner`'s
`git status`.

The helper runs before and after hooks one call at a time, but it cannot tell
which overlapping job changed a shared tree. Each hook receives its job's
index, so a parallel escape guard claims only the names that job owns, as
`tests/lib/host_tasks_guard.sh` does. A job that raises fills only its own
result slot through the runner's required `on_error` callback, and a Ctrl-C
keeps queued jobs from starting. Run `python3 tests/lib/test_eval_runner.py`
for the helper's unit tests.

Runners that already default to `DEFAULT_PARALLEL_WORKERS` outside this
helper: wiki layer 2, `language_humanizer`, and `natural_language`. Pattern A
runners that stay sequential until sibling conversion tasks wire them onto
`eval_runner` (plus permanent isolation exceptions): `git_commit` (shared
TMPDIR), `git_review` (timeout), the `task_*` family (serial until their
parallel-worker tasks land; the host guard ignores unrelated live backlog
edits; `task_auto_check` also keeps its deep repair loops serial),
`agent_spinner` (unscoped host `git status`, until its guard compares only
the names each eval owns), and `guardrail_audit` / `skill_doctor`
until an isolation sweep proves them. Details stay in lockstep with
`tests/CLAUDE.md`.

### Subset runs

A named subset stages, grades, and reports only those ids. Skipped ids
are absent from the run dir; post-steps do not walk the full inventory
and warn. Same rule as `tests/CLAUDE.md`.

## What's here

See the inventory table in `tests/CLAUDE.md` (kept identical). Pattern A is
preferred for new harnesses; Pattern B stays only in `wiki/` until its next
significant iteration.

## Universal operator lessons

### Model policy

Pin the skill-under-test through `--vendor` defaults (`sonnet` / `auto`).
Keep graders model-free when possible; when a judge LLM exists
(every harness that ships `evals/judge.py`, including `natural_language`),
it inherits on Claude and uses `auto` on Cursor.
Do not pin dated model ids such as `claude-sonnet-4-6`.

### Verdict cache, timeouts, isolation

Same rules as `tests/CLAUDE.md`: content-keyed cache under
`<evals>/.eval_cache/`, worker completion gates before trusting grade.sh,
and sandboxes that must not inherit host instructions when the skill under
test is about prose or standing instructions. Those sandboxes come from
`tests/lib/worker_isolation.py`.

### Reading results

A `FAIL` with `worker rc=0` is a skill or grader disagreement. A non-zero
`worker_rc` / `claude_rc` (both keys are written) or a timeout note in
`stderr.txt` means the worker did not finish — do not treat a green
`grade.sh` on partial state as a pass.
