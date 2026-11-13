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

## Which surface to run

Standing coverage lives in repo-root `TESTING.md` `## Coverage Expectations`
and the matching bullets in repo-root `AGENTS.md`. Short form for this
tree:

- **Default / "run the tests":** `make test`, which runs `tests/run_all.sh`
  over every harness's deterministic entrypoint (`script_tests/run.sh` or
  `run_all.sh`) and every `tests/lib/test_*` unit test, one pass/fail line per
  surface. Narrow to one harness with `bash tests/<skill>/run_all.sh` (or
  `bash tests/<skill>/script_tests/run.sh` where it has no `run_all.sh`). Do
  not start LLM-worker evals from that ask alone.
- **Behavioral evals:** only when Acceptance names them, when the change
  edits loop/relay/orchestration that scripts cannot pin and a named
  scenario buys the signal, or when the operator explicitly asks (including
  an optional full-suite measurement). Never treat a full existing-suite
  re-run as an ordinary task ship gate.
- **Incomplete eval** (timeout, empty response, kill): inconclusive; do not
  chase it inside the change as if it were a behavioral fail.

## Vendor switch

Every behavioral runner that spawns a worker shares `tests/lib/vendor.py`
and accepts:

```text
--vendor {claude,cursor}   # default: cursor; claude in the Claude-only harnesses
--model MODEL              # override worker model; '' inherits the CLI default
--effort LEVEL             # override Claude worker effort (low|medium|high|xhigh|max); '' omits --effort
--worker-bin PATH          # override binary; --claude-bin is a deprecated alias
--judge-model MODEL        # every harness that ships evals/judge.py, including natural_language; '' inherits
--judge-effort LEVEL       # override Claude judge effort beside --judge-model; '' omits --effort
```

Only Claude has an effort control, so an explicit `--effort` or
`--judge-effort` on Cursor stops the run with an error naming Claude.

| Role | `--vendor claude` | `--vendor cursor` |
| --- | --- | --- |
| Worker binary | `claude -p` | `agent -p` |
| Worker model | `opus` (latest alias, not a dated pin) at high effort (`--effort high`) | `auto`, no effort setting |
| Judge / meta LLM | `opus` at `xhigh` effort (`--effort xhigh`) | `auto`, no effort setting |
| Permissions | `--permission-mode bypassPermissions` | `--force --sandbox disabled` |
| Workspace | subprocess `cwd` | `--workspace <sandbox>` plus `cwd` |
| Second turn | `--session-id` on the first turn, `--resume` with the same id on later turns | no session flag on the first turn, `--resume` with the first stream's `session_id` on later turns |
| Staged agents | plugin roles in the scratch config directory's `agents/`, fixture agents in the sandbox project's `.claude/agents/` | both in the sandbox project's `.cursor/agents/` |
| Withheld tools | shell and write by `--disallowedTools`; spawn declared absent in the prompt | shell and write by deny entries in `proj/.cursor/cli.json`; spawn declared absent in the prompt |

At high effort a Claude eval runs for minutes: the 2026-11-13 measurements
recorded in `tests/agent_spinner/evals/README.md` ran from 182 to over 500
seconds per eval. An agent whose tool calls have a wall-clock limit therefore
runs few evals per call, and it reports an eval that outlasts one call as
inconclusive. A full Claude suite costs about one point of the five-hour usage
window per eval, so it spans more than one window. A run that pauses at the
operator's quota threshold resumes after the reset by re-running the same
command, which replays the verdicts already cached.

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
agent never runs Claude tests in the background. The parity rule in TESTING.md's
`## Running Tests` governs every harness: an eval runs and grades the same way
on Claude and Cursor, and a harness is vendor-specific only when it tests a
vendor-specific feature, which it names.

### Claude-only harnesses

