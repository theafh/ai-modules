---
description: "Let git_auto_review fix every finding under git_review's three finding headings, inferred and should-fix ones included, so a run lands those fixes instead of handing them back."
scope: plugins/ai_dev/skills/git_auto_review
created: 2026-10-29T23:50:26
updated: 2026-10-29T23:50:26
status: open
reported-by: Andreas Hoffmann
---

# Let git_auto_review fix every finding the review says to fix

## Goal

`git_auto_review` treats every titled finding its gate files under `What is critical`, `Bugs it may introduce`, or `What should be fixed though it is not a clear bug` as eligible for an automated fix, whether `git_review` labelled it `verified` or `inferred`. The refute-by-default triage in `auto_verifier_git` and the fixer's reproduction stay the evidence bar that decides which of those findings actually get fixed. A run then lands the small, concrete fixes the review names, and the user no longer has to ask for them by hand after the loop stops.

## Context

The **Severity floor.** in `plugins/ai_dev/skills/git_auto_review/SKILL.md` (the `<severity_floor>` block inside `<convergence>`) admits a finding only from `What is critical`, or a `verified` finding from `Bugs it may introduce`. It lists every `inferred` bug and every finding under `What should be fixed though it is not a clear bug` without fixing it. In practice that keeps most of what the review finds out of the loop. In the six default-branch runs in Cursor on 2026-10-29, the floor stopped four runs after round 1 with findings unfixed and held back further findings in the other two. The excluded findings were concrete and small: a test that no longer pinned the recipe it claimed to cover, a stale count in a results record, a duplicated constant, a doc line naming the wrong scope, a script header missing an exit cause. In four of the six runs the user then asked for those fixes by hand, and in a fifth the follow-up tasks the run proposed for them drew the objection that a one-line text fix does not justify a task lifecycle. The standing repo rule to fix a small in-scope follow-up inline instead of filing a task points the same way.

`git_auto_review`'s other qualification conditions already filter what the floor was meant to guard. The **Scope anchor.** keeps out pre-existing issues and scope extensions, **Decisions.** holds every judgement call for the user, and `<lane_classification>` keeps out lines the working tree no longer carries. `auto_verifier_git` approves a finding only when its fix is real, minimum, scope-anchored, and safe, which is the evidence check an `inferred` label lacks. `auto_fixer_git` adds a reproduction for every fix that fails before the fix and passes after, and the **Regression ledger.** restores and retries a round whose reproduction fails. The floor therefore filters nothing those conditions leave unfiltered, apart from findings the review itself says should be fixed.

These passages and tests carry the floor:

- `plugins/ai_dev/skills/git_auto_review/SKILL.md`: the `<severity_floor>` block; the `<qualification>` sentence "only when all five conditions hold", which names **Severity floor.** as one of them; the **Tag permit.** sentence, which counts "the four conditions above"; and the classification sentence that lists "a severity-floor-excluded finding under the **Severity floor.**" as a non-qualifying class.
- `plugins/ai_dev/agents/auto_verifier_git.md`: the `<inputs>` bullet that reads the skill's "`<convergence>` qualification rule, **Scope anchor.**, and **Severity floor.**".
- `tests/git_auto_review/script_tests/run.sh`: the `s4_convergence_labels_single_source` scenario loops over five labels, `**Severity floor.**` among them.
- `tests/git_auto_review/evals/`: the eval `lists_non_qualifying_finding` stages one `inferred` finding under `Bugs it may introduce` and grades that the floor leaves it unfixed. The eval `triage_reports_status_and_reason` stages an `inferred` bug whose `Fix:` rewrites a whole module; today the floor drops it before triage, so the eval's "triage rejects the broader one" expectation never reaches triage.

[The branch-target task](ai-dev_git-auto-review-branch-target.md) edits other passages of the same files: `<inputs>`, `<orient>`, and `<lane_classification>` in the skill, the target bullets of the three agents, `tests/git_auto_review/evals/README.md`, and the `s3` scenario of `script_tests/run.sh`. The two tasks carry no build order, and whichever lands second applies its edits on top of the other's.

