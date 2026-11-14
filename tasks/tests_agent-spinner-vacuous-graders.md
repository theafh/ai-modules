---
description: "Make agent_spinner eval checks that pass on a no-op or on a run breaking their own rule fail where they should, each proven by a grade_cases.sh case on the fail branch."
scope: tests/agent_spinner
created: 2026-11-14T16:08:26Z
updated: 2026-11-14T23:20:22Z
status: open
reported-by: Andreas Hoffmann
---

# Make the vacuous agent_spinner eval checks able to fail

## Goal

Every agent_spinner eval named for a behaviour fails when a run skips or breaks that behaviour. Today several checks in `tests/agent_spinner/evals/grade.sh` pass on an untouched fixture with a one-word response, or on a simulated run that violates the eval's own rule, so the suite can certify a run that did not do the work. Each repaired check lands with a `tests/agent_spinner/script_tests/grade_cases.sh` case that proves its fail branch fails.

## Context

The 2026-11-14 coverage audit staged every fixture through `evals/stage.sh`, graded it with no agent action, and simulated violating runs for some evals; the checks below passed where they should fail.

- **Sweep sampling.** `sweep_sampling_needs_user` and `sweep_rewrite_hunk_blocks_sampling` assert that every changed page holds exactly one check row. `initial_check_rows_for_path` counts rows in any state, and `diff --add-checks` creates them unprompted, so a run that appended a line to every page, ran `diff --add-checks`, closed every check row with `--classify 'sampled out'`, and dispatched no checker scored 4/4 on both. `references/recipes/prose-sweep.md` allows a sampled checker set only on the user's word. Separately, `offers_sampling` searches the whole run text for its choice cue and matched a quoted gate line in a run that said sampling was not used.
- **`changed_false_still_checked`.** Its brief check matches the producer brief the fixture already staged, so a one-sentence run with no ledger action scored 3/3.
- **`blind_pass_by_prompt`.** It greps only `briefs/` for the hypothesis, while `request.txt`, `intent.md`, and `announcement.txt` in the same run directory can quote it. SKILL.md `<containment>` keeps text a blind pass must not see out of the workspace.
- **`judge_flaws_capped`.** The staged judge returns already carry three or fewer flaws, so the cap check passes on a no-op.
- **`inline_floor`.** `ran_a_checking_pass` falls back to matching `check(ing)? pass|refute|re-?check` in the response.
- **`payload_cap`.** "A brief lists the trimmed identifiers" and "a synthesis brief was written" both pass on the fixture's own survey briefs. The fixture also contradicts itself: its briefs check against a `bin/tool.sh` it never stages, its survey returns say `pass` while carrying major and blocker findings, and gamma's quoted line and `# legacy` heading are missing from `docs/gamma.md`.
- **`unreturned_bound`.** Its fixture sets the row's `unreturned` state itself through `ledger_set_state`, so a single sentence passes.
- **Report-opening helpers.** The tier alternative behind "opening sentence carries the verdict and the tier" accepts "fan-out", a shape name, and `DISPATCH_ARITH` accepts "run against".
- **Go-ahead cue.** `ASKS_GO_AHEAD` contains bare `decide` and `confirm`, which match the standard report heading "Decided on a helper's own authority" and the tally line "confirmations 0", so "asks for the decision" passes on any closed report; a Cursor `depth_one_level` run asked nothing and passed it. `judgement_surfaced` uses the same cue.
- **Probe delegation.** `probe_entry_has_capability_value` tests membership in all of a probe entry's values, so "the role probe records delegation as established" passed on a `probe.json` with `delegation_surface: assumed_absent` because its `concurrency` was established.
- **`payload_cap`'s response checks.** `cap|...` matches "capability" and `alpha` matches `docs/alpha.md`. A synthesis brief that relays the returns by path with a read-in-full instruction pastes nothing, so the skill asks for no cap there (`references/run-protocol.md`: "Relay upstream material ... by path with a read-in-full instruction, or paste it below a stated cap"), yet the brief checks demand a truncation notice.

## Approach

1. For both sweep-sampling evals, count a changed page as checked only when its first check row has an `accept` record from a validated return and a brief file, with no `classification` record for that label. For `sweep_sampling_needs_user`, also require that no sampled-out classification exists. Make `offers_sampling` drop each sentence that negates sampling ("not offered", "not used", "sample-dropped") before it gathers its cues, and keep the announcement in scope, since the prompt asks the run to state its choices there; a Cursor `sweep_rewrite_hunk_blocks_sampling` run that wrote "Sampled checker set: not offered" failed "offers no sampled checker set" on those cues.
2. `changed_false_still_checked`: require a ledger `check` record and a run-written brief for `docs/alpha.md`.
3. `blind_pass_by_prompt`: grep every file under `.agent_spinner/` that the blind row could read for the hypothesis.
4. `judge_flaws_capped`: stage one judge return with four flaws, so the cap has something to cut.
5. `inline_floor`: require an accepted check row whose return file post-dates the producers' return files, and drop the phrase fallback.
6. `payload_cap`: read both brief checks from the synthesis row's own brief only, and make them branch-aware: the by-path branch passes when the synthesis row relays all three labels and its brief names each return path with "in full" and pastes no return body, and the paste branch requires a numeric cap, the cut notice, and the trimmed identifiers. Anchor the two response checks (`payload cap|capped at [0-9]+`, `trimmed[^.]{0,60}survey:(alpha|beta|gamma)`) and apply them only on the paste branch. Make the fixture coherent: stage a `bin/tool.sh` that takes `--workers` and rejects `--jobs`, add the quoted line under a `# legacy` heading in `docs/gamma.md`, and set the survey verdicts to `fail`.
7. `unreturned_bound`: stage the row as `dispatched` with a back-dated start, so the run has to produce the `unreturned` state through `accept --wait`.
8. Anchor the opening-tier alternative to tier vocabulary (`spawned[- ]roles|inline floor|tier`) and drop "run against" from `DISPATCH_ARITH`.
9. Drop bare `decide` and `confirm` from `ASKS_GO_AHEAD`, keeping cues that ask the user, and re-check `depth_one_level` and `judgement_surfaced` against it.
10. Make the probe delegation check read the `delegation_surface` key itself.
11. Re-run each touched eval on the default vendor and record the verdicts in `tests/agent_spinner/evals/README.md`.

## Acceptance

- `grade_cases.sh` carries, for each check repaired above, a case where a no-op or violating run fails it and a case where a compliant run passes it, and the suite passes.
- The audit's no-op probe, re-run by staging each touched eval and grading it with an empty response and no agent action, fails every repaired check.
- `tests/agent_spinner/evals/README.md` records the default-vendor verdicts of the touched evals after the change. An eval that now fails a compliant run's behaviour is recorded with the check it fails, and the grader fix is revisited before the task closes.
