# CLAUDE.md — running the local test harnesses

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
| `git_review/` | `git_review` | Pattern A (skill-creator-aligned) | `script_tests/` bundled-script unit tests over staged clones with real remotes (the fetch-before-diff order, the two commit walks, base-side versions of deleted files, the test merge, the head-vs-upstream relationship behind the fast-forward decision, stub-`gh` thread pagination, the heading-range helper) + `evals/` behavioral evals over 36 fixtures via `evals/run.py`. |
| `language_humanizer/` | `language_humanizer` | Pattern A (behavioral only) | 3 scenarios × fixed 5-pass denominator; deterministic `grade.py` (word counts, ledger items, prose shape) + refute-biased `judge.py` for the qualitative assertions. |
| `task/` | `task` (family hub) | Pattern A (skill-creator-aligned) | `script_tests/run.sh` unit-tests the bundled `lint.py`, `discover_tasks.sh`, and `init_tasks.sh`; `script_tests/contract_run.sh` asserts the family contract across the hub, its siblings, and the family agents; `evals/` holds a behavioral eval per family member. `run_all.sh` drives both script runners. |
| `task_create/` | `task_create` | Pattern A (behavioral only) | Three staged evals over the base **Decide or label** rule as the create path applies it; the bundled scripts it drives are covered under `task/script_tests/`. |
| `task_auto_check/` | `task_auto_check` | Pattern A (skill-creator-aligned) | `script_tests/` static contract checks + `evals/` over the autonomous readiness loop (repair-to-ready, gate/verifier/drift stops, mechanical lint cleanup). |
| `trigger_evals/` | wiki and `task_*` family skills | local `run.py` wrapper (auto: deployed-mode or UUID fallback) | Whether a skill *triggers* on realistic user messages (description-matching), separate from skill *behavior*. |

Pattern A is preferred for new harnesses. Pattern B stays in `wiki/`
until the next significant iteration; don't bring up new harnesses
under Pattern B.

## Universal operator lessons

These are the things that bit me in practice. They apply to every
harness here regardless of pattern.

### Model policy: pin the skill-under-test to sonnet, keep the meta level inherited

Every harness that runs a skill as a subprocess pins that worker to
**`claude-sonnet-4-6`** — the thing under test runs on one cheap, stable
model so results don't drift with whatever the host session happens to
be. Only the **meta level on top** — the orchestrator, the grader, the
aggregation — runs on the inherited session model. Concretely:

| Harness | Worker (sonnet-pinned) | Meta level (inherited) |
| --- | --- | --- |
| `trigger_evals/run.py` | `claude -p` per query (`--model` default `claude-sonnet-4-6`) | precise/family scoring — pure Python, no model |
| `wiki/layer2/run.py` | `claude -p` per scenario×pass (`--model` default `claude-sonnet-4-6`) | `grade.py` / `aggregate.py` — pure Python, no model |
| `git_commit/evals/run.py` | `claude -p` per eval (`--model` default `claude-sonnet-4-6`) | `grade.sh` (deterministic) + operator prose-verdict confirmation |
| `task/evals/run.py` | `claude -p` per eval (`--model` default `claude-sonnet-4-6`) | `grade.sh` (deterministic) + operator prose-verdict confirmation |
| `task_create/evals/run.py` | `claude -p` per eval (`--model` default `claude-sonnet-4-6`) | `grade.sh` (deterministic) + operator prose-verdict confirmation |
| `task_auto_check/evals/run.py` | `claude -p` per eval (`--model` default `claude-sonnet-4-6`) | `grade.sh` (deterministic) + operator prose-verdict confirmation |
| `git_review/evals/run.py` | `claude -p` per eval (`--model` default `claude-sonnet-4-6`) | `grade.sh` (deterministic) + operator prose-verdict confirmation |