## Approach

1. **Remove the floor from qualification.** Delete the `<severity_floor>` block, and rewrite the `<qualification>` paragraph in place so a finding qualifies when four conditions hold: its `tag` permits qualification, it meets the **Scope anchor.**, it carries `lane` `working-tree lane`, and it is not held under **Decisions.**. Rewrite the **Tag permit.** sentence's condition count to match, and drop the severity-floor-excluded class from the classification sentence so its list names only the classes that remain. Keep the sentence stating that the gate verdict's `non_blocking` field is reporting-only, moved into `<qualification>`, because the `non_blocking` mark still enters no condition.
2. **Point the verifier at the remaining conditions.** Rewrite the `auto_verifier_git` `<inputs>` bullet so it names the `<convergence>` qualification rule and **Scope anchor.** without **Severity floor.**.
3. **Give a text-only defect a reproduction.** Add a rule to `auto_fixer_git`'s `<policy>`: when a finding's defect has no runtime behaviour to exercise, such as a wrong count, a stale description, or a duplicated literal, its reproduction is a command that checks the corrected text and fails on the pre-fix state, so every admitted finding can meet the existing reproduction rule.
4. **Rewrite the harness pins.**
   - In `s4_convergence_labels_single_source`, drop `**Severity floor.**` from the label loop and add an assertion that `SKILL.md` carries neither `<severity_floor>` nor `Severity floor`.
   - Replace the eval `lists_non_qualifying_finding` with `fixes_inferred_and_should_fix_findings`. Its fixture keeps the `inferred` bug in `report.py` and adds a second file with a text-only defect filed under `What should be fixed though it is not a clear bug`. Pre-seed `gate-r1.txt` with both findings and `gate-r2.txt` tagging both `closed`, through the mechanism `tests/git_auto_review/README.md` describes under `## Fixture mechanism`. Grade that both defects are fixed, `ledger.txt` holds one reproduction per finding, `report.txt`'s stop line names the no-qualifying-finding condition, and `HEAD` is unchanged. Rename the fixture directory, the `grade.sh` arm, the `evals/README.md` row, and the `RUNBOOK.md` session-log row with it.

**Out of scope:**

- Changing `git_review`'s headings, its `verified` and `inferred` labels, or how it sorts findings under them; `git_review` stays the only gate and owns those.
- Changing the **Stop rule.**, including the round cap and the stop on two consecutive rounds of findings in loop-authored code.

## Acceptance

1. `rg -F "Severity floor" plugins/ai_dev/skills/git_auto_review plugins/ai_dev/agents` and `rg -F "severity-floor" plugins/ai_dev tests/git_auto_review --glob '!**/.eval_cache/**' --glob '!**/workspace/**' --glob '!**/results/**'` both find nothing.
2. The `<qualification>` paragraph names four conditions, the **Tag permit.** sentence's count matches them, and the `non_blocking` reporting-only sentence sits in `<qualification>`.
3. `auto_fixer_git`'s `<policy>` carries the text-check reproduction rule from **Give a text-only defect a reproduction.**
4. `bash tests/git_auto_review/script_tests/run.sh` passes with the rewritten `s4` scenario.
5. `python3 tests/git_auto_review/evals/run.py fixes_inferred_and_should_fix_findings triage_reports_status_and_reason` grades both evals PASS on the default Cursor vendor. In `triage_reports_status_and_reason` the staged `inferred` finding now reaches triage and is rejected there, so `extra.py` stays byte-identical. A failure of that eval sends the implementer back to the triage evidence the fixture's `Fix:` gives `auto_verifier_git`, not to the floor.
6. `rg lists_non_qualifying_finding tests/git_auto_review --glob '!**/.eval_cache/**' --glob '!**/workspace/**' --glob '!**/results/**'` finds nothing.
