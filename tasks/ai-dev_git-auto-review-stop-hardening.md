---
description: "Harden auto-loop stop conditions: user-only round-cap authority, delta-only re-review from round 2, a line-level scope anchor, a per-round continue justification, and a report written at every stop."
scope: plugins/ai_dev
created: 2026-11-09T09:41:11Z
updated: 2026-11-09T09:41:11Z
status: open
reported-by: Andreas Hoffmann
---

# Harden auto-loop stop conditions so the orchestrator cannot walk past them

## Goal

`git_auto_review` and the task-family loops stop where their rules say they stop. An orchestrator-composed prompt cannot raise a loop's round cap; only the invoking user's request can. From round 2 the gate re-reviews the delta since the prior round, not the whole change, so unchanged code cannot keep generating new findings. A finding on a line the change did not add or modify is a follow-up task proposal, not a fix. Each round records why it continues, and every stop writes `report.txt` with the cap source, the per-round continue reasons, and the unapplied findings. The prior severity-floor decision stays in force: `inferred` and should-fix findings remain eligible for a fix while the loop is under its cap.

## Context

- **Observed run.** A recent `git_auto_review` run over a large change in a downstream repository completed 10 rounds plus an aborted 11th, raised 28 qualifying findings, every one `non_blocking`, and landed 25 regression reproductions. The user asked why 11 rounds ran when the default cap is 5.
- **The cap was overridden by the orchestrator.** `<inputs>` accepts the literal phrase `round cap <N>` "written anywhere in the prompt". The orchestrator composes the gate and fixer prompts, so it wrote `round cap 8`, then `10`, then was on `11` without any user instruction. The cap is the loop's designed brake; the override handed the brake to the party the brake exists to restrain.
- **The re-review was not a delta review.** The `<role>` says the loop "re-reviews the delta", but `<round_driver>` says round 2+ uses "the same target shape as round 1". The gate therefore re-read the whole commit plus working tree every round and kept surfacing new `inferred`/should-fix items from unchanged code. That contradiction is the source of the long tail.
- **The scope anchor is elastic.** `<scope_anchor>` admits a finding that concerns "lines the change added or modified, or behaviour the change's intent covers". The second clause admitted an unmodified documentation bullet, an unmodified watcher branch, and an unmodified warm-up function. Those were the findings that pulled the loop into adjacent cleanup.
- **The self-written stop did not fire.** It counts only two consecutive rounds whose findings all sit in code the loop wrote. Findings on the original commit's code never count, so a large first change can run indefinitely without meeting it.
- **No round recorded why it continued.** The per-round record has `decision <continue|stop>` but no reason. A round could continue on a non-blocking nit without saying so.
- **`report.txt` was never written.** The run was stopped by the user, and the orchestrator ended without the terminal report the `<relay>` contract requires. The relay held gate, fixer, verifier, and round-diff files but no `report.txt`.
- **The severity-floor decision stays.** A prior repo decision deliberately removed a severity floor so `inferred` and "should be fixed" findings get fixed. This task does not re-introduce a floor, and it does not change `git_review`'s headings or labels.
- **Existing tests to extend.** `tests/git_auto_review/evals/` carries `honours_round_cap`, `stops_on_self_written_code`, `lists_preexisting_issue`, `lists_scope_extension`, and `fixes_inferred_and_should_fix_findings`; `tests/git_auto_review/script_tests/run.sh` carries `s4_convergence_labels_single_source` and `s5_carryover_blocks`; `plugins/ai_dev/skills/task_auto_check/SKILL.md` `<loop_bounds>` carries the same "unless the user prompt supplies a positive integer override" pattern.

## Approach

