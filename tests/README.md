# tests/

Regression test harnesses for the skills shipped in this repo. The
authored harness is committed: `evals.json`, fixtures and their
`setup.sh` stagers, the run and grade scripts, and each subdirectory's
`README.md` and `RUNBOOK.md`. Everything a run regenerates stays local
via `tests/.gitignore`: `workspace/`, `scratch/`, `.eval_cache/`,
`__pycache__/`, the per-run logs and reports under `results/`, and the
staged `wiki/layer2/{AS,L2,WI,WU}-*` sandboxes. The Makefile's lint
targets prune exactly those regenerated subtrees, so `make lint` covers
the committed harness and nothing else. Keep the two prune lists in
step whenever either changes.

## Vendor switch

Behavioral runners share `tests/lib/vendor.py` and accept `--vendor {claude,cursor}`
(default `cursor`; the Claude-only harnesses default to `claude` and stop with an
error on an explicit `--vendor cursor`), so run them without `--vendor` unless
the run is on Claude. Claude
workers use the latest `sonnet` alias; Cursor workers
use `auto` via `agent -p`. Cursor is the project's measurement vendor because
its runs are cheaper and faster, so develop and iterate on it; it is fine to
rely on Cursor results without running the Claude suites. A test that needs a
Claude-specific feature runs on Claude with `--vendor claude` in its command,
also on a Claude-only harness, so the Claude run is visible; any other Claude
run waits for the operator's explicit request, and none runs in the
background. See `tests/CLAUDE.md` and `tests/AGENTS.md` for the
full matrix, auth, Claude-only rejects (`natural_language/`),
and the per-pass micro-deployment rule (`tests/lib/micro_deploy.py`: workers
load artefacts only from that deployment, deployed user copies stay out of
view, and `artefacts_read_from_micro_deployment` plus `checkout_unread`
enforce the read checks). Isolated-sandbox
evals that use `tests/lib/eval_runner` default to 4 parallel workers
(`DEFAULT_PARALLEL_WORKERS` in `tests/lib/vendor.py`); runners still on a
private pool or kept sequential are named in `tests/CLAUDE.md` /
`tests/AGENTS.md`.

## Convention

One subdirectory per skill under test. Two patterns are in use:

### Pattern A: skill-creator-aligned (preferred for new harnesses)

Skill-level evals follow Anthropic's official `skill-creator` skill:
canonical `evals/evals.json` schema, free-form `expectations` strings
graded by a subagent, `workspace/iteration-N/eval-<id>/{with_skill,
without_skill}/` runtime layout. Bundled-script unit tests sit
alongside in `script_tests/` (not a "layer" of the eval, just plain
shell unit tests for the scripts the skill ships).

```text
tests/
├── run_all.sh                    # aggregate deterministic gate (`make test`)
└── <skill_name>/
    ├── README.md
    ├── RUNBOOK.md
    ├── run_all.sh                # this harness's deterministic entrypoint
    ├── results/
    ├── script_tests/
    │   ├── run.sh
    │   └── scratch/<id>/         # transient per-scenario sandboxes
    ├── evals/                    # skill-creator
    │   ├── README.md
    │   ├── evals.json            # canonical schema
    │   └── fixtures/<name>/setup.sh  # per-eval sandbox stagers
    └── workspace/                # skill-creator run output
        └── iteration-N/
```

Reference: `skill-creator/SKILL.md` and `skill-creator/references/schemas.md`
(installed under `~/.claude/plugins/.../skill-creator/`).

### Pattern B: home-grown two-layer (legacy)

Pre-dates the skill-creator alignment. Mature in `tests/wiki/`.

```text
tests/<skill_name>/
├── layer1/      # script-level, deterministic, bash + Python
└── layer2/      # skill-level, custom orchestrator + typed assertions
```

Migrate to Pattern A on the next significant iteration of the harness;
don't bring up new harnesses under Pattern B.

## Current harnesses

