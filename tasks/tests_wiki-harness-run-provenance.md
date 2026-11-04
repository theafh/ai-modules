---
description: Give wiki-harness runs self-describing provenance, surface a narrowed regression baseline, and retire the docs' frozen run-cost counts.
scope: "local test harnesses"
created: 2026-08-22T08:19:15
updated: 2026-11-04T10:11:30
status: open
reported-by: Andreas Hoffmann
---

# Give the wiki harness's runs and docs their own provenance

## Goal

An operator running the wiki skill's local harness can tell from a run what that
run actually covered, can tell whether the regression verdict it prints compared
like against like, and reads operator docs that describe the harness as it
behaves now. Each scale or cost figure those docs quote names the source that
yields it rather than a number frozen when the doc was written.

## Context

The wiki harness is the family's legacy two-layer harness: `layer1` covers the
bundled scripts deterministically, and `layer2` spawns one vendor-resolved
print-mode worker per scenario and pass through `tests/lib/vendor.py`, grades
each against per-scenario assertions, then aggregates with a regression compare.
Its operator-facing docs are the tree's `README.md` and `RUNBOOK.md` under the
harness directory. Three things there still diverge from how the harness
behaves.

**The regression baseline can narrow silently.** The layer-2 runner picks its
comparison baseline through `latest_previous_benchmark()`, and a
`--scenario`-scoped debug run writes a `benchmark.json` exactly as a full-suite
run does. So a one-scenario debug run becomes the baseline the next full-suite
run compares against, and the compare then spans only the overlapping scenario
while the output still presents its exit status as the regression signal. This
happened on 2026-08-21: a full-suite run compared against a baseline written by a
single-scenario, single-pass debug run of `L2-1`. The README passage beginning
"The aggregator automatically compares against the most recent prior" describes
the automatic compare without this caveat, and the RUNBOOK says only that "The
aggregator returns non-zero if any assertion that was 100% in the prior run is
now <100%".

**A run directory does not say what kind of run it was.** The
`workspace/run-<ts>/` name carries a timestamp and nothing else, so the
directory name alone does not identify a full-suite run against a
`--scenario`-scoped debug run. The runner's summary output now prints the
scenario set, pass count, vendor/model, and worker count, so the run kind is
readable from that output; neither operator doc points a reader at it, and the
directory name still carries no shape. On 2026-08-21 a debug run was read as the
standing suite record before that output existed.

**The docs still quote counts and costs frozen at earlier harness eras.**
The README heading `### Full: Layer 1 + Layer 2 (~5 to 10 min, default 4
parallel scenarios)` freezes both the duration and the worker count; the RUNBOOK
comment `# Layer 1 + Layer 2 (full regression, ~5 to 10 min, spawns claude -p
subprocesses)` freezes both the duration and a Claude-only worker picture that
the vendor-aware runner has already superseded; and `## Latest results` still
reports "two independent end-to-end runs (4 samples per scenario)". The README's
former `× 10` pass count and the in-session prompt's "spawn 5 subagents" / "After
all 10 runs finish" instructions have already been retired. Measured on the
2026-08-21 full-suite run, the suite ran every scenario in `layer2/evals.json` at
that file's `passes` value, took roughly 23 minutes of wall clock at the runner's
default parallel-worker count, and spent about 83 minutes of aggregate worker
time at a median of just under two minutes per pass. The README already handles
this drift well in one place: the passage introducing `layer2/evals.json` as
"the live inventory" gives the `jq` command that lists it and labels its own
table as covering only the scenarios the harness started with. That is the shape
the stale figures converge on.

The layer-2 runner already calls `micro_deploy.preflight_auth` before staging
workers, so the earlier "skip the shared auth preflight" gap is closed and is not
part of this task.

The `## What "all passing" guarantees` section enumerates what a clean run
establishes, and its list predates the scenario families the suite now runs: it
speaks only to the original discovery scenarios and names none of the
`wiki_import`, `wiki_wrapup`, or `auto_shaper_wiki` scenario families that
`layer2/evals.json` carries today.

## Approach

Rewrite each diverging passage in the two operator docs in place, and extend the
runner's provenance where it still stops short.

The runner's summary already prints the scenario set, pass count, vendor/model,
and worker count, so the run kind is readable without opening
`benchmark.json`. Keep that output. Have the regression compare name the
baseline it selected and state that baseline's shape alongside the verdict, and
flag the case where the baseline covered fewer scenarios than the current run,
so a narrowed comparison reads as narrowed rather than as a clean pass. Keep the
existing latest-previous baseline selection: surfacing the narrowing preserves
the operator's information without adding a second baseline-selection mechanism
to reason about.

Following the shape the README's live inventory passage already uses, replace
each frozen figure in the two docs with the derivation that yields it: the
scenario inventory in `layer2/evals.json` and that file's `passes` value, and
the runner's own default worker count. Rewrite the RUNBOOK launch comment so it
describes the vendor-aware worker rather than a frozen `claude -p` picture.
Restate `## Latest results` so it points at the current record rather than
describing a superseded pair of runs.

Extend `## What "all passing" guarantees` to cover each scenario-id family
present in `layer2/evals.json`, so a reader learns what the front-end and agent
scenarios establish alongside the discovery ones.

**Out of scope:**

- Migrating this harness to the skill-creator-aligned layout, which the standing
  repo rules defer to the harness's next significant iteration.
- Re-adding auth preflight, which `tests/wiki/layer2/run.py` already performs
  through `micro_deploy.preflight_auth`.
- The tree-level harness inventory in the tests tree's own `README.md`, whose
  listing live siblings already co-edit, including
  [tests_wiki-front-end-behavior-evals.md](tests_wiki-front-end-behavior-evals.md).
- Adding scenarios, assertions, or coverage of untested harness behaviour; this
  task changes what a run reports about itself and what the docs say, and leaves
  the scenario set as it stands.

## Acceptance

1. The regression compare names the baseline run it selected and that baseline's
   shape, and says so explicitly when the baseline covered fewer scenarios than
   the current run. Verify by running a `--scenario`-scoped run, then a
   full-suite run, and confirming the second reports the narrowing rather than
   presenting an unqualified pass.
2. Searching the two operator docs for the frozen forms returns nothing: the
   `~5 to 10 min` duration in both docs, the `default 4 parallel scenarios`
   worker count in the README heading, the "spawns claude -p subprocesses"
   RUNBOOK wording, and the "4 samples per scenario" claim under
   `## Latest results`. Each site instead names the inventory or value it
   derives from, and no second copy of the retired figure remains elsewhere in
   either doc. The already-retired `× 10` pass count and the "spawn 5 subagents"
   / "After all 10 runs finish" instructions stay gone.
3. `## What "all passing" guarantees` names each scenario-id family present in
   `layer2/evals.json` and states what a clean run establishes for it, so the
   section covers the suite as it stands rather than the discovery scenarios
   alone.
4. A full-suite run still completes green after the changes, so the added
   provenance leaves the graded outcome unchanged. Run that verification on the
   default vendor per `TESTING.md`.
