---
description: Give git_checkout and git_refresh vendor-aware Pattern A eval runners that import the shared eval_runner helper, so an eval sweep reaches their behavioral evals.
scope: "local test harnesses"
created: 2026-09-05T02:10:57
updated: 2026-10-14T22:04:07
status: ready
reported-by: Andreas Hoffmann
---

# Run the git_checkout and git_refresh behavioral evals from a runner

## Goal

`python3 tests/git_checkout/evals/run.py` and `python3 tests/git_refresh/evals/run.py`
each stage their fixtures, drive one vendor-resolved print-mode worker per eval,
grade the result deterministically, and record a verdict in the shared cache,
as vendor-aware Pattern A runners that import the shared `tests/lib/eval_runner.py`
helper — the shape the parallel-conversion siblings aim at, not a sequential copy
of the `evals/run.py` files that already ship.
The user-visible outcome: a sweep that runs every behavioral harness reaches
these evals and reports them beside the rest, so a change to either skill is
regression-checked instead of being taken on trust.

## Context

Every Pattern A harness under `tests/` that already defines behavioral evals and
ships `evals/run.py` shares `tests/lib/vendor.py` and accepts
`--vendor {claude,cursor}` (default `cursor` with worker model `auto`;
`--vendor claude` with `sonnet` is a run the operator asks for). `tests/git_checkout/evals/` holds `evals.json`, `fixtures/`, and
`evals/README.md`; `tests/git_refresh/evals/` still holds only `evals.json`
and `fixtures/`.
`tests/git_checkout/evals/README.md` records the consequence in its own words,
that no command executes a behavioral eval and the model-runs-the-skill step is
left to whoever is in the session; `tests/git_refresh/evals/` carries no README
at all.

Three costs follow from that gap. The evals never enter the verdict cache, so
they contribute nothing to the cache's regression signal. A skill edit cannot be
regression-checked against them without a person sitting through every manual
run. And driving them by hand runs the skill under the host session's inherited
model, which the harness model policy in `tests/CLAUDE.md` / `tests/AGENTS.md`
rules out: the worker is pinned through `--vendor` defaults (`sonnet` / `auto`),
not a dated model id and not the host session's model.

Measured on 2026-09-05 while running this repo's full eval sweep. Every other
behavioral harness ran from a command; these two could not, and their evals went
unexercised in a run that was meant to cover the repo.

Two skill tasks built these harnesses:
[the git_checkout skill task](archive/ai-dev_git-checkout-skill.md) and
[the archived git_refresh skill task](archive/ai-dev_git-refresh-skill.md).
Each accepted the harness on the evals being *defined*, not on their being
runnable, so neither owns this work.

[The eval-cache granularity task](archive/tests_eval-cache-key-granularity.md) governs
how `tests/lib/eval_cache.py` computes a key. This task consumes that helper
through `source_roots_for()` rather than changing it, so the two impose no order
on each other.

[The shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md)
is the helper both new runners import so they do not land as another sequential
copy of `tests/git_commit/evals/run.py`.

## Approach

Both new `evals/run.py` files import that helper, `tests/lib/eval_runner.py`,
for the job pool with `--workers` defaulting to
`vendor.DEFAULT_PARALLEL_WORKERS` (4) and a per-job `TMPDIR`, because these
runners must not enter the tree as a new sequential copy. Resolve each
harness's run-artifact root through `eval_runner.resolve_workspace` so
`timing.json` and sibling pass artefacts land under `tests/<skill>/workspace`,
not under `evals/workspace`. Take the git_commit
runner as the shape reference for the harness-specific parts: a small eval
set, per-eval fixtures staged by `setup.sh`, a `grade.sh` that reads the
post-run sandbox, and vendor and cache handling through `tests/lib/vendor.py`
and `tests/lib/eval_cache.py`.

