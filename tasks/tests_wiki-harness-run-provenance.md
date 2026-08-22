---
description: Give wiki-harness runs self-describing provenance, surface a narrowed regression baseline, retire the docs' frozen run-cost counts, and fail fast on a dead worker login.
scope: "local test harnesses"
created: 2026-08-22T08:19:15
updated: 2026-08-22T08:19:15
status: open
reported-by: Andreas Hoffmann
---

# Give the wiki harness's runs and docs their own provenance

## Goal

An operator running the wiki skill's local harness can tell from a run what that
run actually covered, can tell whether the regression verdict it prints compared
like against like, and learns of a dead worker login from one probe instead of
from every worker failing in turn. The harness's operator docs describe the
harness as it behaves now, and each scale or cost figure they quote names the
source that yields it rather than a number frozen when the doc was written.

## Context

The wiki harness is the family's legacy two-layer harness: `layer1` covers the
bundled scripts deterministically, and `layer2` spawns one `claude -p` worker per
scenario and pass, grades each against per-scenario assertions, then aggregates
with a regression compare. Its operator-facing docs are the tree's `README.md`
and `RUNBOOK.md` under the harness directory. Four things there diverge from how
the harness behaves.

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
`workspace/run-<ts>/` name carries a timestamp and nothing else, so a full-suite
run and a `--scenario`-scoped debug run are indistinguishable without opening
`benchmark.json` and reading its `n_scenarios` field. Neither operator doc points
a reader at that field. On 2026-08-21 this led to a debug run being read as the
standing suite record.

**The docs quote counts and costs frozen at the harness's five-scenario era.**
The README heading `### Full — Layer 1 + Layer 2 (~5–10 min, ~50k tokens per pass
× 10)` freezes both the duration and the pass count; the orchestration prompt
under `### Inside a Claude Code session (faster — true parallel subagents)`
instructs a reader to "spawn 5 subagents in parallel" and to act "After all 10
runs finish"; the RUNBOOK comment `# Layer 1 + Layer 2 (full regression, ~5–10
min, spawns claude -p subprocesses)` repeats the duration; and `## Latest
results` still reports "two independent end-to-end runs (4 samples per
scenario)". Measured on the 2026-08-21 full-suite run, the suite ran every
scenario in `layer2/evals.json` at that file's `passes` value, took roughly 23
minutes of wall clock at the runner's default parallel-worker count, and spent
about 83 minutes of aggregate worker time at a median of just under two minutes
per pass. The README already handles this drift well in one place: the passage
introducing `layer2/evals.json` as "the live inventory" gives the `jq` command
that lists it and labels its own table as covering only the scenarios the harness
started with. That is the shape the stale figures converge on.

**The runner skips the shared auth preflight.** `tests/wiki/layer2/run.py` imports
only `worker_env` from the shared `worker_auth` module and never calls
`preflight_auth`, so a dead login is discovered once per worker rather than once
per run. Every other eval runner in the tree that spawns `claude -p` workers calls
it, and the tests tree's own standing instructions document that preflight under
the heading "Worker auth: nested `claude -p` reads the stored OAuth login", which
makes this runner the outlier rather than a sanctioned exception.

The `## What "all passing" guarantees` section enumerates what a clean run
establishes, and its list predates the scenario families the suite now runs: it
speaks only to the original discovery scenarios and names none of the
`wiki_import`, `wiki_wrapup`, or `auto_shaper_wiki` scenario families that
`layer2/evals.json` carries today.

## Approach

Rewrite each diverging passage in the two operator docs in place, and make the
runner state its own provenance.

Have the runner record and print the shape of the run it just performed — the
scenario set and pass count it covered — into the run's own summary output, so
the run kind is readable without opening `benchmark.json`. Have the regression
compare name the baseline it selected and state that baseline's shape alongside
the verdict, and flag the case where the baseline covered fewer scenarios than
the current run, so a narrowed comparison reads as narrowed rather than as a
clean pass. Keep the existing latest-previous baseline selection: surfacing the
narrowing preserves the operator's information without adding a second
baseline-selection mechanism to reason about.

Replace each frozen figure in the two docs with the derivation that yields it —
the scenario inventory in `layer2/evals.json` and that file's `passes` value, and
the runner's own default worker count — following the shape the README's live
inventory passage already uses. Rewrite the in-session orchestration prompt so it
instructs a reader in terms of that inventory rather than a fixed subagent and
run count. Restate `## Latest results` so it points at the current record rather
than describing a superseded pair of runs.

Extend `## What "all passing" guarantees` to cover each scenario-id family
present in `layer2/evals.json`, so a reader learns what the front-end and agent
scenarios establish alongside the discovery ones.

Call `preflight_auth` from the layer-2 runner before it stages any sandbox or
spawns any worker, matching how the tree's other `claude -p` runners use the
shared module.

**Out of scope:**

- Migrating this harness to the skill-creator-aligned layout, which the standing
  repo rules defer to the harness's next significant iteration.
- The tree-level harness inventory in the tests tree's own `README.md`, whose
  listing live siblings already co-edit, including
  [tests_wiki-front-end-behavior-evals.md](tests_wiki-front-end-behavior-evals.md).
- Adding scenarios, assertions, or coverage of untested harness behaviour; this
  task changes what a run reports about itself and what the docs say, and leaves
  the scenario set as it stands.

## Acceptance

1. A layer-2 run's own summary output states the shape of that run — the
   scenarios and pass count it covered — so a `--scenario`-scoped run and a
   full-suite run are distinguishable from that output alone. Verify by running
   one scoped run and one full-suite run and reading the shape back from each.
2. The regression compare names the baseline run it selected and that baseline's
   shape, and says so explicitly when the baseline covered fewer scenarios than
   the current run. Verify by running a `--scenario`-scoped run, then a
   full-suite run, and confirming the second reports the narrowing rather than
   presenting an unqualified pass.
3. Searching the two operator docs for the frozen forms returns nothing: the
   `× 10` pass count in the full-run heading, the "spawn 5 subagents" and "After
   all 10 runs finish" instructions in the in-session prompt, the `~5–10 min`
   duration in both docs, and the "4 samples per scenario" claim under
   `## Latest results`. Each site instead names the inventory or value it derives
   from, and no second copy of the retired figure remains elsewhere in either
   doc.
4. `## What "all passing" guarantees` names each scenario-id family present in
   `layer2/evals.json` and states what a clean run establishes for it, so the
   section covers the suite as it stands rather than the discovery scenarios
   alone.
5. The layer-2 runner exits after a single auth probe when the worker login is
   dead, reporting the shared module's two remediations, and stages no sandbox
   and spawns no worker in that run. Verify by exporting an invalid
   `CLAUDE_CODE_OAUTH_TOKEN`, running the runner, and confirming one probe
   failure and an empty run directory.
6. A full-suite run still completes green after the changes, so the added
   provenance and preflight leave the graded outcome unchanged.