1. **Make cap authority user-only.** In `plugins/ai_dev/skills/git_auto_review/SKILL.md` `<inputs>`, replace the "written anywhere in the prompt" wording with: the phrase is read only from the invoking user's request; an orchestrator-composed gate or fixer prompt that carries it is a contract violation, and the run uses the default cap and records `cap-source default`. Record `cap-source user|default` in the final-state block. Apply the same sentence to `plugins/ai_dev/skills/task_auto_check/SKILL.md` `<loop_bounds>` so its cap cannot be raised by an orchestrator either.
2. **State the cap as a hard ceiling.** In `<stop_rule>`, add: after the cap is reached the run stops and writes `report.txt`; no finding reopens a round. Keep the existing default of 5 and the user-supplied override as the only exception.
3. **Make round 2+ a delta review.** In `<round_driver>`, replace "with the same target shape as round 1" with: from round 2 the gate target is the delta since the prior round's snapshot (`round-r<N-1>.diff.txt` plus the current working tree); the prior gate return supplies the prior findings set; a finding whose `location` is outside the delta is re-listed by tag but not newly raised. Keep the full-change review on round 1 only.
4. **Tighten the scope anchor to changed lines.** In `<scope_anchor>`, require the finding's `location` to intersect a line the change added or modified, or a line in a path the change created. A behaviour-level finding on unmodified code becomes a follow-up task proposal. Keep the task-anchored `## Goal`/`## Acceptance` read for behaviour the change's intent covers, but only when the location sits in a changed path.
5. **Require a continue justification.** Add a `continue-reason` field to the per-round record in `<relay>`: a `continue` decision names the qualifying finding and why it cannot be deferred; an empty reason forces `stop`. Do not force a stop merely because the findings are `non_blocking`; the cap and the delta review are the brakes, and the severity-floor decision stays in force.
6. **Write the report at every stop.** In `<report>`, require `report.txt` on every stop path, including a user abort, a helper failure, and the cap. Add a final check: before returning, verify `report.txt` exists and carries the final-state block. The final-state block gains `cap-source <user|default>`.
7. **Pin the text and behaviour in the harness.**
   - Extend `s4_convergence_labels_single_source` in `tests/git_auto_review/script_tests/run.sh` to assert the user-only override sentence, the hard-ceiling sentence, the delta-review sentence, the line-level scope-anchor sentence, and the `cap-source` and `continue-reason` tokens in both skills.
   - Extend `honours_round_cap` in `tests/git_auto_review/evals/` with a fixture whose user prompt carries no `round cap` phrase and whose orchestrator-composed gate prompt does; assert the run uses the default 5 and records `cap-source default`. Keep the existing user-override run.
   - Add an eval `delta_re_review_excludes_unchanged_code`: round 1 fixes an in-scope defect; round 2's gate cites a second finding on an unmodified file outside the delta; assert the second finding is listed as a follow-up and its file stays byte-identical.
   - Extend the `fixes_in_scope_bug` grade arm to assert its round-1 per-round line carries `continue-reason`, so a continuing round records why it continued.
   - Record each new or changed eval in `tests/git_auto_review/evals/README.md` and `tests/git_auto_review/RUNBOOK.md`, and run the named evals on the default Cursor `auto` vendor.
8. **Bump versions.** Raise `version` in `plugins/ai_dev/skills/git_auto_review/SKILL.md` and `plugins/ai_dev/skills/task_auto_check/SKILL.md` in the implementing commit, per the standing repo rule.

**Out of scope:**

- Re-introducing a severity floor, or changing `git_review`'s headings, its `verified`/`inferred` labels, or how it sorts findings. The prior severity-floor decision stays as made.
- Changing `git_review`'s review criteria or its own target shapes.
- Changing `task_auto_check` beyond the cap-authority sentence and its harness pins.
- The downstream change that exposed the run; this task hardens the loop, not that change.

## Acceptance

- `rg -F "read only from the invoking user's request" plugins/ai_dev/skills/git_auto_review/SKILL.md` and `rg -F "orchestrator-composed" plugins/ai_dev/skills/git_auto_review/SKILL.md` both find the new cap-authority text; the same sentence appears in `plugins/ai_dev/skills/task_auto_check/SKILL.md` `<loop_bounds>`.
- `rg -F "cap-source" plugins/ai_dev/skills/git_auto_review/SKILL.md` finds the final-state field, and `rg -F "continue-reason" plugins/ai_dev/skills/git_auto_review/SKILL.md` finds the per-round field.
- `<round_driver>` no longer says "same target shape as round 1"; it names `round-r<N-1>.diff.txt` as the round-2+ target and states that a finding outside the delta is not newly raised.
- `<scope_anchor>` requires the location to intersect a changed line or a created path; a finding on unmodified code is a follow-up task proposal.
- `bash tests/git_auto_review/script_tests/run.sh` passes with the extended `s4` scenario.
- `python3 tests/git_auto_review/evals/run.py --force honours_round_cap delta_re_review_excludes_unchanged_code fixes_in_scope_bug` passes on the default Cursor `auto` vendor, and each result is recorded in `tests/git_auto_review/RUNBOOK.md`.
- The orchestrator-only override fixture stops at 5 rounds and its `report.txt` final-state block carries `cap-source default`; the user-override fixture still stops at 2 and carries `cap-source user`.
- The `delta_re_review_excludes_unchanged_code` fixture leaves the unmodified file byte-identical and lists its finding as a follow-up.
- `report.txt` exists at every stop path exercised by the harness, including the cap and helper-failure fixtures.
- `make lint` and `make test` pass.
