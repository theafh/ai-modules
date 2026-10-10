# CLAUDE.md: running the local test harnesses

Operational guide for everything under `tests/`. The authored harness
is committed, including this file; `tests/.gitignore` keeps every
regenerated subtree local. `tests/README.md` has the split and the
matching `make lint` prunes.

Per-harness design docs live in each subdirectory's `README.md` and
`RUNBOOK.md`. Use those for *what* the tests cover; use this file for
*how* to run them correctly from inside a Claude Code session and
*how* to read the results without misleading yourself.

## What's here

| Subdir | Skill | Pattern | What it covers |
| --- | --- | --- | --- |
| `wiki/` | `wiki` | Pattern B (legacy two-layer) | Layer 1 deterministic script unit tests + Layer 2 LLM skill-behavior evals via custom orchestrator. |
| `git_commit/` | `git_commit` | Pattern A (skill-creator-aligned) | `script_tests/` bundled-script unit tests + `evals/` behavioral evals run operator-driven (stage → agent runs → grade). |
| `git_checkout/` | `git_checkout` | Pattern A (skill-creator-aligned) | `script_tests/` bundled-script unit tests over staged clones with real remotes (branch resolution, the no-prune fetch, the ambiguity hold, both miss causes, both dirty-worktree branches) + `evals/` behavioral evals run operator-driven (stage → agent runs → grade). |
| `git_review/` | `git_review` | Pattern A (skill-creator-aligned) | `script_tests/` bundled-script unit tests over staged clones with real remotes (the fetch-before-diff order, the two commit walks, base-side versions of deleted files, the test merge, the head-vs-upstream relationship behind the fast-forward decision, stub-`gh` thread and thread-comment pagination, the heading-range helper, and the size-profile line counts) + `evals/` behavioral evals over 36 fixtures via `evals/run.py`. |
| `language_humanizer/` | `language_humanizer` | Pattern A (prose-only skill) | `run_all.sh` drives the static SKILL.md / registration contract in `script_tests/` and the grader unit tests in `evals/test_grade.py`; `evals/` runs 3 scenarios × fixed 5-pass denominator, each pass and judge call isolated through `tests/lib/worker_isolation.py` and recorded on the default Cursor worker, graded by deterministic `grade.py` (word counts, ledger items, prose shape) + refute-biased `judge.py`. |
| `natural_language/` | `natural-language` | Pattern A (behavioral only) | 2 scenarios × fixed 5-pass denominator; deterministic `grade.py` (word count, pronoun openings, list-or-colon series, em dash, canary/shadow-share first-use gloss, chat length) + refute-biased `judge.py` for four source relations and shape. |
| `task/` | `task` (family hub) | Pattern A (skill-creator-aligned) | `script_tests/run.sh` unit-tests the bundled `lint.py`, `discover_tasks.sh`, and `init_tasks.sh`; `script_tests/contract_run.sh` asserts the family contract across the hub, its siblings, and the family agents; `evals/test_run.py` checks that no eval grading the sandbox's whole `git status` declares an artefact the micro-deployment writes into the sandbox project; `evals/` holds a behavioral eval per family member. `run_all.sh` drives the two script runners and `evals/test_run.py`. |
| `task_create/` | `task_create` | Pattern A (behavioral only) | Three staged evals over the base **Decide or label** rule as the create path applies it; the bundled scripts it drives are covered under `task/script_tests/`. |
| `task_fix/` | `task_fix` | Pattern A (behavioral only) | Four staged evals over the base `<lint>` **Repeated-link react protocol**: regroup the live account and leave the archived body quiet, gather a reference page's current state and its edit into one passage, surface a gathering that would leave an Acceptance item nothing to measure, and name a repeat inside one paragraph again in plain text there. Grades the task file's bytes and the run's per-finding disposition line. |
| `task_auto_check/` | `task_auto_check` | Pattern A (skill-creator-aligned) | `script_tests/` static contract checks + `evals/` over the autonomous readiness loop (repair-to-ready, gate/verifier/drift stops, mechanical lint cleanup). |
| `guardrail_audit/` | `guardrail_audit` | Pattern A (prose-only skill) | `script_tests/` static SKILL.md and registration contract + `evals/` over five staged fixtures with byte-identity grading. |
| `skill_doctor/` | `skill_doctor` | Pattern A (skill-creator-aligned) | `script_tests/` over `resolve_scope.py` and `discovery_safety.py` plus the static contract + `evals/` over three staged fixtures. |
| `agent_spinner/` | `agent_spinner` | Pattern A (prose-only skill) | `script_tests/` static SKILL.md / references / grep / registration contract + `evals/` over 21 staged fixtures, one per independently staged behavioural acceptance item. The runner denies the spawn tool for no-delegation-surface fixtures and brackets each eval with a host-checkout `git status`. |
| `git_refresh/` | `git_refresh` | Pattern A (script surface automated) | `script_tests/` over the bundled `refresh_repo.sh` on staged repositories. `evals/` holds four behavioral evals with fixtures but ships no runner, so a sweep does not reach them. |
| `ai_instruction_writing/` | `ai_instruction_writing` | Pattern A (script-only) | `script_tests/` asserts the static prose contract of a skill that ships no bundled scripts. |
| `charter_guardrail/` | `guardrail` | Pattern A (script-only) | `script_tests/` exercises the `charter_guardrail.sh` hook that protects `CHARTER.md`: its block and allow decisions for Claude, Codex, and Antigravity tool calls and for shell commands that read or write the charter, the `guardrail/charter-*` branch exception, and its behavior without `jq`. It also checks the hook registrations, the Codex deploy wiring, and how the docs and wiki describe Codex plugin-hook trust; no `run_all.sh`, so drive `script_tests/run.sh` directly. |
| `format_rust/` | `format_rust` | Pattern A (script-only) | `script_tests/` greps SKILL.md and the plugin README for the error-versus-invariant model, panic discipline, and clippy wiring; no `run_all.sh`. |
| `update_changelog/` | `update_changelog` | Pattern A (script-only) | `script_tests/` covers the deterministic parts of the incremental day-grouping walk. |
| `deployment/` | the deploy script (no single skill) | Pattern A (script-only) | These script tests execute the real deploy script, so they inherit its `jq`, `perl`, and `rsync` PATH gate. `script_tests/run.sh` covers the OpenCode, Antigravity, and bytecode-exclusion deployment paths, the socket and FIFO backup copy, openrsync vanished-file versus permission exit 23, the startup gate, and cleanup-only `--clear-backups` skipping that gate; `script_tests/style_run.sh` covers output-style deployment and uninstall. |
| `trigger_evals/` | wiki and `task_*` family skills | local `run.py` wrapper (deployed mode; `--force-uuid` for UUID proxy) | Whether a skill *triggers* on realistic user messages (description-matching), separate from skill *behavior*. |