Each runner takes `--model` to override, and `--model ''` inherits the
CLI default. The behavioral eval runners (`git_commit/evals/run.py`,
`task/evals/run.py`, `task_create/evals/run.py`,
`task_auto_check/evals/run.py`, `git_review/evals/run.py`) automate the old
operator-driven Phase 2: instead of running the skill yourself in-session
(which would use the inherited model), let the runner spawn the sonnet
worker, then read `response.txt` for the prose-verdict expectations
`grade.sh` can't check.

### Verdict cache: skip re-running an eval whose inputs haven't changed

The five Pattern-A behavioral runners (`git_commit/evals/run.py`,
`task/evals/run.py`, `task_create/evals/run.py`,
`task_auto_check/evals/run.py`, `git_review/evals/run.py`) cache each eval's
graded verdict and skip re-spawning its `claude -p` worker when nothing that
determines the verdict has changed. The shared helper is
`tests/lib/eval_cache.py`; verdicts live per-harness in
`<evals>/.eval_cache/` (gitignored as run output, like `workspace/`).

The cache key is a content hash of: the skill source under test **and its
family dependencies** — for the task family that means the loaded sibling
*plus* the base `task` skill *plus* `plugins/ai_dev/agents/`, because every
sibling reads the base via `<authority>` and the `auto_*` siblings spawn
those agents, and for `git_review` it means the `git_checkout` and
`git_commit` skill directories it hands work to — the harness definition
(the whole `evals/` dir: evals.json,
stage.sh, grade.sh, fixtures, run.py), the worker model, the eval id, and
the prompt. Change any of those and the key moves, so the cache misses and
the eval re-runs. It can never serve a stale pass: a hit means byte-identical
inputs to a run already graded. Over-inclusion (e.g. editing `task_select`
invalidates a `task_implement` eval) only costs an occasional extra run — the
safe direction.

- **Default: on.** A hit prints `CACHED PASS/FAIL … skipped claude -p` and
  replays the stored verdict, writing `cached.json` plus a clearly-bannered
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

### Cheap-first: probe an LLM-eval fixture before paying for the full loop

For any eval whose worker runs a deep, slow loop — the `task_auto_check`
repair loop is the current example (~15–25 min per run, timeout-prone) —
validate the fixture with the cheapest surface that reveals the same
verdict *before* running the loop. For a readiness-repair eval that means
running the gate skill (`task_check`) alone against the staged fixture: a
single `claude -p` reading that skill, ~1–3 min, reporting its verdict and
issue list. A fixture-design bug (an unintended second readiness gap, an
inaccurate premise) caught at the gate costs minutes; the same bug caught
via a full-loop timeout costs 15–25. And run these deep loops
**sequentially** — two in parallel contend for the model and both slow
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
while that login is present and unexpired. Never pass `--bare` — it
forces `ANTHROPIC_API_KEY` / `apiKeyHelper` auth and 401s a subscription
login. The shared helper `tests/lib/worker_auth.py` does this — its
`worker_env()` pops `CLAUDECODE` and the HAS_*_REFRESH flags, and its
`preflight_auth()` fails fast on a dead login with one live `claude -p`
probe (the remediation below) instead of 401-ing every eval. Every
`claude -p` runner imports the helper: `task/evals/run.py`,
`task_create/evals/run.py`, `task_auto_check/evals/run.py`,
`git_commit/evals/run.py`, and `git_review/evals/run.py` use both the
pre-flight and the worker env; `trigger_evals/run.py` and
`wiki/layer2/run.py` use `worker_env()`.

**Failure signature:** worker rc≠0 with
`API Error: 401 Invalid authentication credentials` in `response.txt` —
an expired or absent login, not a skill regression (check `timing.json`
before attributing). The CLI's keychain OAuth is not self-refreshing (a
known bug, anthropics/claude-code#31095, #50743): an expired accessToken
with no usable refreshToken 401s forever. `claude auth status` still
reports `loggedIn` past expiry, so trust the live probe, then re-auth
with `claude auth login` and re-run.

**Optional headless-token override** — for a machine with no interactive
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
line per event and *exits* when done — don't lean on `tail -f`.

### Ground truth lives in files, not mid-stream events

