---
description: Give wiki-harness runs self-describing provenance, surface a narrowed regression baseline, and retire the docs' frozen run-cost counts.
scope: "local test harnesses"
created: 2026-08-22T08:19:15
updated: 2026-11-04T20:27:19
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
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
establishes, and its list predates the scenario-id families the suite now runs:
it speaks only to the original discovery scenarios under the `L2` id prefix and
names none of the other prefixes `layer2/evals.json` carries today (`WI`, `WU`,
`AS`, `MP`), nor the later `L2` hub cases the section still omits.

Since this task was written, the layer-2 suite has been red for reasons outside
this change. Commit `c0d177b` (2026-10-23) made every eval
sandbox root harness-prefix-only, which invalidated 12
`report_field_endswith` assertions that still embed the scenario id in the
expected path, and `AS-2`, `AS-4`, and `AS-9` now trip the artefact read-check
on a literal `$f` path from `init_wiki.sh`. None of this task's changed
surfaces participates in layer-2 grading. Acceptance 4 therefore verifies that
the change adds no new graded regression and records those failures as
baseline context; repairing them is tracked in
[tests_wiki-layer2-preexisting-failures.md](tests_wiki-layer2-preexisting-failures.md).

## Approach

Rewrite each diverging passage in the two operator docs in place, and extend the
runner's provenance where it still stops short.

The runner's summary already prints the scenario set, pass count, vendor/model,
and worker count, so the run kind is readable without opening
`benchmark.json`. Keep that output. Point both operator docs at that printed summary — and at
the `benchmark.json` scenario list it reflects — as the place a reader learns
what kind of run a given `workspace/run-<ts>/` directory was. Leave
run-directory naming as timestamp-only `run-<ts>/`; the summary plus those
doc pointers carry the run-kind signal. Have the regression compare name the
baseline it selected and state that baseline's shape alongside the verdict, and
flag the case where the baseline covered fewer scenarios than the current run
as an explicit compare warning that does not change exit status; exit status
stays driven only by assertion or scenario regressions, so a narrowed comparison
reads as narrowed in its messaging while the graded outcome stays unchanged. Keep the
existing latest-previous baseline selection: surfacing the narrowing preserves
the operator's information without adding a second baseline-selection mechanism
to reason about.

Following the shape the README's live inventory passage already uses, rewrite
each of these frozen or vendor-era sites in the two operator docs in place so
each scale, cost, pass, worker, or worker-picture claim names the derivation
that yields it (the scenario inventory in `layer2/evals.json` and that file's
`passes` value, and the runner's own default worker count) rather than a number
or vendor picture frozen when the doc was written. Drop the `~5 to 10 min`
duration wall-clock from the README Full heading and the RUNBOOK launch comment
rather than replacing it with another frozen figure (including Context's
measured ~23 minutes); rewrite only the worker-count and Claude-only
worker-picture claims at those sites through the named derivations above:

- the README heading `### Full: Layer 1 + Layer 2 (~5 to 10 min, default 4
  parallel scenarios)` (drop duration; rewrite worker count)
- the RUNBOOK launch comment `# Layer 1 + Layer 2 (full regression, ~5 to 10
  min, spawns claude -p subprocesses)` (drop duration; rewrite Claude-only worker picture)
- `## Latest results`, including the "two independent end-to-end runs (4 samples
  per scenario)" claim, so it points at the current record rather than a
  superseded pair of runs
- the README heading `## Layer 2: skill-level, spawns Claude subagents`
- the Layer-2 intro's frozen pass/worker picture (`**Two passes**` and
  `default 4`)
- the README tree comment `run.py # standalone orchestrator (claude -p)`
- the `## What "all passing" guarantees` vendor-era framing ("Across two
  independent agent runs" / "Claude:")

The already-retired `× 10` pass count and the in-session prompt's "spawn 5
subagents" / "After all 10 runs finish" instructions stay gone and are not
reintroduced.

Extend `## What "all passing" guarantees` to cover each scenario-id family
present in `layer2/evals.json`. A family is the id prefix before the first
hyphen on each scenario `id`, re-found by scanning that file at rewrite time
(today `L2`, `WI`, `WU`, `AS`, and `MP`) rather than copying a frozen list or
grouping by `skill_name`. Name each family by that prefix and state what a
clean run establishes for it, so a reader learns what the front-end and agent
scenarios establish alongside the discovery ones. When a family's scenarios set
`skill_name`, use that value in the prose (`wiki_import` for `WI`,
`wiki_wrapup` for `WU`, `wiki_fix` for `AS` and `MP`); name `auto_shaper_wiki`
only as the agent those `wiki_fix` scenarios exercise. Treat `L2` as the hub
`wiki` skill's scenarios (discovery through later hub cases) that inherit the
file's top-level `skill_name`.

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
- Encoding run shape in the `workspace/run-<ts>/` directory name or renaming
  those directories; the printed summary and the operator-doc pointers to it
  carry that signal.

## Acceptance

1. The regression compare names the baseline run it selected and that baseline's
   shape, and says so explicitly when the baseline covered fewer scenarios than
   the current run, as a compare warning that leaves exit status unchanged when
   no assertion or scenario regression fires. Verify by running a
   `--scenario`-scoped run, then a full-suite run, and confirming the second
   reports the narrowing in its compare output rather than presenting an
   unqualified pass in that output.
2. Every rewrite site the Approach lists in the two operator docs is rewritten
   to name the inventory or value it derives from, and searching those docs for
   the frozen forms those sites carried returns nothing; no second copy of a
   retired figure remains elsewhere in either doc. The already-retired `× 10`
   pass count and the "spawn 5 subagents" / "After all 10 runs finish"
   instructions stay gone.
3. `## What "all passing" guarantees` names each scenario-id family present in
   `layer2/evals.json` and states what a clean run establishes for it, so the
   section covers the suite as it stands rather than the discovery scenarios
   alone.
4. The change introduces no new graded regressions. Verify that the changed
   surfaces (`aggregate.py`, the two operator docs, and the layer-1 test) do not
   participate in layer-2 grading, and that a default-vendor full-suite run after
   the change shows only the pre-existing failures recorded in Context (the 12
   path-suffix scenarios and `AS-2`, `AS-4`, `AS-9`), with `aggregate_rc=0` and an
   empty `regressions` list. The suite was already red before this task; repairing
   those failures is out of scope here and tracked in the follow-up task named in
   Context.
5. Both operator docs direct a reader to the runner's printed summary (scenario
   set, pass count, vendor/model, worker count) and the matching
   `benchmark.json` scenario list as how to tell what a given run covered.
   Verify by confirming each doc names that signal in the passages that discuss
   run output or run directories, and that neither doc claims the timestamp-only
   directory name alone identifies run kind.