Pattern A is preferred for new harnesses. Pattern B stays in `wiki/`
until the next significant iteration; don't bring up new harnesses
under Pattern B.

## Universal operator lessons

These are the things that bit me in practice. They apply to every
harness here regardless of pattern.

### Model policy: `--vendor` selects the worker; graders stay inherited or model-free

Every harness that runs a skill as a subprocess goes through
`tests/lib/vendor.py`. Run every eval that needs no Claude-specific feature
without `--vendor`: the default is Cursor, the project's measurement vendor,
because Cursor runs are cheaper and faster, so develop and iterate on it and
rely on its results without a matching Claude run. A test that exercises a
Claude-specific feature names it and runs on Claude with `--vendor claude` in
its command, which keeps the Claude run visible and is also how a task's
acceptance asks for such a run. The flag goes on the Claude-only harnesses
too, although they default to Claude and stop with an error on an explicit
`--vendor cursor`. Any other Claude run, such as a whole suite on Claude as a
compatibility sample, happens only after the operator explicitly asks for one
in the current session. An agent never runs Claude tests in the background.
Do not pin dated ids such as `claude-sonnet-4-6` — Claude uses the latest
`sonnet` alias; Cursor uses `auto`.

| Role | `--vendor claude` | `--vendor cursor` |
| --- | --- | --- |
| Worker binary | `claude -p` | `agent -p` |
| Worker model | `sonnet` (latest alias) | `auto` |
| Judge / meta LLM | inherit (omit `--model`) | `auto` |
| Deterministic graders | model-free | model-free |

`--model` / `--judge-model` override the vendor default; `--model ''`
inherits the CLI default. `--worker-bin` overrides the binary;
`--claude-bin` remains a deprecated alias. Claude-only surfaces
(`trigger_evals/`, `natural_language/`) default to Claude and reject an
explicit `--vendor cursor` until a Cursor equivalent exists, so they run on
Claude wherever a change needs them, in the foreground, with `--vendor claude`
in the command.

The Cursor twin of this file is `tests/AGENTS.md` — keep the vendor
table, the Claude-only list, and the parallel-workers rule in lockstep
when either changes.

The behavioral eval runners automate the old operator-driven Phase 2:
instead of running the skill yourself in-session, let the runner spawn
the vendor worker, then read `response.txt` for the prose-verdict
expectations `grade.sh` can't check. Workers load skills, agents, and styles
only from the per-pass micro-deployment in `tests/lib/micro_deploy.py`: the
repository's deploy script installs the declared artefacts into a scratch home
(and the sandbox project for types that load only at project scope), so the
version under test is what the worker sees and the user's deployed copies stay
out of each vendor's discovery. On Cursor the scratch home also holds login
profiles that put back the PATH the worker was launched with. Cursor runs
shell commands from a login-shell snapshot taken under that home, which would
otherwise skip the operator's own profile, and on macOS `bash` would then
resolve to the stock 3.2. Prompts that name a skill, agent, or style path
take it from that pass's path map. Each pass records
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

### Parallel workers: default 4 only where each job has its own sandbox

Isolated-sandbox evals that use `tests/lib/eval_runner` default to **4**
concurrent jobs (`tests/lib/vendor.py` `DEFAULT_PARALLEL_WORKERS`). Each job
gets its own `TMPDIR`. Pass `--workers 1` to serialize. A harness keeps a
sequential subset only when its jobs share a resource the helper cannot
isolate. Today those are the `task_auto_check` repair-class nested loops and
an escape guard that reads the whole host checkout, such as `agent_spinner`'s
`git status`. Raising the default past 4 mostly buys model contention and
timeouts, not faster wall-clock.

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

- `tests/wiki/layer2/run.py` — one sandbox directory per scenario; passes
  of the same scenario stay sequential.
- `tests/language_humanizer/evals/run.py` — one isolated sandbox root per pass.
- `tests/natural_language/evals/run.py` — one sandbox per pass.

Pattern A runners that stay sequential until their sibling conversion tasks
wire them onto `eval_runner` (plus permanent isolation exceptions):