`tests/run_all.sh` is the aggregate gate: it discovers each harness below at
run time, runs the harness's deterministic entrypoint and every
`evals/test_run.py` or `evals/test_grade.py` its
`evals/covered-by-entrypoint` declaration omits, and runs every
`tests/lib/test_*` unit test. The declaration names, one file per line, the
eval files the entrypoint runs; a harness that carries an eval file without a
declaration fails the gate by name. `make test` invokes it, and
`bash tests/run_all.sh --list` prints the discovered coverage tree. A harness
keeps its own deterministic entrypoint as the scoped subset for one harness.

Scenario counts are the tally line `bash tests/<harness>/script_tests/run.sh`
prints where a harness has that script, and the `jq '.evals | length'` count
on its `evals/evals.json` where it does not; eval counts come from that
`jq` count, and fixture counts from the directories
`ls tests/<harness>/evals/fixtures` lists beside that harness's shared helper
files.

- **`lint_frontmatter/`**: Pattern A script tests. `script_tests/run.sh`
  stages every fixture in a temporary directory outside the checkout and
  proves the strict YAML-subset gate at `scripts/lint_frontmatter.py`: the
  rejected and accepted frontmatter shapes, `--values` decoding, the
  `tests/` exclusion from the default file set, the `SKILL.md` hand-off to
  skill_doctor's `discovery_safety.py`, the missing-script failure, and the
  `make lint` wiring.
- **`wiki/`**: Pattern B. Full Layer 1 (deterministic, `layer1/run.sh`
  prints its own scenario tally) + Layer 2 (every scenario in
  `layer2/evals.json`, each over that file's top-level `passes`
  denominator). The layer-2 scenarios cover the `wiki_fix`, `wiki_import`,
  and `wiki_wrapup` front ends beside the hub `wiki` skill, and
  `layer2/evals.json` stays the statement of extent. Mature, working.
- **`git_commit/`**: Pattern A. `script_tests/` implemented (31
  bundled-script scenarios, four of which run through an explicit
  `/bin/bash` to prove both scripts at the bash 3.2 floor: empty staged
  and unstaged diff lists, and a `set -u` abort that must exit non-zero
  while the EXIT trap is live, plus one scenario proving the eval
  runner's `stage()` stops on a failed or empty stage and one proving
  `grade.sh`'s straggler scan reads only its own job's `TMPDIR`). `evals/`
  holds nine behavioral evals with fixtures, run through `evals/run.py` on
  the default Cursor worker in the shared `tests/lib/eval_runner` pool with
  a deterministic `grade.sh`. See `evals/README.md`.
- **`git_checkout/`**: Pattern A. `script_tests/` implemented (14
  bundled-script scenarios over staged clones with real remotes, plus one
  proving the eval runner's `stage()` stops on a failed or empty stage and
  one proving no eval grades PASS on an inert worker).
  `evals/` holds seven behavioral evals over five fixtures, run through
  `evals/run.py` on the default Cursor worker in the shared
  `tests/lib/eval_runner` pool with a deterministic `grade.sh`. See
  `evals/README.md`.