When a harness spawns LLM subagents (Layer 2 in `wiki/`, the
behavioral evals in `git_commit/`), the host Claude Code instrumentation
may surface subprocess-level events into the parent session's
notification stream. These look like real test outcomes — e.g.

```text
[WU-2 pass-1] FAIL (524.0s)
```

— but they are **not** in the orchestrator's stdout, are **not**
printed by any script in the harness, and are **not** the graded
verdict. They are subprocess-timing artifacts from the host's wrapper
around `claude -p`. A `FAIL (524s)` usually means the subprocess ran
close to its per-pass `--timeout`; the orchestrator may have retried
it, and the final graded state is what counts.

Always cross-check mid-stream impressions against the ground-truth
files the harness writes. If those agree on "clean run," the run was
clean — regardless of what flickered through the notification stream.

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

## tests/wiki/ — Pattern B, two-layer

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

### Layer 2 sandbox isolation — load-bearing assertions

Every Layer 2 scenario asserts:

- `no_files_outside_sandbox`
- `real_home_wiki_absent`

These are the fail-safes that justify running on the operator's real
filesystem rather than a container. They've never failed in any run,
but they're the reason the harness can be safely re-run without
isolation. Don't drop them when adding scenarios.

## tests/git_commit/ — Pattern A, skill-creator-aligned

Two surfaces, each in its own subdir:

| Surface | Where | What it tests | Runner |
| --- | --- | --- | --- |
| `script_tests/` | `prepare_commit_context.sh`, `commit_with_message.sh` | Stdout / exit-code / git-state on real working trees | `./tests/git_commit/run_all.sh` |
| `evals/` | Skill agent behavior | Primary workflow + commit-message format + fallback discipline | Operator-driven: `stage.sh` → agent runs → `grade.sh` |

### script_tests — fast, deterministic

```bash
./tests/git_commit/run_all.sh
```

Stages a fresh per-scenario temp git repo under
`script_tests/scratch/<id>/`. ~1 sec. No LLM cost.

### Behavioral evals — three-phase operator workflow

The installed skill-creator skill is **read-only** for this harness —
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
Phase 2 is operator-driven — there is no `workspace/iteration-N/`
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
its own session — backfilling coverage of pre-existing behavior, or
adding scenarios well past what the change needs. The boundary is
scope, not timing.

## tests/trigger_evals/ — skill triggering (description-matching)

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
older `{"query": "...", "should_trigger": true|false}` form —
`should_trigger: true` maps to `expected_skill = <--skill>` and
`should_trigger: false` maps to `expected_skill = null`. The legacy
form can't express "trigger a sibling instead," so prefer the
explicit `expected_skill` form when authoring or migrating an eval
set.

### Run pattern

```bash
python3 tests/trigger_evals/run.py \
  --eval-set tests/trigger_evals/wiki.json \
  --skill wiki \
  --model claude-sonnet-4-6 \
  --runs-per-query 3 \
  --timeout 45 \
  --workers 10
```

`run.py` auto-detects whether the skill is deployed:

- **Deployed mode** (default when `~/.claude/skills/<name>/SKILL.md`
  exists): spawns `claude -p` for each query × runs-per-query and
  watches the stream for the FIRST tool_use being either
  `Skill(skill="<X>", …)` or `Read(/<X>/SKILL.md)`. Records *which*
  skill `<X>` actually fired, not just "did SOMETHING fire." Warns
  if the deployed `description:` has drifted from the source under
  `plugins/…/<name>/SKILL.md` (run `make deploy` to resync).
- **UUID-proxy fallback** (when the skill is NOT deployed): delegates
  to skill-creator's `run_eval.py`, which writes a temp slash command
  under `~/.claude/commands/<name>-skill-<uuid>.md` carrying the
  description being tested and watches for the UUID in `Skill` /
  `Read` inputs. Useful for testing a description *before* deploy.
  Family/precise grading is NOT supported in this mode — the fallback
  reports only the upstream single-skill pass/fail.