- `git_commit` — `grade.sh` scans a shared `TMPDIR` for stragglers until the
  per-job `TMPDIR` conversion lands.
- `git_review` — two workers contend for the model past the per-eval timeout.
- `task`, `task_create`, `task_fix`, `task_auto_check` — still serial until
  their parallel-worker tasks land. The host guard compares an isolated temp
  copy and only the sandbox's fixture names, so an unrelated live backlog edit
  no longer fails them. `task_auto_check` also keeps its deep repair loops
  serial (a resource the helper cannot isolate).
- `agent_spinner` brackets each eval with a host-checkout `git status`, which
  sees every overlapping eval's changes, so it stays serial until its guard
  compares only the names each eval owns.
- `guardrail_audit`, `skill_doctor` — still serial; no isolation sweep
  has proven concurrent evals yet.

Do not put this default in `TESTING.md`. That file is methodology.
Operator knobs live in this file, `tests/AGENTS.md`, and the runner
`--workers` default.

### Subset runs: skipped ids are not visited

A run that names a subset (`--scenario`, positional eval ids) stages,
grades, and reports only those ids. A skipped id is absent from the run
dir. Graders, normalizers, and aggregators walk the run dir and look up
definitions by id. They do not iterate the full inventory and warn,
restage, or skip the rest. Pattern A runners already take this shape
(`ids` nargs). Wiki layer 2 matches it.

### Verdict cache: skip re-running an eval whose inputs haven't changed

Every Pattern-A behavioral runner that imports the shared helper
`tests/lib/eval_cache.py` caches each eval's graded verdict and skips
re-spawning its worker when nothing that determines the verdict has changed.
Verdicts live per-harness in `<evals>/.eval_cache/` (gitignored as run output,
like `workspace/`).

The cache key is a content hash of these inputs: the sources of every
artefact the runner declares for the eval, under the declaration rule in the
model policy section above, the harness definition (the whole `evals/` dir:
evals.json, stage.sh, grade.sh, fixtures, run.py), the shared helpers that
decide every cached verdict, the worker model, the eval id, and the prompt.
Those helpers are `eval_cache.VERDICT_HELPERS`: `tests/lib/micro_deploy.py`
(the deployment and the read check), `tests/lib/vendor.py` (the worker command
and environment), and `tests/lib/host_tasks_guard.sh` (the host `tasks/`
guard), so an edit to one re-runs each cached eval once. A helper under
`tests/lib` that starts deciding verdicts joins that list in the same change,
the way a newly reached artefact joins a runner's declaration. For a
task-family eval the declaration names the loaded sibling, the base `task`
skill it reads through `<authority>`, and the
`auto_*_task` agents that the `auto_*` siblings and an escalated `task_fix`
spawn. It also names `task_check` for `task_auto_check` and `task_fix`,
because both reach the `auto_gate_task` agent that wraps it. For `task_fix`
it adds `task_auto_check` as well, because the escalated `auto_shaper_task`
may invoke it. For `git_review` the declaration names the `git_checkout` and
`git_commit` skills it hands work to, the `git_refresh` skill whose
default-branch detection it follows, and the `guardrail` skill whose authority
hierarchy it ranks findings by. For `agent_spinner` it names the
`harness_portability` skill that agent_spinner routes per-harness questions
to. Change any of those and the key moves,
so the cache misses and the eval re-runs. As long as the declaration names
everything the eval's worker may load and `VERDICT_HELPERS` names every shared
helper a verdict depends on, the cache never serves a stale pass, because a
hit means byte-identical inputs to a run already graded.
Over-inclusion (editing a section of the base `task` skill that a
`task_create` eval never reaches still invalidates that eval) only costs an
occasional extra run, the safe direction.

- **Default: on.** A hit prints `CACHED PASS/FAIL … skipped agent -p`, or
  `skipped claude -p` on a Claude run, and replays the stored verdict, writing `cached.json` plus a clearly-bannered
  `response.txt` into the run dir so its shape matches a fresh run.
- **`--force`:** re-run every eval and refresh the cache. Use it to resample
  the stochastic worker on unchanged inputs when you want a fresh draw.
- **`--no-cache`:** neither read nor write the cache.

This is the mechanical backstop for the base `task` skill's
verification-economy rule ("re-run only when the inputs changed"), applied to
the one surface where a needless re-run is dramatically expensive. It trades
LLM-sampling variance for cost; `--force` is the escape hatch when the
variance is what you want. Unit + plumbing tests live in
`tests/lib/test_eval_cache.py` (run `python3 tests/lib/test_eval_cache.py`).

### Host `tasks/` during a task-family run

Each task-family eval copies the host `tasks/` tree into its temp directory at
stage time (`tests/lib/host_tasks_guard.sh`). The isolation checks compare the
live tree to that copy only for basenames the sandbox itself contains. A
parallel `task_auto_check`, or any other edit of a live task the sandbox does
not name, stays outside the comparison. A fixture name that appears, moves, or
is newer than the eval marker in the live tree still fails the eval.

The `wiki/` harness's `real_home_wiki_absent` fail-safe still watches the
operator's wiki tree. Finish a wiki run before editing that tree.

### Cheap-first: probe an LLM-eval fixture before paying for the full loop