- **`git_review/`**: Pattern A. `script_tests/` implemented (34
  bundled-script scenarios over staged clones with real remotes, plus the
  four plugin-meta lockstep checks, one scenario proving the eval runner's
  `stage()` stops on a failed or empty stage, one proving the suite-entry
  git-config pin against a non-ASCII path, and one proving no eval grades
  PASS on an inert worker): the ordered evidence collection, the two
  commit walks, the base-side versions of deleted files, the test merge, the
  head-against-its-upstream relationship the fast-forward decision rests on,
  the stub-`gh` thread and thread-comment pagination, the heading-range helper,
  the size profile (content-only line counts that equal numstat in range,
  uncommitted, and per-path-fallback modes; conflicted files of an unresolved
  merge counted, matched as generated, and listed like any other changed
  file; and the binary-path listing, which names a modified, added, deleted,
  conflicted, git-quoted, or space-holding binary, and a renamed or copied
  binary or generated file, by the path `git diff --name-only` prints, and
  classifies a renamed file as generated by its new path, so a file moved out
  of `vendor/` counts as first-party code; and the share, which counts a
  binary file under a generated path once), and the located secret-scan hits
  (file and new-side line, in range and uncommitted modes, including a
  conflicted path, an unborn branch, a run started in a subdirectory, a line
  only the index holds, an untracked file without a final newline, a path
  whose diff driver carries a textconv and an external command, a binary file
  read through its textconv driver and cited `(textconv)`, an untracked
  symlink recorded as its target path, a repository with `color.diff=always`
  and `diff.external` set, Compose map and list entries, unquoted YAML
  entries, Go `:=` declarations, and assignments to suffixed and camelCase key
  names such as `aws_secret_access_key`, `SECRET_KEY`, `apiKey`,
  `clientSecret`, `accessToken`, and `dbPassword` located as hits, keyword
  arguments on lines of their own, assignments whose names continue after a
  credential keyword such as `token_count` and `password_hash`, an English word
  ending in `key` such as `monkey`, subscript writes, values that open with
  `_`, `{`, or a backtick, JSON members named `key`, route and URL segments,
  Python type annotations, YAML tags, templated values, and Go expressions that
  draw no hit, and the per-path diff
  fallback with a non-ASCII path, with the manual fallback's extraction matched in range,
  uncommitted, per-path, and subdirectory runs, and its per-path retry keeping
  `unread_paths.txt` out of the working tree). Each manual-fallback block runs
  under bash and, when it is on `PATH`, under `zsh -f`, and a copy that names
  a variable `status` or `path` must fail the zsh run. `evals/` holds 48
  behavioral evals over 36 fixtures, run through `evals/run.py` on the
  default Cursor worker in the shared `tests/lib/eval_runner` pool with a
  deterministic `grade.sh`. Forge fixtures put a stub
  `gh` on `PATH` that serves fixture JSON and logs every call, so a run that
  posts nothing is provable. See `evals/README.md`.
- **`language_humanizer/`**: Pattern A, prose-only skill. The skill
  ships no scripts, so `script_tests/` covers the static contract
  (single-file directory, pseudo-XML lint, the description budget and its
  two router splits, dash-free prose, the named sections and fidelity
  rules, registration lockstep, and the eval runner's stop on a failed or
  empty stage), and `evals/test_grade.py` proves the grader passes a
  faithful rewrite and fails each lossy one; `run_all.sh` drives both. `evals/` runs 3 scenarios × a fixed 5-pass denominator,
  graded by a deterministic `grade.py` plus a refute-biased `judge.py`.
  Every pass and every judge call runs from an isolated root through
  `tests/lib/worker_isolation.py`, and the recorded measurement runs on
  `--vendor cursor`. No verdict cache: the repeated draws are the
  measurement.
