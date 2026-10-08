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
--vendor {claude,cursor}   # default: claude
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

### Claude-only harnesses

These reject `--vendor cursor` with a clear message until a Cursor
equivalent exists:

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

Workers path-read the skill under test from a staged copy that sits outside
every graded tree: either under the eval's `artefacts/` directory beside the
sandbox, or inside an isolated sandbox root when the harness copies the skill
there, as `language_humanizer` does. A worker never path-reads the skill from a
graded tree or from its source in the repository. Named helper agents that
must be spawnable from the sandbox are copied only into
`<sandbox>/.{cursor,claude}/agents/`.

Path-read of `SKILL.md` and a mini project-dir deploy of skills and agents both
load under Cursor, but a deployed user-level skill of the same name can win
over a path-read copy. On 8 October 2026 a traced Cursor worker that was told
to read a staged copy read the deployed `~/.cursor/skills` copy instead.
Staging the copy as a project skill of the worker's workspace and naming its
path in the prompt made the worker read the staged copy, which is how
`language_humanizer` stages it, but with no path in the prompt a deployed copy
still won over the project copy. Harnesses
keep selective agent staging so git and tree-identity grades stay honest.

## Running under Cursor

```bash
# Script surfaces (no LLM)
bash tests/git_commit/run_all.sh
bash tests/task/run_all.sh
# …

# Behavioral evals on Cursor auto
python3 tests/git_commit/evals/run.py --vendor cursor
python3 tests/guardrail_audit/evals/run.py --vendor cursor --force
python3 tests/language_humanizer/evals/run.py --vendor cursor   # the recorded measurement

# Claude default (latest sonnet worker, inherited judge)
python3 tests/git_commit/evals/run.py
python3 tests/language_humanizer/evals/run.py   # judge inherits on Claude
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
