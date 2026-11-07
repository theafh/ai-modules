---
description: Prove the two wiki front-end promises the layer-2 scenarios claim but never assert, wiki_fix report fidelity and the pre-approval write boundary, and name the covered skills in the tree inventory.
scope: "local test harnesses"
created: 2026-08-11T18:59:52
updated: 2026-11-07T10:11:22
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
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

The capture as it stands cannot see the agent's report. The shared worker helper
already runs each worker with stream-json and parses the turn for tool-call
provenance (`micro_deploy.run_worker`), but the runner writes only the parsed
final message to `response.txt`; the `auto_shaper_wiki` sub-agent's own report is
not extracted into an artifact, and the grader reads only `response.txt` and the
structured `report.md` it falls back to. It implements no assertion type over a
sub-agent's output. Closing the fidelity gap therefore extends the stream
extraction before it adds the assertion.

[task-family_test-harness-consolidation.md](task-family_test-harness-consolidation.md)
also edits the tree README's harness listing, so coordinate that one section.

## Approach

Capture the agent's report as its own per-pass artifact, then grade the returned
response against it. The shared worker helper already runs stream-json; have the runner write the `auto_shaper_wiki` sub-agent's report to a per-pass
file beside `response.txt` for every pass whose run yields one, and add a
grader assertion type that compares the captured report against what the skill
returned. Read that report from the spawn `ToolRecord` whose `helper` is
`auto_shaper_wiki` (`micro_deploy.run_worker` already returns it, with
`result_text` populated on both vendors). On Claude that `result_text` is the
report as written; on Cursor `_render_cursor_result` renders it as a JSON
object, so take that object's `conversationSteps` field, the helper's final
text only, as the report. Fall back to the helper transcript's final assistant
message — the `text` blocks of its last `role: assistant` line, taken alone
rather than concatenated with the narration and tool preambles on earlier
lines — in its chat transcript JSONL under the scratch home, located by the
`agentId` in the parent's Task result, under `_CURSOR_TRANSCRIPT_ROOTS`, only
when the selected source carries no report text: an empty `result_text`, a
refusal, a bare `success` marker, or a Cursor rendering whose
`conversationSteps` is empty. That comparison is
whitespace-collapsed verbatim containment: read both the captured report and
`response.txt` with runs of whitespace collapsed to a single space, and pass
the assertion when the collapsed report appears in the collapsed response in
order, so the parent's framing around the report block does not fail it. The
failure message names the first span of the captured report the response
omits, and a pass that captures no report at all fails with the named evidence
`no sub-agent report captured`, so it cannot pass on an empty capture. Keep `response.txt` holding the worker's
final assistant text, since the existing `response_text_*` assertions and the
`report.md` fallback both read it. Add the assertion to `AS-2` alone, the one `AS-*` scenario that already grades
the surfacing with `A4_surfacing_mentioned_in_response`; the remaining `AS-*` entries carry `skill_name` `wiki_fix` as well, so naming `AS-2` is what keeps
`wiki_fix` coverage in one place. Rewrite `AS-2`'s `extra_constraints` line
"Run the auto_shaper_wiki audit flow the wiki_fix skill fronts" to "Invoke the
`auto_shaper_wiki` agent and run its audit flow through it", matching the
`wiki_fix` skill's `<delegate>` directive: a worker that runs the flow inline
would leave no sub-agent report to capture. This edits one existing scenario's
constraint text and neither adds nor removes a scenario, so the `**Out of
scope:**` entry that leaves the scenario inventory as it stands still holds.
Demonstrate the new check's teeth by changing `AS-2`'s instruction to summarise
the agent's report instead of relaying it, running it once, recording the
per-assertion `FAIL` in `tests/wiki/results/SUMMARY.md` beside the pre-approval
record, then restoring the instruction.

Prove the pre-approval assertions bite by temporarily rewriting `WI-1`'s and
`WU-1`'s `user_request` and their matching `extra_constraints` stop line in
`layer2/evals.json` so the worker is instructed to write
`HOME/proj/wiki/concepts/transformer.md` before approval, running each scenario,
and confirming its `path_does_not_exist` assertion reports `FAIL` on that run.
Restore both scenarios' request text and restage their sandboxes afterwards,
then record the failing run and its per-assertion evidence where the harness
keeps its results so the proof is not re-litigated later.

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
- A full layer-2 suite re-run as a done bar. This task proves the change's reach
  over the four evals it touches; a full-suite run stays an optional operator
  measurement, not this task's acceptance gate.

## Acceptance

1. Every pass whose run yields an `auto_shaper_wiki` report — the spawn
   `ToolRecord`'s `result_text` (the `conversationSteps` field of its Cursor
   rendering), else the `text` blocks of the helper transcript's last assistant
   message — writes it as its own per-pass artifact
   beside `response.txt`, and `AS-2` grades the returned
   response against the captured report rather than against a keyword regex. The
   assertion passes on a run of `AS-2`, and a pass that captures no
   `auto_shaper_wiki` report fails it with the named evidence `no sub-agent
   report captured`.
2. `response.txt` still holds the worker's final assistant text after the
   stream-extraction change, so every existing `response_text_*` assertion and
   the `report.md` fallback grade against what they read now.
3. The fidelity assertion fails on a run whose scenario instruction is
   deliberately changed to summarise the agent's report instead of relaying it,
   demonstrated once before the instruction is restored, so the new check is
   known to have teeth. The failing run is recorded in
   `tests/wiki/results/SUMMARY.md` beside Acceptance 4's record, naming the
   scenario, the changed instruction, and the assertion that failed, so a later
   reader and `task_audit` find the proof in the tree.
4. `WI-1`'s and `WU-1`'s `path_does_not_exist` assertions each fail on a run
   whose `user_request` and `extra_constraints` stop line are temporarily
   changed to instruct the write of the guarded page before approval, and the
   outcome is recorded where the harness keeps its results, so a later reader
   finds the proof without repeating the exercise.
5. The wiki entry under `## Current harnesses` in the tests tree's `README.md`
   names `wiki_fix`, `wiki_import`, and `wiki_wrapup` as skills its layer-2
   scenarios cover, and keeps the `layer2/evals.json` selector as its statement
   of extent.
6. A scoped layer-2 re-run on the default vendor over the four evals the change
   reaches — `AS-2` (the new fidelity assertion and the stream-extraction
   change), `AS-21` (an independent `response_text_*` consumer of
   `response.txt`), and `WI-1` and `WU-1` (the restored pre-approval staging) —
   passes every assertion in those scenarios, and every assertion they carried
   before the change still passes. That set proves the change's reach: the new
   assertion grades green, the `response.txt` format still satisfies its
   existing readers, and the restored staging leaves those four evals green. A
   failing assertion inside that set is diagnosed and fixed as part of this
   task; every eval outside it keeps its already-recorded verdict.