These default to Claude and stop with a clear error on an explicit
`--vendor cursor` until a Cursor equivalent exists, so they run on Claude
wherever a change needs them, in the foreground, with `--vendor claude` in the
command:

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
`styles/`. Each pass also records `checkout_unread` beside that check: any
read, glob, or named path that resolves inside the repository checkout fails
the pass and lists the path under `inside_checkout`. Claude's stream carries a
helper's tool calls, but Cursor keeps them out of the parent's stream, so on
Cursor both checks also read the chat transcripts the CLI writes under the
scratch home. The checks expand shell paths against the worker's own
environment, so `~` is the scratch home on Cursor but the real home on Claude,
and they read each command left to right: a variable that an earlier statement
of the command assigns expands its later paths, and a relative path after the
command's own `cd` resolves against that directory. A prefix assignment such as
`HOME=<fake home> bash x.sh` stays with its own command, as the shell scopes
it. A vendor-layout path that keeps a variable the command never assigns fails
closed for the artefact check unless everything before that variable already
lies inside the deployment, where it stays in set as a fragment of a deployed
path. Text after that variable that carries a `..` segment climbs back out of
the deployment, so that fragment fails closed too. A `plugins/` or `styles/`
path behind such a variable stays unchecked for artefacts, because a sandbox
fixture tree can share its shape; a path that still carries an unexpanded
variable also stays unflagged for `checkout_unread`, because it cannot be
placed. Each run probes authentication once inside a micro-deployment
environment before its first pass.

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
python3 tests/trigger_evals/run.py --eval-set tests/trigger_evals/wiki.json \
  --skill wiki --baseline tests/trigger_evals/results/wiki/<prior-cursor-run>