For any eval whose worker runs a deep, slow loop (currently the
`task_auto_check` repair loop, ~15 to 25 min per run, timeout-prone),
validate the fixture with the cheapest surface that reveals the same
verdict *before* running the loop. For a readiness-repair eval that means
running the gate skill (`task_check`) alone against the staged fixture: a
single `claude -p` reading that skill, ~1 to 3 min, reporting its verdict and
issue list. A fixture-design bug (an unintended second readiness gap, an
inaccurate premise) caught at the gate costs minutes; the same bug caught
via a full-loop timeout costs 15 to 25. And run these deep loops
**sequentially**: two in parallel contend for the model and both slow
past even an 1800s timeout. `task_auto_check/RUNBOOK.md` has the specifics
and the grade-check pitfall that goes with them.

### Worker auth: nested `claude -p` reads the stored OAuth login

A `claude -p` worker spawned from inside a Claude Code session (any
harness runner) does not inherit the host session's in-memory auth. The
session env carries `CLAUDECODE` plus `CLAUDE_CODE_SDK_HAS_OAUTH_REFRESH`
/ `CLAUDE_CODE_SDK_HAS_HOST_AUTH_REFRESH` (host-managed refresh that does
not reach grandchild processes), so a child that still sees `CLAUDECODE`
treats itself as nested and expects the parent's SDK-held auth.

**The fix, derived from a sibling skill-eval runner:** strip
`CLAUDECODE` from the worker env so the child is a plain CLI invocation.
It then reads the CLI's own stored OAuth credential (macOS keychain item
`Claude Code-credentials`) directly, and no separate token is needed
while that login is present and unexpired. Never pass `--bare`; it
forces `ANTHROPIC_API_KEY` / `apiKeyHelper` auth and 401s a subscription
login. The shared helper `tests/lib/vendor.py` does this
(`tests/lib/worker_auth.py` keeps Claude-only wrappers for older callers):
its `worker_env()` pops `CLAUDECODE` and the HAS_*_REFRESH flags, and its
`preflight_auth()` fails fast on a dead login with one live `claude -p`
probe (the remediation below) instead of 401-ing every eval. The behavioral
runners build every worker environment from `worker_env()` through the
per-pass micro-deployment, and each run probes once through
`micro_deploy.preflight_auth()`, which runs that check inside a scratch
micro-deployment environment, so a login the scratch configuration directory
cannot reach fails fast too. `language_humanizer` and `natural_language` also
keep the host-environment probe, because their judges run outside the
micro-deployment. `trigger_evals/run.py` uses `worker_env()` directly.

**Failure signature:** worker rc≠0 with
`API Error: 401 Invalid authentication credentials` in `response.txt`,
an expired or absent login, not a skill regression (check `timing.json`
before attributing). The CLI's keychain OAuth is not self-refreshing (a
known bug, anthropics/claude-code#31095, #50743): an expired accessToken
with no usable refreshToken 401s forever. `claude auth status` still
reports `loggedIn` past expiry, so trust the live probe, then re-auth
with `claude auth login` and re-run.

**Optional headless-token override**, for a machine with no interactive
login (e.g. cron). Mint a `claude setup-token` (interactive browser
OAuth; 1-year inference-only token) and park it in the keychain;
`worker_env()` picks it up and it wins over the stored login:

```bash
claude setup-token
security add-generic-password -a "$USER" -s claude-headless-token -w '<token>' -U
```

`CLAUDE_CODE_OAUTH_TOKEN` exported in the shell wins over both, in every
runner, since they all build their worker env from the shared
`worker_env()`.

### Worker isolation

`tests/lib/worker_isolation.py` is the single source of the isolation that
every runner importing it applies. Each worker and each judge stays free of
the host's standing-instruction files that its working directory and ancestor
walk would reach, because it runs under a fresh root outside the home
directory and any git repository.

Cursor is the preferred measurement vendor. The Claude branch of the helper
serves compatibility runs and Claude-only product surfaces such as
output-style loading. One Cursor source stays outside the helper: User Rules,
which Cursor keeps in its settings rather than in project files. Deployed
user-level skills are kept out of view by the per-pass micro-deployment rather
than by this helper (see the model policy above).

Runners that import the helper take their sandbox roots and their worker
arguments from it. The unit tests live in `tests/lib/test_worker_isolation.py`.

### Timed-out worker output: decode it through `tests/lib/worker_io.py`

A `claude -p` worker that overruns its deadline raises `TimeoutExpired`, and the
partial output that exception carries is **bytes** even though the runner passed
`text=True`, which governs only what a normal completion returns. The
runners append a `[TIMEOUT after Ns]` note to that output, so a raw
`(exc.stderr or "") + note` raises `TypeError: can't concat str to bytes`. That
error escapes both the per-eval function and `main()`, which used to abort the
whole run: no verdict for the timed-out eval, none for anything queued behind
it, and a traceback where the graded summary belongs. It bit hardest on the
runners most likely to time out, which are the ones driving the slowest loops.

Every runner now resolves both streams through `as_text()` from the shared
`tests/lib/worker_io.py`, which returns `""` for `None`, decodes `bytes` with
`errors="replace"` (the deadline can cut the stream mid multi-byte sequence),
and passes `str` through. A timed-out eval is then recorded like any other
failure (`claude_rc` of `-1`, a `stderr.txt` ending in the note, a failed
verdict), and the run continues to its graded summary. Unit tests live in
`tests/lib/test_worker_io.py` (run `python3 tests/lib/test_worker_io.py`).

Keep the decode in that one module rather than reintroducing a local copy.

### Running long jobs in the background: `Bash --run_in_background`, not `Monitor + tail -f`