- **`natural_language/`**: Pattern A, behavioral only (the subject is an
  output style, so there is no `script_tests/`). `run_all.sh` drives the
  deterministic surface: `evals/test_run.py` (the style-route preflight and
  the runner's stop on a failed or empty stage) and `evals/test_grade.py`
  (the grader's wrap-collapsed matching), neither of which starts a worker.
  2 scenarios × a fixed 5-pass denominator, graded by a deterministic
  `grade.py` plus a refute-biased `judge.py`. No verdict cache: the repeated
  draws are the measurement. Workers load the style through Claude
  output-style selection, so the runner defaults to Claude, stops with an
  error on `--vendor cursor`, and runs on Claude wherever a change needs it,
  with `--vendor claude` in the command.
- **`task/`**: Pattern A. The `task_*` family hub, holding three
  deterministic surfaces: `script_tests/run.sh` unit-tests the bundled
  `lint.py`, `discover_tasks.sh`, and `init_tasks.sh` (116 scenarios),
  `script_tests/contract_run.sh` asserts the family contract across the
  hub, its siblings, and the family agents, and `evals/test_run.py` checks
  that no eval grading the sandbox's whole `git status` declares an
  artefact the micro-deployment writes into the sandbox project, that
  the runner's `stage()` stops on a failed or empty stage, and that the
  parallel surface holds: `--workers` defaults to 4, the Approach serial
  nested-loop set is the three ids the task names, and `timing.json`
  keeps the fields it reads. A hermetic host-guard case there runs two real
  jobs through `tests/lib/eval_runner.run_jobs` against a temporary host
  mirror, proving overlapping sandbox-only jobs leave the host `tasks/` tree
  untouched and a planted newer host file carrying one eval's fixture name
  fails that eval's isolation check while an overlapping eval with other
  fixture names stays PASS.
  `run_all.sh` drives all three and aggregates their exit codes. `evals/`
  holds a behavioral eval per family member, run out-of-band via
  `evals/run.py`.
- **`task_create/`**: Pattern A. The skill drives the base `task` skill's
  scripts, covered under `task/script_tests/`, so `script_tests/run.sh` here
  tests the grader instead: each case stages an eval, installs a chosen task
  body, and reads one `evals/grade.sh` check's verdict. It also checks every
  fixture's git identity and the eval runner's stop on a failed or empty
  stage. `evals/test_run.py` pins the parallel surface: `--workers` defaults
  to 4, ids come from `evals.json` in file order, the run root is
  `tests/task_create/workspace`, `timing.json` carries the fields the
  measurement reads, and `_execute` dispatches jobs through
  `tests/lib/eval_runner.run_jobs`; a hermetic host-guard case runs two real
  jobs against a temporary host mirror and proves overlapping sandbox-only
  work leaves its `tasks/` tree untouched while a planted newer host file
  carrying one eval's fixture name fails that eval. There is no `run_all.sh`,
  so run `bash tests/task_create/script_tests/run.sh` and
  `python3 tests/task_create/evals/test_run.py` directly. Four
  staged evals over the base **Decide or label** rule and the `<prior_art>`
  Novel class as the create path applies them: `reconcile-recorded`
  (evidence-settled fork, no label), `labeled-why-open` (no tier settles it),
  `guardrail-bound-surface` (every path crosses a boundary), and
  `related-precedent-novel` (related prior-art covering none of the requested
  work classifies as Novel and writes the task with a Context cross-link).
  Grades the written task file and, for the Decide-or-label evals, the
  worker's captured response, since that rule obliges both.
- **`task_fix/`**: Pattern A. The skill drives the base `task` skill's
  scripts, covered under `task/script_tests/`, so `script_tests/run.sh` here
  tests the grader instead, grading staged fixtures against chosen responses,
  plus the eval runner's stop on a failed or empty stage. `evals/test_run.py`
  pins the parallel surface: `--workers` defaults to 4, ids come from
  `evals.json` in file order, the run root is `tests/task_fix/workspace`,
  `timing.json` carries the fields the measurement reads, and `_execute`
  dispatches jobs through `tests/lib/eval_runner.run_jobs`; it also checks the
  runner's stop on a failed or empty stage, and a hermetic host-guard case runs
  two real jobs against a temporary host mirror and proves overlapping
  sandbox-only work leaves its `tasks/` tree untouched while a planted newer
  host file carrying one eval's fixture name fails that eval. There is no
  `run_all.sh`, so run `bash tests/task_fix/script_tests/run.sh` and
  `python3 tests/task_fix/evals/test_run.py` directly. Four staged
  evals over the base `<lint>` **Repeated-link react protocol** as the inline
  `task_fix` path applies it: `regroup_live_skip_archived` (gather the live
  account, leave the archived body quiet), `regroup_state_and_edit_site` (a reference
  page's current state and its edit gather into one passage under one link),
  `surfaced_acceptance_contract` (the gathering would leave an Acceptance item
  nothing to measure), and `regroup_same_paragraph` (a repeat inside one
  paragraph is named again in plain text there). Grades the task file's bytes
  and the run's per-finding disposition line, since the protocol obliges both.
- **`task_auto_check/`**: Pattern A. `script_tests/` covers the static
  skill contract and the parallel runner, including its stop on a failed or
  empty stage; `evals/` drives the autonomous readiness loop over staged
  fixtures (repair-to-ready, frozen commitments, isolated re-gates, last-call
  citation refutation, the gate / verifier / drift stop conditions, and
  mechanical lint cleanup) through `run.py` on the default Cursor
  worker with a deterministic `grade.sh`. The deepest loop here, so `RUNBOOK.md` records
  the cheap-first fixture probe that keeps a fixture bug off the full run.
- **`git_auto_review/`**: Pattern A. `script_tests/` drives the five bundled
  scripts the skill ships (relay init with its staleness clear and marked
  pre-seed pairs, the ledger runner's exit and per-line contract, the round-1
  pre-fix artefacts `pre-fix.patch`, `pre-fix.untracked.tar`, and
  `pre-fix.ignored.manifest` and the once-only baseline pair, the scripted round diff (`run_round_diff.sh`)
  over the pre-fix state, and the Restore procedure reproducing the captured
  worktree with the index untouched) plus the static
  skill and agent contracts, the Makefile `.git_auto_review` prune, the
  shared isolation allowlist, and the eval runner's stop on a failed or empty
  stage through `tests/lib/check_stage_guard.py`. `evals/` holds behavioral evals over staged git
  fixtures, run through `evals/run.py` on the default Cursor worker with a
  deterministic `grade.sh`; its multi-round nested-loop stop evals run one job
  at a time after the isolated pool. See `evals/README.md`.
- **`guardrail_audit/`**: Pattern A, prose-only skill. `script_tests/`
  covers the static SKILL.md / registration contract and the eval runner's
  stop on a failed or empty stage, plus `sandbox_git_isolation.sh` (fixture
  git cannot commit into the host checkout) and `grader_response.sh`, which
  stages chosen responses through `grade.sh` to pin the `direction_target`
  softening check's PASS and FAIL directions; `evals/` has six
  staged fixtures (presence-gating, doc-vs-doc, doc-vs-code retrofit,
  declared-direction target (`direction_target`), grounded TESTING.md
  proposal, multi-project nature mismatch) with byte-identity grading and a `run.py` on the default
  Cursor worker.
- **`skill_doctor/`**: Pattern A. `script_tests/` cover
  `resolve_scope.py` (hub-with-`<family>` and prefix-only) and
  `discovery_safety.py` (risky sibling-description outlier,
  dual-audience gaps, both sides of the block-versus-warn severity
  line including a fixture per promised blocking class, and
  false-positive regression guards over real shipped description
  shapes), plus the static SKILL.md contract and the eval runner's stop on
  a failed or empty stage. `evals/` has six
  staged fixtures driven by `run.py` on the default Cursor worker with a
  deterministic `grade.sh`; `run_all.sh` drives only the script tests.
- **`agent_spinner/`**: Pattern A, bundled ledger. `script_tests/` covers the
  static contract (SKILL.md budgets and blocks, the six shape tags, the
  per-harness greps that must return nothing, the reference set, registration
  lockstep, the ledger's stdlib-only and read-only-git checks, and the eval
  runner's stop on a failed or empty stage), and `script_tests/ledger_run.sh`
  exercises the bundled `scripts/run_ledger.py` under the oldest and newest
  python3; `script_tests/grade_cases.sh` runs the real `evals/grade.sh` over
  11 committed report variants (15 pass/fail checks) for
  `explicit_spinner_on_family_job`; `evals/test_run.py` proves the runner's
  wiring against a stub worker; `evals/` holds every id in `evals.json` (49
  today). Each
  behavioural eval stages one behaviour and the `smoke_*` evals check the
  runner's modes, driven by `evals/run.py` on the default Cursor worker in
  the shared `tests/lib/eval_runner` pool at the default 4 workers, with a
  deterministic `grade.sh`. The runner withholds tools under its
  withheld-tool rule and brackets every eval with a per-eval owned-name
  host guard, so a sandbox escape fails the eval whose sandbox names it
  even while siblings overlap. See `evals/README.md` for the signal each
  eval uses and the `## Runner modes` section.
- **`git_refresh/`**: Pattern A. `script_tests/` covers the bundled
  `refresh_repo.sh` over staged repositories, plus two eval-harness
  scenarios: the runner's `stage()` stops on a failed or empty stage, and
  eval 3's grade reads the gated order from the helper log. `evals/` holds
  four behavioral evals with fixtures, run through `evals/run.py` on the
  default Cursor worker in the shared `tests/lib/eval_runner` pool with a
  logging shim around the deployed helper and a deterministic `grade.sh`. See `evals/README.md`.
- **`ai_instruction_writing/`**: Pattern A, script-only. The skill ships
  no bundled scripts, so `script_tests/` asserts its static prose
  contract instead.
- **`charter_guardrail/`**: Pattern A, script-only. `script_tests/run.sh`
  exercises the `charter_guardrail.sh` hook that protects `CHARTER.md`:
  its block and allow decisions for Claude, Codex, and Antigravity tool
  calls and for shell commands that read or write the charter, the
  `guardrail/charter-*` branch exception, and its behavior without `jq`.
  It also checks the hook registrations, the Codex deploy wiring, and how
  the docs and wiki describe Codex plugin-hook trust. No `run_all.sh`;
  run `script_tests/run.sh` directly.
- **`format_rust/`**: Pattern A, script-only. `script_tests/run.sh` greps
  SKILL.md and the plugin README for the error-versus-invariant model,
  panic discipline, and clippy wiring. No `run_all.sh`.
- **`update_changelog/`**: Pattern A, script-only. `script_tests/` covers
  the deterministic parts of the incremental day-grouping walk.
- **`deployment/`**: Pattern A, script-only, and the one harness that
  belongs to the deploy script rather than to a skill. These script tests
  execute the real deploy script, so they inherit its `jq`, `perl`, and
  `rsync` PATH gate. `script_tests/run.sh` covers the OpenCode, Antigravity,
  and bytecode-exclusion paths, the socket and FIFO backup copy, openrsync
  vanished-file versus permission exit 23, the startup gate, cleanup-only
  `--clear-backups` skipping that gate, scope-limited uninstall through a
  shared three-scope fixture (a scope flag limits removal to that scope, a
  scopeless run covers every scope, out-of-scope entries are reported and
  kept), and the `logged_path_scope` helper's per-target derivation;
  `script_tests/style_run.sh` covers output-style deployment and uninstall;
  `script_tests/hook_merge_run.sh` covers the entry-grain hook merge into a
  shared hook file, its dry-run report, the `@entries:` deploy-log manifest,
  the manifest uninstall, and the routing and documentation claims that keep
  the whole-key merge superseded; `script_tests/update_run.sh` covers the
  log-driven `--update` replay: restoring each recorded scope, one backup per
  covered global target root, project-scope isolation, dry-run immutability,
  the vanished-scope drop, foreign-checkout and orphan handling, scope and
  filter narrowing, and the help, Makefile, and documentation claims.
- **`trigger_evals/`**: a different axis from the rest, namely whether a
  skill's `description:` makes the agent load it on a realistic user message, on
  Claude and on Cursor. Driven by the local `run.py` wrapper, with hermetic unit
  tests under `script_tests/` for the baseline-regression detector, the
  deployed-versus-unavailable-versus-`--force-uuid` mode-selection guards, and
  the per-vendor deployed worker path.

## Grader mechanics

The durable grader-authoring rules live in `TESTING.md`
`## Test Design Principles`. This section records the harness-level shape those
rules take in the committed graders under `tests/`.

- **Property-named checks, every satisfying phrasing.** A check names the
  property under test and accepts every phrasing and placement that satisfies
  it. Where a rubric permits two repair shapes, the check is a disjunction over
  both shapes rather than a pin to one wording.
- **Wrap-collapsed matching.** Graders that match more than one word of prose
  expose a shared helper (`unwrapped` / `unwrapped_file`) that collapses hard
  wraps to spaces, and every such check reads through that helper.
- **Subject-anchored structured fields.** A check on a structured report field
  (for example a `verdict:` line) matches the record whose subject is the item
  under test (`verdict_line` / `verdict_is`), never a bare name appearing inside
  another record's prose. When either of two named owners may carry the verdict,
  the check is an either-side `verdict_is` disjunction.
- **Per-behaviour reporting.** An eval that asserts many independent behaviours
  prints PASS/FAIL per behaviour so one slip localises; the eval's overall exit
  status still fails when any behaviour fails.

## Adding a harness for a new skill

1. Create `tests/<skill_name>/` with Pattern A's layout.
2. Implement `script_tests/run.sh` first if the skill ships bundled
   scripts: cheap, deterministic, fast feedback on the mechanical
   surface. Stage a fresh sandbox per scenario; never operate on the
   host repo's working tree.
3. Author `evals/evals.json` and per-eval fixture `setup.sh` scripts
   for any skill-prose behavior that scripts can't verify (message
   format discipline, fallback discipline, user-prompting behavior,
   skill triggering). Run via skill-creator's `scripts.run_eval`.
