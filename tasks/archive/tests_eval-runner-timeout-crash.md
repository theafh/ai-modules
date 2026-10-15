---
description: Re-measure task_auto_check eval band, set default --timeout above it, sync RUNBOOK/run.py/CLAUDE.md band surfaces, keep per-eval ceilings via evals.json and RUNBOOK table.
scope: "local test harnesses"
created: 2026-09-05T03:06:08
updated: 2026-10-13T10:59:58
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Re-measure the task_auto_check eval timing band and lift its default timeout above it

## Goal

The `task_auto_check` behavioral harness records a timing band measured against
the loop as it runs today, and its default `--timeout` follows the Acceptance
rule that sets that default from the re-measured band, so the run the default
performs is one that completes rather than one the deadline cuts off. Every surface that states the band — every statement of the band in
`tests/task_auto_check/RUNBOOK.md`, the `--timeout` help in
`tests/task_auto_check/evals/run.py`, and the cheap-first passage in
`tests/CLAUDE.md` under `### Cheap-first: probe an LLM-eval fixture before paying for the full loop` — carries the same re-measured figure.

The user-visible outcome: an operator who runs this harness at its default sees
graded verdicts rather than worker cutoffs, and the documented band matches what
the evals actually take.

## Context

This task began life covering two threads, and the first is already fixed in the
working tree. The shared helper `as_text()` in `tests/lib/worker_io.py` now
decodes every runner's timeout-path output, so a single eval that overruns its
deadline is recorded as a failed eval and the sweep continues. The
`tests/task_auto_check/evals/run.py` runner is vendor-aware through
`tests/lib/vendor.py`, writes both `worker_rc` and `claude_rc` in `timing.json`,
and the shared timeout-path decode is what makes a long measurement run safe to
do at all: a repair-class eval that overruns no longer aborts the evals queued
behind it, so the sampling below can proceed to completion.

The one remaining thread is the timing band, which is stale.
`tests/task_auto_check/RUNBOOK.md` states the repair-class scenarios "take
~900 to 1500s solo", tells the operator to "pass `--timeout 1800` or more",
and still says "since the default 900 cuts many of them off", and the
`--timeout` help in `tests/task_auto_check/evals/run.py` repeats "runs
~900-1500s solo". The runner's default is already 1800. Yet on 2026-09-05 three evals run
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
`relay_by_path`, `stray_hunk_reverted`,
`guard_rebaseline_after_gate`, `interaction_scan_surfaces`, and
`immediate_ready_citations_overturn`, and its cost-discipline section requires
running them solo and sequentially, because two nested loops in parallel contend
for the model and both slow down. `TESTING.md` makes Cursor, the default
vendor, the worker for behavioral runs, so re-measure on it. If a Cursor sample
cannot complete the loop, record why in the RUNBOOK and ask the operator for a
Claude sample, since a Claude run that no Claude-specific feature needs waits
for the operator's request.

## Approach

Run each repair-class eval solo and sequentially on the default vendor, invoking each sample with `--force` or `--no-cache` so `run_one` does not return on a cache hit and replay a prior `duration_s`. The effective worker ceiling for each eval is that eval's `evals.json` `"timeout"` when present, else the CLI `--timeout`; raise whichever applies until every sampled run completes, and capture `duration_s` from each `timing.json` at `worker_rc` 0 (the file also writes `claude_rc` as the same value), taking that duration from the live completing worker for that sample. Take the band as the range across those
completing runs, and set the harness default from that band under the Acceptance
rule for the default. Rewrite the band in place at every site that states it: the operational-caveats
paragraph in `tests/task_auto_check/RUNBOOK.md` (`take ~900 to 1500s solo`), the
cost-discipline fixture-validate bullet in the same file (`via a 15 to 25 min
repair-loop timeout`), the cost-discipline sequential-run bullet
(`solo, each finishes in ~900 to 1500s`), the `--timeout` help in
`tests/task_auto_check/evals/run.py`, and the cheap-first passage in
`tests/CLAUDE.md` under `### Cheap-first: probe an LLM-eval fixture before paying for the full loop` (`~15 to 25 min per run` and `costs 15 to 25`), so one figure governs every site,
superseding the stale seconds and minutes band wording rather than leaving a
second figure beside it. Rewrite each minutes site to the re-measured range in minutes (the same figure
the seconds sites carry, expressed in minutes).
Name the vendor used for the measurement in the RUNBOOK note.