**Right pattern** for a "wake me when this job is done" wait:

```text
Bash(
  command="<long-running-command> 2>&1",
  run_in_background=true,
  timeout=<expected_max_ms>,
)
```

`Bash --run_in_background` fires one completion notification when the
process exits. No polling, no lingering processes.

**Wrong pattern** for a completion wait:

```text
Monitor(command="tail -f <output-file> | grep ...")   # don't
```

`tail -f` never exits on its own. When the underlying job finishes,
the tail keeps the monitor armed against the static file until the
monitor's timeout. You then have to call `TaskStop` to clean it up.

`Monitor` is the right shape for *unbounded* per-occurrence streams
(log-tailing for ERROR lines indefinitely), not for completion waits.
For per-occurrence with a natural end, write a script that emits one
line per event and *exits* when done; don't lean on `tail -f`.

### Ground truth lives in files, not mid-stream events

When a harness spawns LLM subagents (Layer 2 in `wiki/`, the
behavioral evals in `git_commit/`), the host Claude Code instrumentation
may surface subprocess-level events into the parent session's
notification stream. These look like real test outcomes, e.g.

```text
[WU-2 pass-1] FAIL (524.0s)
```

But they are **not** in the orchestrator's stdout, are **not**
printed by any script in the harness, and are **not** the graded
verdict. They are subprocess-timing artifacts from the host's wrapper
around `claude -p`. A `FAIL (524s)` usually means the subprocess ran
close to its per-pass `--timeout`; the orchestrator may have retried
it, and the final graded state is what counts.

Always cross-check mid-stream impressions against the ground-truth
files the harness writes. If those agree on "clean run," the run was
clean, regardless of what flickered through the notification stream.

### The three ground-truth signals to check after any LLM-in-the-loop run

1. **Exit code** of the orchestrator process.
2. **The graded summary file** the harness writes (e.g.
   `grading_summary.json` for `wiki/`, `grade.sh` output for
   `git_commit/`, `results.json` for `trigger_evals/`).
3. **The regression compare** if the harness has one (e.g.
   `benchmark.json["regressions"]` for `wiki/`).

If all three agree, the run was successful. If they disagree, trust
them over any in-flight events.

### Assert plugin-meta lockstep, never a literal version

A harness that checks the plugin metadata must assert the invariant the
standing repo rules state, which is that `.codex-plugin/plugin.json` and
both marketplace registrations carry whatever version
`.claude-plugin/plugin.json` currently holds. Pinning the literal version
a change shipped at makes the harness fail on the next routine bump, and
that is exactly what `tests/guardrail_audit/` and `tests/format_rust/`
both did until they were rewired.

Source the shared helper and call it with the plugin name:

```bash
# shellcheck source=../../lib/plugin_version.sh
. "$HERE/../../lib/plugin_version.sh"
check_plugin_version_lockstep ai_dev
```

`tests/lib/plugin_version.sh` reports through the harness's own `check`
helper, so its four results land in the existing pass and fail tallies.
It needs `REPO_ROOT` and `check` already defined, so source it after the
harness sets those up. Match a marketplace entry by plugin name rather
than grepping the file for a version string, since a registration lists
many plugins and a bare grep matches any of them; the helper already
does this.

## tests/wiki/: Pattern B, two-layer

The wiki skill ships bundled scripts (`discover_wiki.sh`,
`init_wiki.sh`, `lint.py`, `compute_sha256.py`) **and** load-bearing
prose policy. They regress independently.

### Commands

```bash
# Layer 1 only — deterministic script unit tests, ~1 sec, no LLM cost
./tests/wiki/run_all.sh

# Layer 1 + Layer 2 — full suite, ~10–15 min with 4 parallel workers
./tests/wiki/run_all.sh --layer2

# Single Layer 2 scenario while debugging
python3 ./tests/wiki/layer2/run.py --scenario L2-2

# Re-grade an existing run without re-spawning subagents (after
# editing assertions or evals.json — responses are immutable once
# captured)
RUN=tests/wiki/layer2/workspace/run-<ts>
python3 tests/wiki/layer2/normalize.py     "$RUN"
python3 tests/wiki/layer2/grade.py         "$RUN"
python3 tests/wiki/layer2/aggregate.py     "$RUN"
python3 tests/wiki/layer2/render_report.py "$RUN"
```

### Reading the result

```text
tests/wiki/layer2/workspace/run-<ts>/
├── grading_summary.json   # flat list: scenario × pass → passed: true/false
├── benchmark.json         # per-assertion pass rate + "regressions": [...]
├── benchmark.md           # same data, human-readable
└── report.html            # interactive viewer (open in a browser)
```

One-shot verdict check after a run:

```bash
RUN=tests/wiki/layer2/workspace/run-<ts>
python3 -c "
import json, sys
s = json.load(open('$RUN/grading_summary.json'))
b = json.load(open('$RUN/benchmark.json'))
ok    = sum(1 for d in s if d['passed'])
total = len(s)
regs  = b.get('regressions', [])
print(f'graded: {ok}/{total} passed; regressions vs prior: {len(regs)}')
sys.exit(0 if ok == total and not regs else 1)
"
```

The aggregator compares against the most recent prior `benchmark.json`
automatically. `run.py` exits non-zero if any assertion that was 100%
in the prior run is now <100%, or any all-clean scenario now has at
least one fail.

### Audit signals if a run looks off

