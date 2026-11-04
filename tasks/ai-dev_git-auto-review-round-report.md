---
description: "Rework git_auto_review's report.txt into per-round outcomes, not-applied findings with reasons, and the final state, so a finding fixed earlier is never reported as unfixed."
scope: plugins/ai_dev/skills/git_auto_review
created: 2026-11-04T14:19:14
updated: 2026-11-04T14:19:14
status: open
reported-by: Andreas Hoffmann
---

# Make git_auto_review's report.txt state each round's outcome, what was left unapplied and why, and the final state

## Goal

`git_auto_review`'s terminal `report.txt` answers three questions in plain terms: what each round did, which findings the run left unapplied and why, and what state the working tree is in when the run stops. It carries only the blocks that have content. A finding fixed in an earlier round reads as fixed, and the current "did not fix" umbrella never covers it.

## Context

The confusing output has two sources in the skill's report contract. The `<relay>` paragraph at [the git_auto_review skill](../../plugins/ai_dev/skills/git_auto_review/SKILL.md) says `report.txt` carries "one line per finding the run did not fix", while `<convergence>`'s reporting sentence in the same file requires every gate-listed finding that does not qualify, a tag-excluded `closed` or `settled by a decision` finding included, to be listed with its lane and no fix. A finding fixed in round 1 and re-tagged `closed` by round 2's delta gate therefore lands under a "did not fix" heading even though the run fixed it. The report has no per-round record to say so.

The same contract prescribes no format. `<output_contract>` says the deliverable is `report.txt` "written to the relay and reprinted to the caller", and the `<report>` step says to reprint it, while `auto_gate_git` returns its gate report as Markdown. The loop's own report inherits Markdown-looking output without a stated choice.

The deterministic harness reads this file: [grade.sh](../../tests/git_auto_review/evals/grade.sh) resolves `report.txt` and asserts properties on it, and [evals.json](../../tests/git_auto_review/evals/evals.json) names the report assertions each scenario checks.

## Approach

Rewrite the `<relay>` report contract and the `<convergence>` rendering sentence so `report.txt` has three named blocks, each emitted only when it has content:

- A per-round record, one entry per completed round: the round number, whether the gate was a first or delta review, the stop or continue decision, the qualifying finding ids, the triage decision per finding, the fixes actually written (finding id and path), and the ledger and delta-audit results.
- A not-applied record, one line per finding the run did not apply in the round that raised it: id, heading, location, lane, the reason class from `<convergence>` (a follow-up task proposal, `lane-excluded`, `tag-excluded (closed)` or `tag-excluded (settled by a decision)`, `triage-not-approved` with the verifier's reason, or `charter-set-refused`), and a clause stating whether an earlier round already fixed it.
- A final-state block: the stop condition, the files the run changed in the working tree, and the pending decisions.

State the format explicitly in `<output_contract>`: plain text with one record per line, so the file and its reprint read the same and no Markdown rendering is implied. Keep the "only what applies" rule: an empty block is omitted rather than printed as `None.`.

Keep the `closed` tag semantics in `auto_gate_git` unchanged; the report layer carries the earlier-fix fact. Update the `<convergence>` sentence that requires listing a non-qualifying finding so it points at the not-applied record and names the earlier-fix clause instead of folding every such finding into "did not fix".

Extend the deterministic harness with one staged two-round scenario: round 1 fixes a finding, round 2's gate tags it `closed`, and the grader asserts that `report.txt` carries a round-1 fix record and does not present that finding as unapplied. Add a second scenario where a run stops with no finding, and assert the report omits the not-applied and per-round-fix blocks.

Follow the standing repo rules' version-bump discipline for the `ai_dev` plugin in the implementing commit.

**Out of scope:** Changing what `git_review` reports or how `auto_gate_git` assigns tags; those contracts stay as written.

## Acceptance

- The `<relay>` paragraph and the `<convergence>` sentence in `plugins/ai_dev/skills/git_auto_review/SKILL.md` define the per-round, not-applied, and final-state blocks, and the report contract no longer uses "did not fix" as the umbrella over a `closed` finding. A grep for the three block names and for the earlier-fix clause returns them, and the old phrase is absent from the report contract.
- `tests/git_auto_review/evals/evals.json` carries the two new scenarios, and `tests/git_auto_review/script_tests/run.sh` passes.
- The staged two-round scenario produces a `report.txt` whose round-1 record names the fixed finding and whose not-applied record, when it lists that finding, says an earlier round fixed it.
- The staged clean-run scenario produces a `report.txt` with no not-applied block and no empty `None.` placeholder.
- `make lint` and `make test` pass.