The recorded measurement is the deliverable, so the durations and the band drive
the default rather than the reverse.

For each measured repair-class eval, apply the Acceptance rule for that eval's post-change effective worker ceiling.

**Out of scope:** Narrowing the cache key, which
[the eval-cache granularity task](tests_eval-cache-key-granularity.md) owns;
editing this harness's `run.py` still invalidates its cached verdicts until that
task lands. Replacing a minutes-site band statement with a vendor-neutral
full-repair-loop contrast that omits the re-measured figure is rejected; every
named minutes site states that figure in minutes.

## Acceptance

A sampled run measures each repair-class eval (`repair_to_ready`,
`relay_by_path`, `stray_hunk_reverted`,
`guard_rebaseline_after_gate`, `interaction_scan_surfaces`,
`immediate_ready_citations_overturn`) solo and sequentially with `--force` or
`--no-cache` under an effective worker ceiling — each eval's `evals.json`
`"timeout"` when set, else the CLI `--timeout` — raised until none is cut off,
on the default vendor unless the RUNBOOK records why a Cursor sample could not
complete the loop and that the operator asked for a Claude sample instead. Each
measured run reaches a graded verdict with `worker_rc` of `0` and a recorded
`duration_s` from that live completing worker, with no `-1` cutoff among them,
and each eval is run at least twice so the band rests on more than one draw per
eval.

The RUNBOOK measurement note in `tests/task_auto_check/RUNBOOK.md` lists, for
each named repair-class eval above, at least two completing `duration_s`
values with the vendor used for each draw, taken from the completing runs
above rather than from any run the deadline cut off, and records the band
derived from those values, its lower and upper end.

`tests/task_auto_check/RUNBOOK.md` no longer states the `~900 to 1500s` band, the
`via a 15 to 25 min repair-loop timeout` minutes form of that band, or the
instruction to pass `--timeout 1800`; each superseded site states the
re-measured band (seconds sites in seconds; the former minutes site as the
re-measured range in minutes) and, where the default is named, the
current default.

The `--timeout` help in `tests/task_auto_check/evals/run.py` no longer states
`~900-1500s`; it states the same re-measured band as the RUNBOOK, and the two
agree on the figure.

The cheap-first passage in `tests/CLAUDE.md` under `### Cheap-first: probe an LLM-eval fixture before paying for the full loop` no longer freezes `~15 to 25 min per run` or `costs 15 to 25`; that passage states the same re-measured range in minutes, matching the minutes-site form the RUNBOOK uses.

The harness default `--timeout` in `tests/task_auto_check/evals/run.py` equals
the re-measured band's observed upper end plus 300 seconds (the headroom the
current 1800 default keeps above the old 1500s upper end). When the sampled
completing runs stay at or below 1800s, the default stays 1800 and the RUNBOOK
records that the re-measurement confirmed it; otherwise the default is that
upper-end-plus-300 value.

For each measured repair-class eval, the post-change effective worker ceiling — that eval's `evals.json` `"timeout"` when declared, else the new harness default — is at least that eval's observed maximum `duration_s` among the completing runs above, plus 300 seconds. Where a declaration already clears that floor it stays; where it does not, or where a sampling raise must persist for the default path, `evals.json` carries the updated `"timeout"`. When any of those declarations change, the matching row in the RUNBOOK per-eval timeout table under `## Per-eval timeouts, and which evals need them` states the new budget.
