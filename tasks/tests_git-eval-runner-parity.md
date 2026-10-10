---
description: Give git_checkout and git_refresh the same vendor-aware Pattern A eval runner the other harnesses ship, so an eval sweep reaches their behavioral evals.
scope: "local test harnesses"
created: 2026-09-05T02:10:57
updated: 2026-10-09T17:46:37
status: open
reported-by: Andreas Hoffmann
---

# Run the git_checkout and git_refresh behavioral evals from a runner

## Goal

`python3 tests/git_checkout/evals/run.py` and `python3 tests/git_refresh/evals/run.py`
each stage their fixtures, drive one vendor-resolved print-mode worker per eval,
grade the result deterministically, and record a verdict in the shared cache,
exactly as every other Pattern A harness that already ships `evals/run.py` does.
The user-visible outcome: a sweep that runs every behavioral harness reaches
these evals and reports them beside the rest, so a change to either skill is
regression-checked instead of being taken on trust.

## Context

Every Pattern A harness under `tests/` that already defines behavioral evals and
ships `evals/run.py` shares `tests/lib/vendor.py` and accepts
`--vendor {claude,cursor}` (default `cursor` with worker model `auto`;
`--vendor claude` with `sonnet` is a run the operator asks for). `tests/git_checkout/evals/` and
`tests/git_refresh/evals/` still hold only `evals.json` and `fixtures/`.
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

[The eval-cache granularity task](tests_eval-cache-key-granularity.md) governs
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
runners must not enter the tree as a new sequential copy. Take the git_commit
runner as the shape reference for the harness-specific parts: a small eval
set, per-eval fixtures staged by `setup.sh`, a `grade.sh` that reads the
post-run sandbox, and vendor and cache handling through `tests/lib/vendor.py`
and `tests/lib/eval_cache.py`.

For each of the two harnesses, add `evals/stage.sh` that stages one fixture and
prints `printf %q`-quoted `name=value` lines for the sandbox path and the
prompt; add `evals/grade.sh` as a `case` over eval id that asserts
the post-run repository state each eval's expectations name; and add
`evals/run.py` that calls `vendor.add_vendor_arguments` and `vendor.resolve`,
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

Write `tests/git_refresh/evals/README.md` covering the four evals and their
fixtures, matching what `tests/git_checkout/evals/README.md` already does for
its seven, and rewrite the passage in that existing README that describes the
evals as having no runner, since this task gives them one.

Register both runners in the tests tree's operating guides and inventory:
rewrite the model-policy / vendor, verdict-cache, and worker-auth passages in
`tests/CLAUDE.md` and `tests/AGENTS.md` so each lists the new runners beside the
existing ones, and rewrite any inventory row in `tests/README.md` that still
describes these evals as reaching only the script surface.

**Out of scope:** Adding behavioral evals beyond those already defined in
the two `evals.json` files, which the standing repo rule on harness growth keeps
to its own session.

## Acceptance

- `python3 tests/git_checkout/evals/run.py` with no eval-id
  arguments runs every eval in that harness's `evals.json` and prints a graded
  summary naming each eval id and its verdict, and
  `python3 tests/git_refresh/evals/run.py` does the same for its
  evals. Both commands accept `--workers` defaulting to 4.
- Re-running either command with unchanged inputs replays every verdict from the
  cache and spawns no worker, and re-running with `--force` spawns a worker for
  each eval and refreshes the stored verdict.
- Without `--vendor` and `--model`, each runner resolves to Cursor worker model
  `auto`. With `--vendor claude` and no `--model`, each resolves to Claude
  worker model `sonnet`. Each fails fast with the shared vendor
  preflight's remediation message when the chosen vendor's login is dead rather
  than recording a failed verdict per eval.
- `tests/git_refresh/evals/README.md` exists and documents each of that harness's
  evals against the fixture that stages it.
- `tests/CLAUDE.md` and `tests/AGENTS.md` list both runners in their vendor /
  model-policy, verdict-cache, and worker-auth passages, and neither those guides
  nor `tests/README.md` still describes these evals as reaching only the script
  surface.