```bash
RUN=tests/wiki/layer2/workspace/run-<ts>

# Any subprocess that errored
find "$RUN" -name timing.json -exec grep -l '"claude_rc": [^0]' {} \;

# Any captured stderr (empty stderr files are normal/expected)
find "$RUN" -name stderr.txt -size +0

# Any graded failure
find "$RUN" -name grading.json -exec grep -l '"passed": false' {} \;
```

If all three return empty and `regressions: []`, the run was genuinely
clean.

### Per-pass timeout

`run.py --timeout` defaults to 600s. The import/wrapup scenarios
(`WI-*`, `WU-*`) regularly push past 400s and can flirt with the
default under load. If a run shows transient single-pass fails that
recover on retry, prefer `--timeout 900` over chasing the symptom.

### Layer 2 sandbox isolation: load-bearing assertions

Every Layer 2 scenario asserts:

- `no_files_outside_sandbox`
- `real_home_wiki_absent`

These are the fail-safes that justify running on the operator's real
filesystem rather than a container. They've never failed in any run,
but they're the reason the harness can be safely re-run without
isolation. Don't drop them when adding scenarios.

## tests/git_commit/: Pattern A, skill-creator-aligned

Two surfaces, each in its own subdir:

| Surface | Where | What it tests | Runner |
| --- | --- | --- | --- |
| `script_tests/` | `prepare_commit_context.sh`, `commit_with_message.sh` | Stdout / exit-code / git-state on real working trees | `./tests/git_commit/run_all.sh` |
| `evals/` | Skill agent behavior | Primary workflow + commit-message format + fallback discipline | Operator-driven: `stage.sh` → agent runs → `grade.sh` |

### script_tests: fast, deterministic

```bash
./tests/git_commit/run_all.sh
```

Stages a fresh per-scenario temp git repo under
`script_tests/scratch/<id>/`. ~1 sec. No LLM cost.

### Behavioral evals: three-phase operator workflow

The installed skill-creator skill is **read-only** for this harness;
nothing under `tests/git_commit/` copies into or patches it. All
harness logic stays in this directory.

```bash
# 1. Stage one fixture; exports shell-safe name=value lines
eval "$(bash tests/git_commit/evals/stage.sh <eval_id>)"

# 2. Have an agent (in this session) load $skill_path and apply it to
#    $sandbox_repo with the prompt in $prompt. The agent uses its own
#    Skill/Read/Bash tools — there's no orchestrator that drives it.

# 3. Grade the post-run sandbox programmatically
bash tests/git_commit/evals/grade.sh <eval_id> "$sandbox_repo"
```

`evals/README.md` has the full recipe and the per-eval expectations.
Phase 2 is operator-driven; there is no `workspace/iteration-N/`
tree to inspect (the older README claimed there was; it's been
corrected).

### What success looks like

- `run_all.sh` exits 0 with all `script_tests` scenarios PASS.
- For each behavioral eval: `grade.sh <id> "$sandbox_repo"` exits 0
  and prints PASS for every expectation.

### Scope discipline

Ship the tests a change needs in the same session as the change: a
skill change lands with the tight new scenario(s) that prove its own
behavior, and you run `./tests/git_commit/run_all.sh` to confirm no
regression before committing. Keep only *unbounded* harness growth for
its own session: backfilling coverage of pre-existing behavior, or
adding scenarios well past what the change needs. The boundary is
scope, not timing.

## tests/trigger_evals/: skill triggering (description-matching)

Tests a separate axis from the other harnesses: whether a skill's
*description* causes Claude to load the skill on a realistic user
message. Skill *behavior* is tested by `wiki/` and `git_commit/`;
skill *triggering* is tested here.

Each `<skill>.json` is an array of `{query, expected_skill}` entries.
The runner is the local wrapper `tests/trigger_evals/run.py`.

### Eval-set schema

```json
[
  {"query": "add a page to my wiki about transformers", "expected_skill": "wiki"},
  {"query": "ingest this URL: ...", "expected_skill": "wiki_import"},
  {"query": "audit my wiki for broken links", "expected_skill": "wiki_fix"},
  {"query": "wrap up this chat into my notes", "expected_skill": "wiki_wrapup"},
  {"query": "format the python file at src/loader.py", "expected_skill": null}
]
```

`expected_skill` names the *specific* skill that should fire. Use
`null` to mean "no skill from this family should fire" (a request
that's outside wiki/wiki_import/wiki_fix/wiki_wrapup territory
entirely). For backward compatibility the runner still accepts the
older `{"query": "...", "should_trigger": true|false}` form:
`should_trigger: true` maps to `expected_skill = <--skill>` and
`should_trigger: false` maps to `expected_skill = null`. The legacy
form can't express "trigger a sibling instead," so prefer the
explicit `expected_skill` form when authoring or migrating an eval
set.

### Run pattern

Trigger evals are Claude-only, so the runner defaults to Claude; run them
where a change needs the measurement, such as a description edit, in the
foreground, with `--vendor claude` in the command so the Claude run is
visible.

```bash
python3 tests/trigger_evals/run.py --vendor claude \
  --eval-set tests/trigger_evals/wiki.json \
  --skill wiki \
  --runs-per-query 3 \
  --timeout 45 \
  --workers 10
```

`run.py` selects mode from the deployed tree:

