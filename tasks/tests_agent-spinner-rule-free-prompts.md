---
description: "Rewrite the agent_spinner eval prompts that state the rule their eval is named for, so each prompt asks only for the job and the eval shows the skill drives the behaviour."
scope: tests/agent_spinner/evals
created: 2026-11-14T16:08:26Z
updated: 2026-11-26T06:29:11Z
status: ready
reported-by: Andreas Hoffmann
---

# Take the rule out of the agent_spinner eval prompts that state it

## Goal

Each agent_spinner behavioural eval asks for the job and leaves the behaviour under test to the skill. When a prompt states the rule its eval is named for, the eval still passes with that rule deleted from the skill, so it cannot show that the skill drives the behaviour. After this task those prompts describe only the user's request, the graders keep checking the substance on disk, and the evals' verdicts are re-recorded on the default vendor.

## Context

`tests/agent_spinner/evals/evals.json` holds each eval's `prompt`. The 2026-11-14 coverage audit found prompts that hand the worker the rule, for example `ruling_applies_to_class`, whose second sentence keeps only its report request: the live prompt "I rule that `utilize` becomes `use` in all three pages. Apply that ruling to all three instances, record one disposition per instance citing the ruling, and report the run." reduces to "I rule that `utilize` in `docs/alpha.md` becomes `use`. Report the run." so the prompt names one instance and the run must generalize the ruling and build the ledger's dispositions itself, with no disposition instruction left in the prompt; `survived_lenses_labelled_recall` gives the exact label the grader looks for. Find the full set at implementation time by reading each prompt against the eval's `id` and its expectations and selecting the prompts that state the expected behaviour rather than the request. At the time of writing the set included `ruling_applies_to_class`, `stamp_routed_on_any_rewrite`, `stamped_target_routed_to_owner`, `verifier_brief_carries_no_preference`, `blind_pass_by_prompt`, `survived_lenses_labelled_recall`, `beyond_brief_find_reported`, `known_false_control_caught`, `remediator_refutes_false_finding`, `committed_rule_deletion_surfaced`, `changed_false_still_checked`, and `role_depth_recorded`, as an illustration of the shape and not a closed list.

A prompt may still state what a real user would say, such as a scope, a constraint, or a decision the user already made; the rewrite removes only the instruction that is the skill's job. `sweep_rewrite_hunk_blocks_sampling` showed the opposite failure, a prompt sentence that contradicted the expected behaviour, and it is fixed separately.

[The vacuous-graders task](archive/tests_agent-spinner-vacuous-graders.md) also changes `changed_false_still_checked` and `blind_pass_by_prompt`. Land that task first, so each eval's grader can fail before its prompt stops carrying the rule.

## Approach

1. Select the prompts as described above and record the selection, with each prompt's removed sentence, in `tests/agent_spinner/evals/README.md`.
2. Rewrite each selected prompt to the request alone, keeping every fact the fixture needs the worker to know — file paths, the request's scope, a constraint, and a decision the user already made. Apply one test to each sentence: a sentence that states an answer the run can derive from the staged tree — which file differs from the baseline, what the stamp records, what the control returned, which class a ruling covers — goes, because the run must establish that answer itself. A pointer at material the request forces the run to read stays, and only the instruction about how to treat that material goes. Two worked cases fix the boundary: `changed_false_still_checked` loses "for a file that differs from the baseline" and keeps the writer's return and the file, so the run's own diff must establish the change; `verifier_brief_carries_no_preference` reduces to "Write the verifier's brief over the two reviewer returns at reviews/a.md and reviews/b.md, against my own notes in notes.md, and report the run." — it names the notes as material the brief is written against, so the request forces the read, and loses "Keep notes.md's preference out of the brief", so the run meets the preference and the skill must keep it out of the brief on its own. Any phrasing that makes the notes material the brief is written against satisfies this case. No fixture edit is permitted for this task: where no prompt rewrite keeps an eval falsifiable, record that eval in the README as a skill gap with the failing check named, as Acceptance item 2 already requires, rather than staging a different tree.
3. Leave each grader as it is unless the rewrite reveals a check that matched the prompt's own wording, in which case anchor the check to the run's output.
4. Run every rewritten eval on the default vendor and record the verdicts.

## Acceptance

- The `## Context` selector is re-run over every prompt in `evals.json` at implementation time, and each prompt it finds appears in a `## Prompt selection` section of `tests/agent_spinner/evals/README.md`, recorded there as selected with its removed sentence or as request-only with the reason it states only the request. Each of the twelve ids named in `## Context` appears as an entry under that heading, so `rg -n '^## Prompt selection$' tests/agent_spinner/evals/README.md` finds the section and reading that section finds all twelve ids; an id met only in `## Signal per eval` or `### Recorded results` does not count. This item pairs with the item that greps `evals.json` for each recorded sentence: every entry marked selected names a sentence that grep no longer finds.
- Each selected eval's prompt no longer contains the sentence recorded as removed, and a grep for each recorded sentence in `evals.json` finds nothing.
- The README records the selection, the removed sentences, and the default-vendor verdicts after the rewrite. An eval that now fails is recorded as evidence that the skill does not yet drive that behaviour, with the failing check named, and it is not reworded back into the prompt.
- Each grader that Approach step 3 re-anchored has a new case in `tests/agent_spinner/script_tests/grade_cases.sh` that stages the mistake that check names and asserts its `FAIL` line, `bash tests/agent_spinner/script_tests/grade_cases.sh` exits 0 with those cases passing, and `tests/agent_spinner/evals/README.md` names each changed check with the run artifact it now reads. A grader the rewrite left unchanged needs no new case. An eval is recorded as evidence that the skill does not drive its behaviour only after its rewritten prompt still names the fixture's request and its changed check fails on its new case.