- **Force UUID** (`--force-uuid`): override auto-detect and use the
  UUID-proxy path even when the skill is deployed. Rarely useful in
  practice — if you have the real skill deployed *and* you pass the
  same description through the proxy, the model picks the deployed
  one (because names like `wiki` beat names like `wiki-skill-<uuid>`),
  and the proxy never gets called, which scores 0/N falsely.

### Family / precise grading (deployed mode)

`run.py` reports two pass rates per run:

- **Precise** — the FIRST tool the model invoked loaded the *exact*
  `expected_skill`. For `expected_skill: null`, precise = "no skill
  was loaded as the first tool."
- **Family** — the first tool loaded *any* skill in the family list.
  For `expected_skill: null`, family = "no family member was loaded."

The family list defaults to skills sharing the same name root as
`--skill` (e.g. `wiki` → `[wiki, wiki_fix, wiki_import, wiki_wrapup]`;
`format_python` → `[format_markdown, format_python, format_rust]`).
Override explicitly with `--family wiki,wiki_import` if the
auto-derivation isn't what you want.

A query that says "audit my wiki for broken links" with
`expected_skill: wiki_fix` and an actual triggered run of
`[wiki_fix, wiki, wiki]` will score precise = 1/3 (FAIL at the 50%
threshold) but family = 3/3 (PASS — the model always recognized
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
Family-only passes still count as failures by exit code — they're
diagnostic, not "good enough." Treat them as "fix the description
bleed," not as "done."

### When to run trigger evals

After material edits to a skill's `description:` frontmatter, after
adding or renaming a sibling skill in the same family, or when
adding a new skill. Don't run them on every skill-content change —
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
python3 tests/trigger_evals/run.py \
  --eval-set tests/trigger_evals/task.json \
  --skill task --skill-path plugins/ai_dev/skills/task \
  --model claude-sonnet-4-6 --runs-per-query 3 --timeout 45 --workers 10 \
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
— the report says so — so confirm a single regression with a re-run
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
triggered `[wiki_fix, wiki, wiki]` — sharpen the `wiki` description
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
   host repo's working tree. The runner must fail loud — exit
   non-zero on any failed assertion.

3. Author `evals/evals.json` and per-eval fixture `setup.sh` scripts
   for any skill-prose behavior that scripts can't verify (message
   format discipline, fallback behavior, user-prompting). Schema:
   `{id, prompt, expected_output, files, expectations[]}` per
   `skill-creator/references/schemas.md`.

4. Add per-skill `<skill>.json` to `tests/trigger_evals/` only when
   the skill's *triggering* behavior is non-trivial — usually a new
   skill that overlaps semantically with an existing one.

5. When designing eval assertions, lean on filesystem-state and
   structured-report-field checks first. Reach for free-form
   response-text checks only when no other signal captures the
   behavior — agent prose is the most variable surface and the
   surface most likely to make a real change look like a regression.

6. If the harness runs the skill against a real filesystem (no
   container), add explicit sandbox-isolation fail-safes — e.g.
   "no files modified outside the sandbox," "no writes to
   `$HOME/<destination>`." See `wiki/` Layer 2 for the load-bearing
   pattern.

## What "all green" actually guarantees

- **Bundled scripts** (Layer 1 in `wiki/`, `script_tests/` in
  `git_commit/`): the mechanical surface of the skill behaves as
  specified for every input shape we test.
- **Behavioral evals** (Layer 2 in `wiki/`, `evals/` in
  `git_commit/`): the agent followed the skill's load-bearing
  workflow across N independent samples — invoked the right scripts,
  composed conformant output, honored refusal/fallback rules, didn't
  leak outside the sandbox.
- **Trigger evals** (`trigger_evals/`): the skill's description is
  selective enough on `should_trigger: false` cases and inclusive
  enough on `should_trigger: true` cases.

It does NOT guarantee the skill's prose advice leads to good
end-user output on real-world content. That's a quality question
best evaluated by humans on real artifacts.