- **Deployed mode** (default when `~/.claude/skills/<name>/SKILL.md`
  exists): spawns `claude -p` for each query × runs-per-query and
  watches the stream for the FIRST tool_use being either
  `Skill(skill="<X>", …)` or `Read(/<X>/SKILL.md)`. Records *which*
  skill `<X>` actually fired, not just "did SOMETHING fire." Warns
  if the deployed `description:` has drifted from the source under
  `plugins/…/<name>/SKILL.md` (run `make deploy` to resync).
- **Unavailable skill** (skill absent from the deployed tree, and
  `--force-uuid` not set): exits non-zero with a named unavailability
  error and writes no score. Deploy the skill (`make deploy`) before
  measuring, or pass `--force-uuid` deliberately.
- **Force UUID** (`--force-uuid`): the only entry to the UUID-proxy
  path. Delegates to skill-creator's `run_eval.py`, which writes a
  temp slash command under
  `~/.claude/commands/<name>-skill-<uuid>.md` carrying the description
  being tested and watches for the UUID in `Skill` / `Read` inputs.
  Family/precise grading is NOT supported in this mode; the proxy
  reports only the upstream single-skill pass/fail. Rarely useful
  when the real skill is also deployed: names like `wiki` beat
  `wiki-skill-<uuid>`, so the proxy never gets called and scores
  0/N falsely.

**Reading a zero-recall outcome.** In deployed mode, a description-level
zero for the skill under test shows those `expected_skill` rows as
`[..]` in `run.log`, or `[.F]` when a sibling took the load, while
null-expected rows still pass. On a single-target set that looks like
`Precise: 8/16` on `agent_spinner.json` (every target row failed; every
null row passed). Treat that as evidence about the `description:`, not
as an availability failure. The unavailable-skill guard covers only
`--skill`: when that named skill is missing from the deployed tree the
run exits with the named unavailability and writes no score. Undeployed
siblings in a multi-skill set still reach deployed mode, so every
positive row at `[..]` with only the null rows passing should first
send the reader to check what the worker could load (siblings present
and deployed) before blaming one description. A run that prints
`Precise: 0/N` with `__worker_failed__` in every triggered column is a
dead worker; diagnose it through
``### Worker auth: nested `claude -p` reads the stored OAuth login``
above, not as a skill regression.

### Family / precise grading (deployed mode)

`run.py` reports two pass rates per run:

- **Precise**: the FIRST tool the model invoked loaded the *exact*
  `expected_skill`. For `expected_skill: null`, precise = "no skill
  was loaded as the first tool."
- **Family**: the first tool loaded *any* skill in the family list.
  For `expected_skill: null`, family = "no family member was loaded."

The family list defaults to skills sharing the same name root as
`--skill` (e.g. `wiki` → `[wiki, wiki_fix, wiki_import, wiki_wrapup]`;
`format_python` → `[format_markdown, format_python, format_rust]`).
Override explicitly with `--family wiki,wiki_import` if the
auto-derivation isn't what you want.

A query that says "audit my wiki for broken links" with
`expected_skill: wiki_fix` and an actual triggered run of
`[wiki_fix, wiki, wiki]` will score precise = 1/3 (FAIL at the 50%
threshold) but family = 3/3 (PASS, the model always recognized
wiki-territory). That's the diagnosis the family metric is designed
to surface: "description bleed between siblings" looks very different
from "the skill doesn't trigger at all."

Per-query pass uses a 50% threshold over `runs-per-query` runs.

**Why we don't call skill-creator's `run_eval.py` / `run_loop.py`
directly anymore**: the upstream runner's UUID-proxy mechanism is
incompatible with the user's environment once any skill from this
repo is `make deploy`-installed. The real skill outranks the proxy
and the upstream runner records 0 triggers across the board,
producing a misleading "10/20 passed" (only the should-NOT-trigger
queries trivially pass). The local runner sidesteps that by talking
directly to the deployed skill.

### Reading the trigger-eval result

```text
tests/trigger_evals/results/<skill>/<timestamp>/
├── results.json   # {skill_name, mode, family, results: [...], summary: {...}}
└── run.log        # config + progress + per-query [P|.][F|.] grid
```

Per-query row schema (deployed mode):

```json
{
  "query": "audit my wiki for broken links and missing index entries",
  "expected_skill": "wiki_fix",
  "triggered_skill_per_run": ["wiki_fix", "wiki", "wiki"],
  "precise_triggers": 1,
  "family_triggers": 3,
  "runs": 3,
  "precise_trigger_rate": 0.333,
  "family_trigger_rate": 1.0,
  "precise_pass": false,
  "family_pass": true
}
```

`summary` carries `total`, `precise_passed`, `family_passed`,
`precise_failed`, `family_failed`.

The run.log per-query line uses a two-letter marker `[Xy]` where
`X = P` (precise pass) or `.`, and `y = F` (family pass) or `.`:

```text
[PF] expected=wiki_fix    triggered=wiki_fix/wiki_fix/wiki_fix : fix my wiki — it's been a while ...
[.F] expected=wiki_fix    triggered=wiki_fix/wiki/wiki         : audit my wiki for broken links ...
[..] expected=wiki_import triggered=-/wiki_import/-            : the wiki at ~/work/sales-ops doesn't have a page yet ...
```

`run.py` exits 0 when *precise* passes for every query, 1 otherwise.
The graded summary is the verdict; exit code is just a CI signal.
Family-only passes still count as failures by exit code; they're
diagnostic, not "good enough." Treat them as "fix the description
bleed," not as "done."

### When to run trigger evals

After material edits to a skill's `description:` frontmatter, after
adding or renaming a sibling skill in the same family, or when
adding a new skill. Don't run them on every skill-content change;
they're slow and the description usually isn't what you just edited.

