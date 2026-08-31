---
description: Prove the two wiki front-end promises the layer-2 scenarios claim but never assert, wiki_fix report fidelity and the pre-approval write boundary, and name the covered skills in the tree inventory.
scope: "local test harnesses"
created: 2026-08-11T18:59:52
updated: 2026-08-30T17:36:22
status: checked
reported-by: Andreas Hoffmann
---

# Close the unproven promises in the wiki front-end scenario coverage

## Goal

The wiki harness asserts the two front-end promises its scenarios currently claim
without proving, and the tests tree inventory names which skills those scenarios
cover. The harness records what the `auto_shaper_wiki` agent returned, so
`wiki_fix` report fidelity is graded against that evidence rather than against a
keyword match or the worker's own word. A reader looking for `wiki_fix`,
`wiki_import`, or `wiki_wrapup` coverage finds it named rather than implied, and
the assertions guarding the pre-approval write boundary are known to fail when a
run crosses that boundary.

## Context

The wiki harness's `layer2/evals.json` already covers all three front ends, which
it did not when this task was filed on 2026-08-11. Its `WI-*` scenarios carry
`skill_name` `wiki_import`, its `WU-*` scenarios carry `wiki_wrapup`, and its
`AS-*` scenarios carry `wiki_fix` and instruct the worker to "Run the
auto_shaper_wiki audit flow the wiki_fix skill fronts". Between them they assert
the proposal shape, the raw capture, the post-approval `log.md` write, and both
sandbox fail-safes, `no_files_outside_sandbox` and `real_home_wiki_absent`, on
every scenario. A full-suite run passed every assertion on 2026-08-22. The
coverage gap this task originally described is therefore closed, and what remains
are two promises the scenarios claim but do not test, plus an inventory entry that
names no skill.

**The `wiki_fix` report-fidelity promise has no assertion.** `wiki_fix` returns
the `auto_shaper_wiki` agent's report verbatim under its `<surface_report>`
policy. The closest existing check is `AS-2`'s
`A4_surfacing_mentioned_in_response`, a keyword regex over the response text that
a paraphrase satisfies as readily as a verbatim relay. Nothing compares what the
agent produced against what the skill returned.

**The pre-approval boundary assertions are unproven against a violation.** `WI-1`
and `WU-1` assert `path_does_not_exist` on a wiki page to establish that neither
front end writes before approval. No record shows either assertion failing on a
run that does write early, so their teeth are assumed rather than demonstrated,
and a scenario whose staging never gives the worker the chance to write would
pass them vacuously.

**The tree inventory names no covered skill.** The `## Current harnesses` entry
for the wiki harness in the tests tree's own `README.md` describes its layer 2 as
every scenario in `layer2/evals.json` over that file's `passes` denominator. That
selector stays true as the set grows, and it leaves a reader searching the
inventory for a named front end with nothing to find.

The capture as it stands cannot see the agent's report. The runner invokes each
worker with the CLI's default text output and writes stdout to `response.txt`, so
the sub-agent's own messages never reach an artifact, and the grader reads only
that file and the structured `report.md` it falls back to. It implements no
assertion type over a sub-agent's output. Closing the fidelity gap therefore
extends the capture before it adds the assertion.

[task-family_test-harness-consolidation.md](archive/task-family_test-harness-consolidation.md)
also edits the tree README's harness listing, so coordinate that one section.

## Approach

Capture the agent's report as its own per-pass artifact, then grade the returned
response against it. Run the worker with the streaming output format the CLI
offers in `--print` mode, extract the `auto_shaper_wiki` sub-agent's report from
that stream into a per-pass file beside `response.txt`, and add a grader
assertion type that compares the captured report against what the skill returned.
Confirm the sub-agent's report is recoverable from the stream before building the
assertion on it. Keep `response.txt` holding the worker's final assistant text
across the format change, since the existing `response_text_*` assertions and the
`report.md` fallback both read it. Add the assertion to the `AS-*` scenario that
already puts `wiki_fix` under test, so `wiki_fix` coverage stays in one place.

Prove the pre-approval assertions bite by staging a run that writes the guarded
page before approval, confirming `WI-1`'s and `WU-1`'s `path_does_not_exist`
assertions fail on it, then reverting the staging and recording the outcome where
the harness keeps its results so the proof is not re-litigated later.

Rewrite the wiki entry under `## Current harnesses` so it names the skills the
layer-2 set covers alongside the selector it already carries, keeping that
selector as the statement of extent.

**Out of scope:**

- Staging a separate per-skill harness for each front end. The coverage such
  harnesses were to add now lives in the wiki harness's layer-2 set, so a second
  home would duplicate it; relocating those scenarios is harness restructuring
  rather than work this task needs.
- Adding scenarios for front-end behaviour the current set does not reach. This
  task proves promises the existing scenarios already claim and leaves the
  scenario inventory as it stands.

## Acceptance

1. Each pass of the `AS-*` scenario carrying `skill_name` `wiki_fix` writes the
   `auto_shaper_wiki` sub-agent's report as its own artifact beside
   `response.txt`, and that scenario grades the returned response against the
   captured report rather than against a keyword regex. The assertion passes on a
   run of that scenario.
2. `response.txt` still holds the worker's final assistant text after the output
   format change, so every existing `response_text_*` assertion and the
   `report.md` fallback grade against what they read now.
3. The fidelity assertion fails on a run whose scenario instruction is
   deliberately changed to summarise the agent's report instead of relaying it,
   demonstrated once before the instruction is restored, so the new check is
   known to have teeth.
4. `WI-1`'s and `WU-1`'s `path_does_not_exist` assertions each fail on a run
   staged to write the guarded page before approval, and the outcome is recorded
   where the harness keeps its results, so a later reader finds the proof without
   repeating the exercise.
5. The wiki entry under `## Current harnesses` in the tests tree's `README.md`
   names `wiki_fix`, `wiki_import`, and `wiki_wrapup` as skills its layer-2
   scenarios cover, and keeps the `layer2/evals.json` selector as its statement
   of extent.
6. A full-suite layer-2 run passes every assertion after the changes, so the new
   assertion, the output format change, and the restored staging leave the suite
   green.