For each of the two harnesses, add `evals/stage.sh` that stages one fixture and
prints `printf %q`-quoted `name=value` lines for the sandbox path and the
prompt; add `evals/grade.sh` as a `case` over eval id that asserts
the post-run repository state each eval's expectations name; and add
`evals/run.py` that takes each pass's sandbox root from `worker_isolation.create_sandbox_root` (standing testing rule: stage a sandbox per scenario), calls `vendor.add_vendor_arguments` and `vendor.resolve`,
preflights through `micro_deploy.preflight_auth`, micro-deploys the skill under
test per pass through `micro_deploy.micro_deploy`, runs the worker through
`micro_deploy.run_worker`, records `artefacts_read_from_micro_deployment` in
each pass's `timing.json`, accepts `--force` and `--no-cache`, and records
verdicts through `tests/lib/eval_cache.py`, with one artefact declaration
feeding both `--only` and `source_roots_for()`. Keep the vendor defaults that `vendor.py` already defines: Claude
worker model `sonnet`, Cursor worker model `auto`. Do not pin a dated Claude
model id.

Derive each `grade.sh` arm from the expectations already written in
`evals/evals.json`, and keep the arm asserting the property rather than a
phrasing: for `git_checkout` that means the branch HEAD ends on, the upstream it
tracks, and whether the worktree was left as found; for `git_refresh` that means
which local branches survive the run and which the gated follow-up left alone.

Write `tests/git_refresh/evals/README.md` covering every eval in that harness's
`evals.json` and the fixture that stages it, matching the existing shape of
`tests/git_checkout/evals/README.md`, and rewrite the passage in that existing
README that describes the evals as having no runner, since this task gives them
one.

Rewrite `README.md`, `RUNBOOK.md`, and `run_all.sh` under both
`tests/git_checkout/` and `tests/git_refresh/` so each names
`python3 tests/<harness>/evals/run.py` as the behavioral runner and no
longer describes those evals as a session-level skill-creator or
operator-driven workflow. Keep each `run_all.sh` as the script-tests
entrypoint; rewrite its help text and trailing note in place so they
point at that runner instead of claiming the evals have no CLI path.

Register both runners in the tests tree's inventory and Parallel workers
passages: rewrite the `git_checkout/` and `git_refresh/` rows under
`## What's here` in `tests/CLAUDE.md` (the table `tests/AGENTS.md` points at)
so each names `evals/run.py` as the behavioral runner rather than
operator-driven or runner-less evals; rewrite the Parallel workers inventories
(`### Parallel workers: default 4 only where each job has its own sandbox` in
`tests/CLAUDE.md` and `### Parallel workers` in `tests/AGENTS.md`) in place so
both name `tests/git_checkout/evals/run.py` and
`tests/git_refresh/evals/run.py` as Pattern A runners that import
`tests/lib/eval_runner` and keep both off the Pattern A sequential-until-conversion
list; and rewrite any inventory row in `tests/README.md` that still describes
these evals as reaching only the script surface, as operator-driven, or as
shipping no runner.

**Out of scope:** Adding behavioral evals beyond those already defined in
the two `evals.json` files, which the standing repo rule on harness growth keeps
to its own session.

## Acceptance

- `python3 tests/git_checkout/evals/run.py` with no eval-id
  arguments runs every eval in that harness's `evals.json` and prints a graded
  summary naming each eval id and its verdict, and
  `python3 tests/git_refresh/evals/run.py` does the same for its
  evals. Both commands accept `--workers` defaulting to 4.
- Each of `tests/git_checkout/evals/run.py` and `tests/git_refresh/evals/run.py`
  imports `tests/lib/eval_runner.py`, registers `--workers` through
  `eval_runner.add_workers_argument`, and drives its job pool through
  `eval_runner.run_jobs`, so each job receives that helper's per-job `TMPDIR`
  (`rg -n 'run_jobs|add_workers_argument' tests/git_checkout/evals/run.py
  tests/git_refresh/evals/run.py` lists both call sites in each file).
- Both `tests/git_checkout/evals/run.py` and `tests/git_refresh/evals/run.py`
  call `worker_isolation.create_sandbox_root` for each pass's sandbox root
  (`rg -n 'create_sandbox_root' tests/git_checkout/evals/run.py
  tests/git_refresh/evals/run.py` lists a call site in each file).
