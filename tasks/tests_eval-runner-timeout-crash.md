---
description: Re-measure the task_auto_check eval timing band against the current loop, set its default --timeout above the re-measured ceiling, and update the RUNBOOK and run.py help to match.
scope: "local test harnesses"
created: 2026-09-05T03:06:08
updated: 2026-09-05T21:33:57
status: open
reported-by: Andreas Hoffmann
---

# Re-measure the task_auto_check eval timing band and lift its default timeout above it

## Goal

The `task_auto_check` behavioral harness records a timing band measured against
the loop as it runs today, and its default `--timeout` sits above that band's
upper end, so the run the default performs is one that completes rather than one
the deadline cuts off. Both places that state the band, the timing note in
`tests/task_auto_check/RUNBOOK.md` and the `--timeout` help in
`tests/task_auto_check/evals/run.py`, carry the same re-measured figure.

The user-visible outcome: an operator who runs this harness at its default sees
graded verdicts rather than `worker rc=-1` cutoffs, and the documented band
matches what the evals actually take.

## Context

This task began life covering two threads, and the first is already fixed in the
working tree. The shared helper `as_text()` in `tests/lib/worker_io.py` now
decodes every runner's timeout-path output, so a single eval that overruns its
deadline is recorded as a failed eval and the sweep continues. Nine runners were
wired to it, the local copy in `tests/task_auto_check/evals/run.py` was removed
in favour of the shared one, the `tests/task/evals/run.py` default was raised to
1800 with its README timing notes rewritten, and a section documenting the helper
was added to `tests/CLAUDE.md`. That crash fix is what makes a long measurement
run safe to do at all: a repair-class eval that overruns no longer aborts the
evals queued behind it, so the sampling below can proceed to completion.

The one remaining thread is the timing band, which is stale.
`tests/task_auto_check/RUNBOOK.md` states the repair-class scenarios "take
~900 to 1500s solo" and tells the operator to "pass `--timeout 1800` or more", and
the `--timeout` help in `tests/task_auto_check/evals/run.py` repeats "runs
~900-1500s solo". The default is already 1800. Yet on 2026-09-05 three evals run
solo and sequentially each reached the 1800-second deadline: `repair_to_ready`
and `guard_rebaseline_after_gate` were cut off mid-loop, while
`mechanical_lint_ready`, which runs no repair loop, finished. The grading
evidence showed the skill working rather than stuck, since `repair_to_ready`
passed all six of its checks on the state it had reached when the deadline cut it
off, and `guard_rebaseline_after_gate` failed only the check that the task
reaches `ready`, the stamp the loop had not got to yet. So the loop now runs
longer than both the recorded band and the default, and the two need
re-measuring against a loop that completes.

The RUNBOOK's repair-class set is `repair_to_ready`,
`guard_rebaseline_after_gate`, `interaction_scan_surfaces`, and
`immediate_ready_citations_overturn`, and its cost-discipline section requires
running them solo and sequentially, because two nested loops in parallel contend
for the model and both slow down.

## Approach

Run each repair-class eval solo and sequentially, with `--timeout` set to a
ceiling well above 1800 so none is cut off, and capture `duration_s` from each
`timing.json` at `claude_rc` 0. Take the band as the range across those
completing runs, and set the harness default above the observed upper end with
the same headroom the default already keeps above the old band rather than
sitting on its floor. Rewrite the band in place in both
`tests/task_auto_check/RUNBOOK.md` and the `--timeout` help in
`tests/task_auto_check/evals/run.py` so one figure governs both, superseding the
stale "900 to 1500s" wording rather than leaving a second figure beside it.

The recorded measurement is the deliverable, so the durations and the band drive
the default rather than the reverse. Where the completing runs show the loop does
not in fact exceed the current 1800 default, keep the default at 1800 and record
the re-measured band that shows why.

**Out of scope:** Narrowing the cache key, which
[the eval-cache granularity task](tests_eval-cache-key-granularity.md) owns;
editing this harness's `run.py` still invalidates its cached verdicts until that
task lands.

## Acceptance

A sampled run measures each repair-class eval (`repair_to_ready`,
`guard_rebaseline_after_gate`, `interaction_scan_surfaces`,
`immediate_ready_citations_overturn`) solo and sequentially at a `--timeout`
ceiling high enough that none is cut off. Each measured run reaches a graded
verdict with `claude_rc` of `0` and a recorded `duration_s`, with no `-1` cutoff
among them, and each eval is run at least twice so the band rests on more than
one draw per eval.

The observed `duration_s` values and the band derived from them, its lower and
upper end, are recorded in `tests/task_auto_check/RUNBOOK.md`, taken from the
completing runs above rather than from any run the deadline cut off.

`tests/task_auto_check/RUNBOOK.md` no longer states the `~900 to 1500s` band or
instructs passing `--timeout 1800`; the superseding passage states the
re-measured band and the current default.

The `--timeout` help in `tests/task_auto_check/evals/run.py` no longer states
`~900-1500s`; it states the same re-measured band as the RUNBOOK, and the two
agree on the figure.

The harness default `--timeout` in `tests/task_auto_check/evals/run.py` sits
above the re-measured band's upper end. When the sampled completing runs stay at
or below 1800s, the default stays 1800 and the RUNBOOK records that the
re-measurement confirmed it; otherwise the default is raised above the observed
ceiling.
