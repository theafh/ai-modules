---
description: "Let task_auto_check replace a frozen Acceptance item that names no checkable result with checks proving the same promise, and say that a user route stops only the repair it governs."
scope: plugins/ai_dev/skills/task_auto_check
created: 2026-11-15T06:22:10Z
updated: 2026-11-15T06:22:10Z
status: open
reported-by: Andreas Hoffmann
---

# Let task_auto_check replace a frozen Acceptance item that cannot be checked

## Goal

When a frozen Acceptance item names no checkable result, such as "The retry behavior works properly.", `task_auto_check` replaces it on the ordinary repair path with checks that prove the same promise. The replacement is allowed only when the verifier's written pairing maps every promise the item made to a replacement check and the Goal still has a check proving it. An item that promises more than the Goal, or more than the replacement checks prove, still goes to the user. The skill also states that a user route stops only the repair it governs, so the run's other repairs continue and the gate decides the final status.

## Context

- **Two rules disagree.** `<frozen_intent>` in `plugins/ai_dev/skills/task_auto_check/SKILL.md` lets the loop "make acceptance checks verifiable". `<verification_standard>` sends to the user "any edit, at any size, that deletes a requirement, rule, constraint, promise, or Acceptance item carried by `frozen-task.txt`, or narrows it so the task promises less", and keeps three kinds of edit on the ordinary path: a refresh of a detail the code moved, an interaction-scan supersession, and a change to text an earlier round added. The routing rule in `plugins/ai_dev/agents/auto_verifier_task.md` says the same, starting "For that readiness-loop path, keep three kinds of edit on the ordinary repair path". Replacing an unverifiable item deletes it, so the verifier has to pick one rule.
- **Why the route exists.** [The commitment-routing task](archive/task-family_readiness-loop-deletion-and-regate.md) introduced the route so that the minimum-change preference cannot silently trade a commitment for a smaller proof set. The written pairing keeps that protection: a replacement that drops part of the item's promise is still a narrowing, and it still goes to the user.
- **What happened.** Five fixtures stage an unverifiable frozen item: `repair_to_ready`, `relay_by_path`, `stray_hunk_reverted`, and `guard_rebaseline_after_gate` under `tests/task_auto_check/evals/fixtures/`, plus `verifier_failure_user_stop`. Across the eight 2026-11-15 runs of the first four, the verifier split three ways:
  - In five runs it replaced the item as a clarification.
  - In Claude's `repair_to_ready` run it kept the item, added proofs beside it, and routed the deletion to the user. The second gate then stamped `ready` with that decision still open.
  - In Cursor's `relay_by_path` and `guard_rebaseline_after_gate` runs it routed the rewrite to the user, and the run stopped at `checked` with the vague item in place.
  The graders of `repair_to_ready`, `relay_by_path`, and `guard_rebaseline_after_gate` expect the item replaced and the task `ready`.
- **The stop scope is unclear.** `<verification_standard>` says "Stop that repair, apply none of it, and report the run as stuck through `<structural_split_boundary>`". That boundary stops "the auto-edit path for that issue", while the skill words a whole-run stop as "for the run" elsewhere: `<invalidated_premise_boundary>` stops "the body-repair path for the run", and `<intent_drift_boundary>` halts "the auto-repair path for this run". Claude read the route as stopping one repair, and Cursor read it as stopping the run.
- **Real commitments.** `committed_rule_deletion_routed` stages three concrete rules whose deletion must go to the user. `fidelity_rejects_drift` stages "The API is protected from abusive clients.", which promises more than its per-user rate-limiting Goal, so its narrowing stays a user decision under this task too.

**Settled here.**

- **The fourth kind.** The fourth ordinary-path kind follows from `<frozen_intent>`'s own "make acceptance checks verifiable" and from the repo's graders, which expect the replacement.
- **The stop scope.** A route stops only the repair it governs, because `<structural_split_boundary>`, the channel the route reports through, stops "the auto-edit path for that issue".

Land this task after [the return-layout task](archive/task-family_gate-verifier-return-layout.md). That task adds the approved edit's `reason:` field, which carries the pairing here, and it edits the same verifier template.

## Approach

1. Rewrite the "Keep three kinds of edit on the ordinary repair path" sentence of `<verification_standard>` in place as four kinds. The fourth is the replacement of a frozen Acceptance item that names no checkable result by checks that prove the same promise, when the pairing shows each promise of the item covered by a replacement check and the Goal still proved. State that an item promising more than the Goal, or more than its replacement checks prove, stays on the user route. Point `<frozen_intent>`'s "make acceptance checks verifiable" at that sentence.
2. Rewrite the matching three-kinds sentence of `auto_verifier_task.md`'s routing rule in place, and have an approved fourth-kind edit record the pairing of each promise to its replacement check in its `reason:` field.
3. Rewrite "Stop that repair, apply none of it, and report the run as stuck" in `<verification_standard>` in place. The new text says that a route applies none of that repair, and that the loop proposes no repair for a routed issue again in this run. The round's other approved repairs and later rounds continue. When the gate's verdict still counts the routed issue as blocking, the run ends at `checked`. When the verdict no longer counts it, the run may reach `ready`. Either way, the report carries each routed decision through the stuck channel as the user's call.
4. Add static pins for the fourth kind and the stop scope to `tests/task_auto_check/script_tests/run.sh`, each with a mutation case that fails when the sentence reverts.

## Acceptance

1. `<verification_standard>` and the verifier's routing rule name four ordinary-path kinds, `<frozen_intent>` points at them, and the three-kinds sentence no longer stands alone in either file.
2. `<verification_standard>` states that a route stops only its repair, that a routed issue is not repaired again in the run, and how the gate's verdict decides the end status.
3. `bash tests/task_auto_check/run_all.sh` passes, including the new pins and their mutation cases.
4. `repair_to_ready`, `relay_by_path`, and `guard_rebaseline_after_gate` run on the default vendor and replace the unverifiable item, with each replacement's `reason:` carrying the pairing. `committed_rule_deletion_routed` and `fidelity_rejects_drift` run on the default vendor and still route their frozen commitments to the user. The verdicts are recorded in `tests/task_auto_check/evals/README.md`. If a run routes an unverifiable item or replaces a real commitment, the record names the run and the item, and the task stays open.
