---
description: "Wire the shared tests/lib unit tests and every harness's deterministic surface into one runnable gate, so no suite is reachable only by remembering its path."
scope: "local test harnesses"
created: 2026-10-30T23:33:51
updated: 2026-10-30T23:33:51
status: open
reported-by: Andreas Hoffmann
---

# Give the test tree one runnable deterministic gate

## Goal

One command runs every deterministic test surface in the repo and reports a
single pass or fail, so a suite cannot silently stop running because nobody
remembered its path. Today the shared helpers under `tests/lib/` carry 597
assertions that no entrypoint invokes, and seven harnesses have no
`run_all.sh`, so their deterministic tests run only when an operator types the
exact `script_tests/run.sh` path.

The user-visible outcome: a documented command — reachable from `make` and
named in `TESTING.md` — runs the whole deterministic surface, and its summary
names each surface it covered, so a missing or skipped suite is visible rather
than absent.

## Context

`TESTING.md` `## Running Tests` documents `bash tests/<skill>/run_all.sh` and
`bash tests/<skill>/script_tests/run.sh` per harness but names no aggregate
entrypoint, and the `Makefile` has no `test` target: `make help` lists `help`,
`deploy`, `global`, `install`, `uninstall`, `clean`, `lint`, `fix`, `fix-md`
and nothing else. `AGENTS.md`'s **Regression test harnesses** section says
"run the deterministic surfaces unless they widen scope" and then names the
per-harness paths, so the operator assembles the run set by hand each time.

**The shared lib tests are unreachable.** `tests/lib/` holds eight test files
with real coverage — `test_eval_runner.py` (64 checks), `test_eval_cache.py`
(226), `test_micro_deploy.py` (169), `test_vendor.py` (40),
`test_worker_isolation.py` (51), `test_worker_io.py` (12),
`test_host_tasks_guard.sh` (4), `test_repeated_link_disposition.sh` (31) — and
all 597 pass. Nothing invokes them as a set. `tests/AGENTS.md` and
`tests/CLAUDE.md` each name one file's command in passing
(`python3 tests/lib/test_eval_runner.py`), and `tests/git_auto_review/script_tests/run.sh`
greps `test_worker_isolation.py` as text rather than running it. An edit that
breaks `eval_cache` or `micro_deploy` — the two largest helpers, and the two
every behavioral runner depends on — stays invisible until some behavioral eval
misbehaves.

**Seven harnesses have no `run_all.sh`.** `charter_guardrail`, `format_rust`,
`guardrail_audit`, `natural_language`, `task_create`, `task_fix`, and
`trigger_evals` ship `script_tests/run.sh` (or, for `natural_language`,
`evals/test_run.py` and `evals/test_grade.py`) but no entrypoint, so the
documented `bash tests/<skill>/run_all.sh` form does not reach them. `TESTING.md`
covers this with the parenthetical "the same, where no `run_all.sh` exists",
which leaves the operator to know which form each harness needs.

**Deterministic surfaces exist outside `script_tests/`.** `natural_language`
keeps its runner and grader tests in `evals/test_run.py` and
`evals/test_grade.py`; `task` drives `script_tests/run.sh`,
`script_tests/contract_run.sh`, and `evals/test_run.py` from its `run_all.sh`;
`agent_spinner` keeps `trigger_overlap.py` as a standalone helper. A single gate
has to reach all three shapes, not only `script_tests/run.sh`.

**Runtime is acceptable.** Measured on 2026-10-30, every suite together is
about 380 seconds wall clock, dominated by `skill_doctor` (158s),
`git_review` (78s), and `deployment` (30s). `skill_doctor`'s cost is its
fourteen whole-repo `resolve_scope.py` invocations, which is a separate
optimization this task does not take.

## Approach

Add one aggregate entrypoint plus a thin `make` target, and make the run set
derived rather than listed.

1. **Add `tests/run_all.sh`.** Discover the harness directories under `tests/`
   at run time rather than enumerating them, and for each one run whatever
   deterministic surface it carries: `run_all.sh` when present,
   `script_tests/run.sh` otherwise, plus `evals/test_run.py` and
   `evals/test_grade.py` when a harness carries them and no `script_tests/`
   covers them. Run `tests/lib/`'s unit tests as one more surface. Print a
   per-surface pass/fail line and a final tally, and exit non-zero when any
   surface fails. Accept `--surface <name>` to narrow the run and `--list` to
   print the discovered set.
2. **Add a `test` target to the `Makefile`** that invokes it, listed in
   `make help`, and documented in `TESTING.md` `## Running Tests` as the one
   command that runs the deterministic surface. Keep the per-harness forms
   documented beside it, since a scoped run stays useful.
3. **Give the seven `run_all.sh`-less harnesses an entrypoint** where the
   harness has more than one deterministic file, so the per-harness form works
   uniformly; a harness with exactly one `script_tests/run.sh` needs none and
   the aggregate gate reaches it anyway.
4. **Add a coverage assertion.** `tests/run_all.sh --list` must name every
   harness directory and `tests/lib/`, and a scenario in
   `tests/lib/test_eval_runner.py` or a small new `tests/lib/` test fails when a
   harness directory exists on disk but is absent from the discovered set. That
   is what stops the next harness from joining the tree unreachable.

**Out of scope:** Speeding up `skill_doctor`'s fourteen whole-repo
invocations. Wiring behavioral evals into the aggregate, which stay opt-in per
`TESTING.md` `## Coverage Expectations`. Parallelizing the deterministic suites,
which run fast enough serially at the measured total.

**Landing order.** This task lands after [the hermetic-gate
task](tests_deterministic-gate-hermetic.md), because Acceptance requires
`bash tests/run_all.sh` to exit zero on a clean checkout and that task is what
makes `skill_doctor` and `git_review` green. Landing this one first is still
useful — the aggregate will report the two known-red suites as red — but the
zero-exit line is only reachable afterwards. The two tasks touch disjoint
files: the hermetic task edits `skill_discovery.py` and `git_review`'s
scenarios, and this one adds `tests/run_all.sh` and a `Makefile` target.

## Acceptance

- `tests/run_all.sh` exists, is executable, and `bash tests/run_all.sh` runs
  every deterministic surface in the tree, printing one line per surface and a
  final tally. It exits zero on a clean checkout once the hermetic-gate task has
  landed; before that, the same run exits non-zero and names `skill_doctor` and
  `git_review` as the red surfaces, so a red run names the failing surface
  rather than only the tally.
- `bash tests/run_all.sh --list` names every directory under `tests/` that
  carries a deterministic test file, and `tests/lib/`, and names no directory
  that does not.
- `make test` runs the aggregate and appears in `make help`.
- The aggregate run includes the eight `tests/lib/` unit tests as its own
  surface, and a deliberately broken assertion in any one of them makes
  `bash tests/run_all.sh` exit non-zero.
- A harness directory created under `tests/` with a `script_tests/run.sh` and
  no other registration is picked up by `bash tests/run_all.sh --list` without
  editing the script, and a scenario fails when a harness on disk is missing
  from the discovered set.
- `TESTING.md` `## Running Tests` names `make test` / `bash tests/run_all.sh`
  as the one command that runs the deterministic surface, with the per-harness
  forms kept beside it as the scoped alternative, so one canonical aggregate
  statement exists and the per-harness block reads as the scoped subset.
- `tests/AGENTS.md` and `tests/CLAUDE.md` both name the aggregate entrypoint in
  lockstep, and both state that `tests/lib/`'s unit tests run as part of it.
- `make lint` passes.