- Each of `tests/git_checkout/evals/stage.sh` and `tests/git_refresh/evals/stage.sh` exists; for every eval id in that harness's `evals.json`, invoking the script with that id prints `printf %q`-quoted `name=value` lines that name the sandbox path and the prompt.
- `tests/git_checkout/evals/grade.sh` has one `case` arm per eval id in `tests/git_checkout/evals/evals.json`, and each arm asserts every expectation that eval lists that is observable from the post-run repository filesystem (branch tip, upstream when named, symbolic HEAD when required, presence or absence of named local branches, and uncommitted worktree content when named); expectations that speak only about the worker response or which helper was invoked stay out of `grade.sh`.
- `tests/git_refresh/evals/grade.sh` has one `case` arm per eval id in `tests/git_refresh/evals/evals.json`, and each arm asserts every expectation that eval lists that is observable from the post-run repository filesystem (default-branch tip after fast-forward when named, which local branches remain or were deleted after the default run and after any gated follow-up, and uncommitted worktree content when named); expectations that speak only about the worker response or which helper was invoked stay out of `grade.sh`.
- Re-running either command with unchanged inputs replays every verdict from the
  cache and spawns no worker, re-running with `--force` spawns a worker for
  each eval and refreshes the stored verdict, and re-running with `--no-cache`
  spawns a worker for each eval while leaving every stored verdict unchanged.
- After a fresh (non-cache-replay) pass of either runner, each evaluated
  pass's `timing.json` under the workspace root
  `eval_runner.resolve_workspace` returns for that harness
  (`tests/git_checkout/workspace` and `tests/git_refresh/workspace`)
  carries the key `artefacts_read_from_micro_deployment`.
- In each of `tests/git_checkout/evals/run.py` and `tests/git_refresh/evals/run.py`,
  one artefact declaration (`ARTEFACTS` or `artefacts_for`) is the sole list both
  the micro-deploy call and `source_roots_for()` consume, so `--only` filtering
  and cache-key hashing share that same declaration.
- Without `--vendor` and `--model`, each runner resolves to Cursor worker model
  `auto`. With `--vendor claude` and no `--model`, each resolves to Claude
  worker model `sonnet`. Each fails fast with the shared vendor
  preflight's remediation message when the chosen vendor's login is dead rather
  than recording a failed verdict per eval.
- `tests/git_refresh/evals/README.md` exists and documents each of that harness's
  evals against the fixture that stages it.
- `tests/git_checkout/evals/README.md` no longer claims that no command executes a behavioral eval or that the model-runs-the-skill step is left to the session; that prior passage is rewritten so the README's canonical run instruction is `python3 tests/git_checkout/evals/run.py`.
- Under each of `tests/git_checkout/` and `tests/git_refresh/`,
  `README.md`, `RUNBOOK.md`, and `run_all.sh` name that harness's
  `evals/run.py` as the way to run the behavioral evals, and none of
  those six files still describe those evals as a session-level
  skill-creator workflow, an operator-driven session, or as having no
  runner CLI.
- Each of `tests/git_checkout/run_all.sh` and `tests/git_refresh/run_all.sh` invokes only `"$SCRIPT_DIR/script_tests/run.sh"` as its test runner and points at `evals/run.py` from its `--help` usage text and trailing note only (`rg -n 'script_tests/run\.sh' tests/git_checkout/run_all.sh tests/git_refresh/run_all.sh` lists that invocation in each file; `rg -n 'evals/run\.py' tests/git_checkout/run_all.sh tests/git_refresh/run_all.sh` lists at least one match in each file, every match lying inside the `--help` usage text or the trailing note, with no executable call of that runner).
- In `tests/CLAUDE.md`, the `## What's here` rows for `git_checkout/` and
  `git_refresh/` name each harness's `evals/run.py` as the behavioral runner
  (neither still describes those evals as operator-driven or as shipping no
  runner); the Parallel workers passages in `tests/CLAUDE.md` and
  `tests/AGENTS.md` name both `tests/git_checkout/evals/run.py` and
  `tests/git_refresh/evals/run.py` as `eval_runner` consumers and neither
  harness appears on the Pattern A sequential-until-conversion list; and
  `tests/README.md` no longer describes either harness's evals as reaching
  only the script surface, as operator-driven, or as shipping no runner.
