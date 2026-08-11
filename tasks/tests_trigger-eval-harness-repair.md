---
description: Repair the trigger-eval harness, which reports a zero trigger rate on every positive query, so its numbers measure skill triggering again, then re-baseline the recorded results.
scope: "local test harnesses"
created: 2026-08-11T18:59:52
updated: 2026-08-11T18:59:52
status: open
reported-by: Andreas Hoffmann
---

# Repair the trigger-eval harness so its results measure triggering

## Goal

A trigger-eval run reports whether a skill fires on realistic user phrasings, so
its numbers can be trusted as evidence about a description. A run whose skill
under test is unavailable says so instead of reporting a clean-looking zero. Fresh
baselines exist for the fixtures the tree carries, recorded against the
descriptions in place at the time of the run.

## Context

Every recorded run for the wiki family reports `precision=100% recall=0%
accuracy=50%` with a `trigger_rate` of 0.0 on every positive query, across all
five iterations of the optimization loop. The negative queries pass for the same
reason nothing else did: the skill never fired at all. As recorded, the numbers
measure the harness rather than the descriptions, and the shape of the failure
reads like a description that matches nothing.

The runner resolves the skill under test from the deployed skill tree, with a
fallback path when that lookup misses. The finished precedent
[archive/task-family_sibling-trigger-routing.md](archive/task-family_sibling-trigger-routing.md)
records that the runner reads the deployed descriptions and produced non-zero
routing numbers for the `task*` fixtures, so the harness worked at that time. What
has changed since is how artefacts reach the deployed tree, which makes the
resolution path the first place to look.

The recorded results are also stale against what they describe. The logs are dated
2026-05-17, while the `wiki` and `wiki_import` descriptions changed on 2026-05-25
and `wiki_fix`'s on 2026-06-22, and the `wiki_fix` log still quotes the pre-rename
agent name `wiki_auto_shaper`. So they cannot serve as a baseline even once the
harness works again.

The harness is shared: it carries `task` and `task_explain` fixtures beside the
four wiki ones, so this repair is repo-wide tooling rather than wiki-specific.
[wiki_activation-surface-and-descriptions.md](wiki_activation-surface-and-descriptions.md)
rewrites two of those descriptions and needs this harness to measure the result,
so that task consumes what this one restores.
[task-family_test-harness-consolidation.md](task-family_test-harness-consolidation.md)
adds trigger-eval cases for a task-family sibling and registers harnesses in the
same tree inventory, so it depends on the runner this task repairs and co-edits
that inventory section.

## Approach

1. Reproduce the zero-trigger result on one fixture, then instrument the runner's
   skill-availability path to record which lookup it takes and what the spawned
   worker actually receives.
2. Fix the resolution so the worker has the skill under test available whichever
   deployment shape the machine uses, and have the runner fail loudly with a named
   unavailability whenever it can detect that the skill is absent, rather than
   scoring the run.
3. Re-baseline the four wiki fixtures and the two task fixtures against the
   current descriptions, recording each run where the tree's conventions keep
   results.
4. State in the tree README how to read a zero-recall outcome, so a later reader
   separates a harness failure from a description failure.

**Out of scope:**

- Rewriting any skill description, owned by
  [wiki_activation-surface-and-descriptions.md](wiki_activation-surface-and-descriptions.md).
- Changing the optimization loop's search strategy or its iteration budget.

## Acceptance

1. A run on a fixture whose positive queries name the skill under test plainly
   reports a non-zero trigger rate, replacing the zero rate recorded today.
2. A run with the skill deliberately made unavailable exits with a distinct
   failure naming the unavailability, and produces no accuracy or recall figure.
3. Fresh baselines exist for all four wiki fixtures and both task fixtures, each
   run against the current descriptions and dated after the most recent change to
   the description it measures.
4. The stale 2026-05-17 logs are superseded in the results location by those fresh
   runs, so no reader takes a zero-recall log as a current verdict.
5. The tree README states what a zero-recall outcome means and which failure it
   distinguishes, placed with the harness's own entry.
6. Diagnostic instrumentation added in step 1 is removed or sits behind a flag, so
   an ordinary run's output stays readable.
