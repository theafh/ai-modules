---
description: Give the git_checkout and git_refresh harnesses the same sonnet-pinned eval runner the other Pattern A harnesses ship, so an eval sweep reaches their eleven behavioral evals.
scope: "local test harnesses"
created: 2026-09-05T02:10:57
updated: 2026-09-05T02:10:57
status: open
reported-by: Andreas Hoffmann
---

# Run the git_checkout and git_refresh behavioral evals from a runner

## Goal

`python3 tests/git_checkout/evals/run.py` and `python3 tests/git_refresh/evals/run.py`
each stage their fixtures, drive one sonnet-pinned worker per eval, grade the
result deterministically, and record a verdict in the shared cache, exactly as
the five runners already in the tree do. The user-visible outcome: a sweep that
runs every behavioral harness reaches all eleven of these evals and reports them
beside the rest, so a change to either skill is regression-checked instead of
being taken on trust.

## Context

Seven Pattern A harnesses define behavioral evals. Five of them ship
`evals/run.py` beside a `stage.sh` and a `grade.sh`: `tests/git_commit/`,
`tests/task/`, `tests/task_create/`, `tests/task_auto_check/`, and
`tests/git_review/`. Two more, `tests/guardrail_audit/` and
`tests/skill_doctor/`, ship the same shape. `tests/git_checkout/evals/` and `tests/git_refresh/evals/`
hold only `evals.json` and `fixtures/`. `tests/git_checkout/evals/README.md`
records the consequence in its own words, that no command executes a behavioral
eval and the model-runs-the-skill step is left to whoever is in the session;
`tests/git_refresh/evals/` carries no README at all.

Three costs follow from that gap. The evals never enter the verdict cache, so
they contribute nothing to the cache's regression signal. A skill edit cannot be
regression-checked against them without a person sitting through eleven manual
runs. And driving them by hand runs the skill under the host session's inherited
model, which the harness model policy in the tests tree's own operating guide
rules out: every skill under test is pinned to `claude-sonnet-4-6` so results do
not drift with the host session.

Measured on 2026-09-05 while running this repo's full eval sweep. Every other
behavioral harness ran from a command; these two could not, and their evals went
unexercised in a run that was meant to cover the repo.

Two skill tasks built these harnesses:
[the git_checkout skill task](ai-dev_git-checkout-skill.md) and
[the archived git_refresh skill task](archive/ai-dev_git-refresh-skill.md).
Each accepted the harness on the evals being *defined*, not on their being
runnable, so neither owns this work.

[The eval-cache granularity task](tests_eval-cache-key-granularity.md) governs
how `tests/lib/eval_cache.py` computes a key. This task consumes that helper
through `source_roots_for()` rather than changing it, so the two impose no order
on each other.

## Approach

Take `tests/git_commit/evals/run.py` as the reference implementation, since its
harness is the closest in shape: a small eval set, per-eval fixtures staged by
`setup.sh`, and a `grade.sh` that reads the post-run sandbox. Carry over its
structure rather than inventing a second one, so a future change to the shared
runner shape lands in one recognisable form across the tree.

For each of the two harnesses, add `evals/stage.sh` that stages one fixture and
prints `printf %q`-quoted `name=value` lines for the sandbox path, the skill
path, and the prompt; add `evals/grade.sh` as a `case` over eval id that asserts
the post-run repository state each eval's expectations name; and add
`evals/run.py` that imports `worker_env()` and `preflight_auth()` from
`tests/lib/worker_auth.py`, defaults `--model` to `claude-sonnet-4-6`, accepts
`--force` and `--no-cache`, and records verdicts through `tests/lib/eval_cache.py`
with `source_roots_for()` naming the skill directory under test.

Derive each `grade.sh` arm from the expectations already written in
`evals/evals.json`, and keep the arm asserting the property rather than a
phrasing: for `git_checkout` that means the branch HEAD ends on, the upstream it
tracks, and whether the worktree was left as found; for `git_refresh` that means
which local branches survive the run and which the gated follow-up left alone.

Write `tests/git_refresh/evals/README.md` covering the four evals and their
fixtures, matching what `tests/git_checkout/evals/README.md` already does for
its seven, and rewrite the passage in that existing README that describes the
evals as having no runner, since this task gives them one.

Register both runners in the tests tree's operating guide and its README:
add them to the model-policy table listing which worker each harness pins, to
the verdict-cache section listing which runners share the cache, and to the
worker-auth section listing which runners use the shared helper. Those three
passages enumerate the runners by name, so each grows by two entries rather
than being restated.

**Out of scope:** Adding behavioral evals beyond the eleven already defined in
the two `evals.json` files, which the standing repo rule on harness growth keeps
to its own session.

## Acceptance

`python3 tests/git_checkout/evals/run.py` with no arguments runs all seven evals
and prints a graded summary naming each eval id and its verdict, and
`python3 tests/git_refresh/evals/run.py` does the same for its four.

Re-running either command with unchanged inputs replays every verdict from the
cache and spawns no worker, and re-running with `--force` spawns a worker for
each eval and refreshes the stored verdict.

Each runner reports `claude-sonnet-4-6` as its worker model when no `--model` is
given, and each fails fast with the shared helper's remediation message when the
stored login is dead rather than recording a failed verdict per eval.

`tests/git_refresh/evals/README.md` exists and documents each of the four evals
against the fixture that stages it.

The tests tree's operating guide lists both runners in its model-policy,
verdict-cache, and worker-auth passages, and neither its inventory nor
`tests/README.md` still describes these evals as reaching only the script
surface.

`make lint` passes.