# Claude (latest opus worker, opus at xhigh judge): an eval that needs a
# Claude-specific feature, or a suite the operator explicitly asks for
python3 tests/git_commit/evals/run.py --vendor claude
python3 tests/language_humanizer/evals/run.py --vendor claude
```

Pass `--force` to ignore the verdict cache; `--no-cache` to neither read nor
write it.

### Parallel workers

Isolated-sandbox evals that use `tests/lib/eval_runner` default to **4**
concurrent jobs (`tests/lib/vendor.py` `DEFAULT_PARALLEL_WORKERS`). Each job
gets its own `TMPDIR`. Pass `--workers 1` to serialize. A harness keeps a
sequential subset only when its jobs share a resource the helper cannot
isolate. Today those subsets are the `task_auto_check` serial nested-loop set
(`repair_to_ready`, `relay_by_path`, `stray_hunk_reverted`,
`guard_rebaseline_after_gate`, `interaction_scan_surfaces`,
`immediate_ready_citations_overturn`, `regroup_via_reviewer`,
`regroup_immediate_ready`, `regroup_same_paragraph_ready`,
`committed_rule_deletion_routed`, `last_call_ready_refuted`,
`regate_isolated`, `dryrun_gap_confirmed`), which runs one job at a time after the isolated pool,
`tests/task/evals/run.py`'s Approach serial nested-loop set
(`auto_check_boundary`, `fix_coherence_reconcile_escalated`,
`fix_coherence_reconcile_inline_staleness`), which also runs one id at a
time after the isolated pool. The rest of the
`task_auto_check` suite and the rest of the `task` hub suite use the default
4 workers. Raising the default past 4 mostly buys model contention and
timeouts, not faster wall-clock.

The Pattern A runners on `eval_runner` at `vendor.DEFAULT_PARALLEL_WORKERS`
are `tests/task_auto_check/evals/run.py`, `tests/task/evals/run.py`,
`tests/task_create/evals/run.py`, `tests/task_fix/evals/run.py`,
`tests/git_checkout/evals/run.py`,
`tests/git_refresh/evals/run.py`, `tests/git_commit/evals/run.py`,
`tests/git_review/evals/run.py`, `tests/guardrail_audit/evals/run.py`,
`tests/skill_doctor/evals/run.py`, `tests/agent_spinner/evals/run.py`, and
`tests/git_auto_review/evals/run.py`. `task_auto_check` runs its serial
nested-loop set, the list above, one job at a time after the isolated pool.
`tests/task/evals/run.py` runs its Approach serial nested-loop set
(`auto_check_boundary`, `fix_coherence_reconcile_escalated`,
`fix_coherence_reconcile_inline_staleness`) one id at a time after the
isolated pool. `git_auto_review` declares its own serial
nested-loop set (`honours_round_cap`, `ignores_orchestrator_round_cap`,
`delta_re_review_bounds_the_subject`, `empty_continue_reason_forces_stop`,
`retries_once_on_ledger_fail`, `stops_on_second_ledger_fail`,
`stops_on_self_written_code`, `retries_once_on_unmapped_hunk`,
`stops_on_second_unmapped_hunk`, `restores_stray_fixer_path`) and runs
those one job at a time after the isolated pool, so its multi-round nested-loop
stop evals never overlap one another or the pool; every other `git_auto_review`
eval stages its own sandbox root and runs in the pool. Every `git_checkout`,
`git_refresh`, and
`git_commit` eval stages its own sandbox root, so the whole suite runs in the
pool. `git_commit`'s worker and `grade.sh` both receive the job's `TMPDIR`, so
the grader's straggler scan reads only that job's context files. Every
`task_fix` eval stages its own sandbox root and its host `tasks/` guard
compares only the sandbox's fixture names, so the whole suite runs in the
pool. Every `skill_doctor` eval stages its own sandbox root and its checksum
manifest covers only that sandbox, so overlapping evals keep their verdicts
apart; its `stage.sh`, worker, and `grade.sh` all run under the job's
`TMPDIR`. Every `agent_spinner` eval stages its own sandbox root and its host
guard compares only the basenames that sandbox owns, so overlapping evals stay
attributable; its `stage.sh`, worker, and `grade.sh` all run under the job's
`TMPDIR`.

The helper runs a harness's before and after hooks around each job, one hook
call at a time, so two escape-guard snapshots never interleave. The hooks
share one lock, and that lock cannot tell which overlapping job changed a
shared tree. Each hook therefore receives its job's index, and a parallel
escape guard uses it to claim only the names that job owns, the way
`tests/lib/host_tasks_guard.sh` compares only the sandbox's fixture names.
Every runner passes the required `on_error` callback, so a job that raises
fills only its own result slot with the fault verdict that callback builds,
and the run still reaches its graded summary. A Ctrl-C keeps queued jobs from
starting and lets the running ones finish. Unit tests live in
`tests/lib/test_eval_runner.py` (run `python3 tests/lib/test_eval_runner.py`).

Runners that already default to `DEFAULT_PARALLEL_WORKERS` outside this
helper (private pools, not yet on `eval_runner`):

- `tests/wiki/layer2/run.py` — one outside-checkout sandbox root per pass;
  passes of the same scenario stay sequential.
- `tests/language_humanizer/evals/run.py` — one isolated sandbox root per pass.
- `tests/natural_language/evals/run.py` — one sandbox per pass.
- `tests/trigger_evals/run.py` — one fresh worker directory per query run,
  outside the checkout and any git repository.

Do not put this default in `TESTING.md`. That file is methodology.
Operator knobs live in this file and its twin guide, plus the runner
`--workers` default.

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

Pin the skill-under-test through `--vendor` defaults: the worker runs `opus`
at high effort on Claude and `auto` on Cursor. Keep graders model-free when
possible; when a judge LLM exists (every harness that ships `evals/judge.py`,
including `natural_language`), it runs `opus` at `xhigh` effort on Claude and
`auto` on Cursor. Do not pin a dated model id: Claude uses the latest `opus`
alias.

### Ambient git configuration: pin the output shape at suite entry

A script test that pins the shape of git output clears or overrides the inherited `GIT_CONFIG_PARAMETERS` variable, which carries `git -c` settings into child processes, and the inherited `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_*` / `GIT_CONFIG_VALUE_*` block for every git invocation it makes, because git resolves both ahead of any repository config. A `git config` setting in the test's own scratch repository is the fallback that keeps the same assertion true in a clean environment. `tests/git_review/script_tests/run.sh` is the reference: it clears both once at suite entry, keeps each quoted-path scenario's `git config core.quotepath true`, and s35 proves the pin by asserting the git-quoted non-ASCII path on the collector's evidence beside a deliberately bypassed call that exports the inverted value and prints the raw path. That proof holds when the suite runs with the inverted value exported; in a clean environment git's default already quotes, so the clear is unobservable there.

### Verdict cache, timeouts, isolation

Same rules as `tests/CLAUDE.md`: content-keyed cache under
`<evals>/.eval_cache/`, worker completion gates before trusting grade.sh,
and behavioural sandboxes that must not inherit host instructions. Every
behavioural runner takes its sandbox root from
`worker_isolation.create_sandbox_root`; a sandbox root's name carries only
the harness prefix, because a worker reads its working directory and an eval
id there leaks the expected behaviour. A new harness prefix must be added to
`ALLOWED_ISOLATION_PREFIXES` in `tests/lib/test_worker_isolation.py` in the
same change that introduces it. `isolation_args` stays with the runners that
pass it today. A stage that fails or names no sandbox stops the
eval before any worker starts, and `tests/lib/check_stage_guard.py` proves
that for each runner.

### Reading results

A `FAIL` with `worker rc=0` is a skill or grader disagreement. A non-zero
`worker_rc` / `claude_rc` (both keys are written) or a timeout note in
`stderr.txt` means the worker did not finish — do not treat a green
`grade.sh` on partial state as a pass.
