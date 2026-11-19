---
description: "Rewrite the agent_spinner eval prompts that state the rule their eval is named for, so each prompt asks only for the job and the eval shows the skill drives the behaviour."
scope: tests/agent_spinner/evals
created: 2026-11-14T16:08:26Z
updated: 2026-11-14T16:08:26Z
status: open
reported-by: Andreas Hoffmann
---

# Take the rule out of the agent_spinner eval prompts that state it

## Goal

Each agent_spinner behavioural eval asks for the job and leaves the behaviour under test to the skill. When a prompt states the rule its eval is named for, the eval still passes with that rule deleted from the skill, so it cannot show that the skill drives the behaviour. After this task those prompts describe only the user's request, the graders keep checking the substance on disk, and the evals' verdicts are re-recorded on the default vendor.

## Context

`tests/agent_spinner/evals/evals.json` holds each eval's `prompt`. The 2026-11-14 coverage audit found prompts that hand the worker the rule, for example `ruling_applies_to_class` ("Apply that ruling to all three instances") and `survived_lenses_labelled_recall`, which gives the exact label the grader looks for. Find the full set at implementation time by reading each prompt against the eval's `id` and its expectations and selecting the prompts that state the expected behaviour rather than the request. At the time of writing the set included `ruling_applies_to_class`, `stamp_routed_on_any_rewrite`, `stamped_target_routed_to_owner`, `verifier_brief_carries_no_preference`, `blind_pass_by_prompt`, `survived_lenses_labelled_recall`, `beyond_brief_defect_reported`, `known_false_control_caught`, `remediator_refutes_false_finding`, `committed_rule_deletion_surfaced`, `changed_false_still_checked`, and `role_depth_recorded`, as an illustration of the shape and not a closed list.

A prompt may still state what a real user would say, such as a scope, a constraint, or a decision the user already made; the rewrite removes only the instruction that is the skill's job. `sweep_rewrite_hunk_blocks_sampling` showed the opposite failure, a prompt sentence that contradicted the expected behaviour, and it is fixed separately.

[The vacuous-graders task](archive/tests_agent-spinner-vacuous-graders.md) also changes `changed_false_still_checked` and `blind_pass_by_prompt`. Land that task first, so each eval's grader can fail before its prompt stops carrying the rule.

## Approach

1. Select the prompts as described above and record the selection, with each prompt's removed sentence, in `tests/agent_spinner/evals/README.md`.
2. Rewrite each selected prompt to the request alone, keeping every fact the fixture needs the worker to know.
3. Leave each grader as it is unless the rewrite reveals a check that matched the prompt's own wording, in which case anchor the check to the run's output.
4. Run every rewritten eval on the default vendor and record the verdicts.

## Acceptance

- Each selected eval's prompt no longer contains the sentence recorded as removed, and a grep for each recorded sentence in `evals.json` finds nothing.
- The README records the selection, the removed sentences, and the default-vendor verdicts after the rewrite. An eval that now fails is recorded as evidence that the skill does not yet drive that behaviour, with the failing check named, and it is not reworded back into the prompt.