### Always diff against the prior run: `--baseline`

The absolute pass rate hides drift. The precise rate is noisy (each
query passes on a 50%-over-3-runs threshold), so two runs can report
the same headline number while individual queries move underneath it.
A routing regression once sat unnoticed for 19 days behind a flat
aggregate for exactly this reason: a `description:` change to one
sibling pulled two queries to it (2/2 precise before, 0 across five
runs after), and nothing compared runs per query.

So pass the prior run as `--baseline` on every trigger run:

```bash
python3 tests/trigger_evals/run.py --vendor claude \
  --eval-set tests/trigger_evals/task.json \
  --skill task --skill-path plugins/ai_dev/skills/task \
  --runs-per-query 3 --timeout 45 --workers 10 \
  --baseline tests/trigger_evals/results/task/<prior-timestamp>
```

`--baseline` accepts the prior run's directory or its `results.json`.
The run then diffs per query on the shared cohort and reports each
`REGRESSION` (a query that passed in the baseline and now fails) and
each `improvement` (the reverse), with the before/after trigger
counts. A regression makes the exit code non-zero, turning the
runner into a real drift signal instead of the always-non-zero
"did every query pass" check it was before. The comparison is also
written into `results.json` under `baseline_comparison`.

A lone per-query flip can still be sampling noise at the 50% threshold
(the report says so), so confirm a single regression with a re-run
before acting on it. A query that fails persistently and is understood
(name-token dominance, an inline-acting model the runner can't observe,
accepted sibling bleed) carries its disposition as a `note` field beside
its entry in the eval set, so a baseline that already shows it failing
never flags it as new. The detector's own unit tests live in
`tests/trigger_evals/script_tests/run.sh` (hermetic, no LLM cost).

### Acting on family-only passes

If a query passes family but fails precise, the wiki family is
correctly seen but a *sibling* is stealing the trigger. The fix is
usually in the *sibling's* description, not the expected one:
sharpen the sibling away from the territory it's encroaching on.
E.g. "audit my wiki for broken links" with `expected: wiki_fix` but
triggered `[wiki_fix, wiki, wiki]`: sharpen the `wiki` description
to NOT claim "audit / lint / fix / health-check" verbs that belong
to `wiki_fix`.

### Gotcha: stale `~/.claude/commands/<name>-skill-<uuid>.md`

If a UUID-fallback run gets interrupted, the temp slash command may
linger and show up in your skill catalog of subsequent sessions. Clean
up with `rm ~/.claude/commands/*-skill-*.md` if you spot leftovers.
Deployed-mode runs leave no temp files.

## Adding a harness for a new skill

1. Create `tests/<skill_name>/` with Pattern A's layout:

   ```text
   tests/<skill_name>/
   ├── README.md
   ├── RUNBOOK.md
   ├── run_all.sh                    # bundled-script unit tests entrypoint
   ├── results/
   ├── script_tests/
   │   ├── run.sh
   │   └── scratch/<id>/             # transient per-scenario sandboxes
   ├── evals/
   │   ├── README.md
   │   ├── evals.json                # canonical skill-creator schema
   │   ├── stage.sh                  # optional: stage one fixture
   │   ├── grade.sh                  # optional: programmatic grading
   │   └── fixtures/<name>/setup.sh  # per-eval sandbox stagers
   └── workspace/                    # iteration outputs if relevant
   ```

2. Implement `script_tests/run.sh` first if the skill ships bundled
   scripts. Stage a fresh sandbox per scenario; never operate on the
   host repo's working tree. The runner must fail loud: exit
   non-zero on any failed assertion.

3. Author `evals/evals.json` and per-eval fixture `setup.sh` scripts
   for any skill-prose behavior that scripts can't verify (message
   format discipline, fallback behavior, user-prompting). Schema:
   `{id, prompt, expected_output, files, expectations[]}` per
   `skill-creator/references/schemas.md`.

4. Add per-skill `<skill>.json` to `tests/trigger_evals/` only when
   the skill's *triggering* behavior is non-trivial, usually a new
   skill that overlaps semantically with an existing one.

5. When designing eval assertions, lean on filesystem-state and
   structured-report-field checks first. Reach for free-form
   response-text checks only when no other signal captures the
   behavior; agent prose is the most variable surface and the
   surface most likely to make a real change look like a regression.

6. If the harness runs the skill against a real filesystem (no
   container), add explicit sandbox-isolation fail-safes, e.g.
   "no files modified outside the sandbox," "no writes to
   `$HOME/<destination>`." See `wiki/` Layer 2 for the load-bearing
   pattern.

## What "all green" actually guarantees

- **Bundled scripts** (Layer 1 in `wiki/`, `script_tests/` in
  `git_commit/`): the mechanical surface of the skill behaves as
  specified for every input shape we test.
- **Behavioral evals** (Layer 2 in `wiki/`, `evals/` in
  `git_commit/`): the agent followed the skill's load-bearing
  workflow across N independent samples: invoked the right scripts,
  composed conformant output, honored refusal/fallback rules, didn't
  leak outside the sandbox.
- **Trigger evals** (`trigger_evals/`): the skill's description is
  selective enough on `should_trigger: false` cases and inclusive
  enough on `should_trigger: true` cases.

It does NOT guarantee the skill's prose advice leads to good
end-user output on real-world content. That's a quality question
best evaluated by humans on real artifacts.
