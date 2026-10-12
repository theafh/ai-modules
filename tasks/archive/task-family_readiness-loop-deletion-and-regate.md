---
description: In task_auto_check, send any repair that deletes or weakens a frozen task commitment to the user, limit what each gate call reads, and challenge a ready from the last allowed call.
scope: plugins/ai_dev/skills/task_auto_check
created: 2026-10-03T15:54:08
updated: 2026-10-12T19:02:10
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
---

# Route commitment deletions to the user, limit what gate calls read, and challenge a last-call ready

## Goal

`task_auto_check` is the readiness loop. It runs `task_check` as its gate, through the `auto_gate_task` agent. Reviewer agents then propose repairs for the issues the gate raises, a verifier agent approves or rejects each proposal, and the loop applies the approved edits. The next round calls the gate again, until the task is `ready` or the loop stops. Before the first gate call, the loop freezes the task: it records the task as it stood, including its title and Goal, and judges every repair against that frozen state.

Three of the loop's rules change. Each is written once, in `task_auto_check` and its agents:

- An edit that deletes a commitment the frozen task carried, or narrows one, is a decision for the user at any size. The verifier never approves it as a repair.
- Every gate call judges the task file as it stands and reads only its admitted inputs, meaning the inputs its agent definition lists. It never reads helper transcripts, session and harness state stores, or earlier gate verdicts. It also never reads the loop's relay directory, where the loop keeps each helper's prompt and return as files.
- Today the loop challenges a `ready` verdict only when the run's first gate call returns it with nothing raised. In that citation refutation, the verifier checks whether each citation in the verdict supports the `clean` claim it backs. The refutation now also covers a `ready` reached on the last gate call the round cap permits.

## Context

- **Current state.** `<verification_standard>` in `plugins/ai_dev/skills/task_auto_check/SKILL.md` sets what the verifier may approve. It sends to the user only an edit group "that would remove the majority of the task body, delete an entire load-bearing section, or collapse either into a summary line or code pointer". `plugins/ai_dev/agents/auto_verifier_task.md` carries the same threshold in its rule beginning ``Route to a human, with decision `human_routed`, any proposal``. Below that threshold, the standing preference for the minimum sufficient edit lets a deletion win over a proof. When the gate flags a promise that no Acceptance item proves, deleting the promise is a smaller edit than adding the proof.
- **Deletion, observed.** In one run, the gate flagged several design rules the task committed to as promises that no Acceptance item proved. Its suggested fix offered proof, or a narrowing that parks the rest out of scope. The verifier settled that choice itself by deleting several groups of rules. It overrode a reviewer's evidence for proving one of them, dropped the gate's out-of-scope option, and sent nothing to the user. The body shrank by about a tenth, which is under the structural threshold. The deletions landed in a commit that named none of them. One deleted rule was a breadth gate the owner had asked for. Its justification lived outside the task file, where the verifier could not see it.
- **Re-gate, observed.** A re-gate is any gate call after the first in a run. In one run, the final `ready` came from a re-gate that searched the project's transcript store and extracted the full report of the gate before it. It checked that those issue phrases were gone and stamped `ready` on that basis. `auto_gate_task`'s `<inputs>` admit the task path, the skill paths, the project root, creation-time context, and a refuted-citation set, meaning the citations a refutation overturned. Its `<policy>` sets no limit on what else it may read.
- **Refutation at the cap, observed.** Another run reached `ready` on its last permitted gate call, and the loop accepted that clean verdict without challenge. Several of the verdict's `clean` lines cited nothing outside the task. The implementation later found several rule defects and an Acceptance item it could not stage. Today the `<gate>` trigger fires only on the first-call signature: the run's first gate call, a prior status of `open`, a `ready` stamp, an empty issue list, and every checklist line `clean`. Its passage gives that narrowness as a cost bound, which excludes a `ready` reached after repair rounds. [The finished gate-evidence task](task-family_gate-evidence-and-refutation.md) set that bound and shipped the evals `immediate_ready_citations_survive` and `immediate_ready_citations_overturn`. This task extends the trigger by one case.
- **Order.** Land after [the verbatim-relay task](task-family_readiness-loop-verbatim-relay.md). That task creates the relay directory and has the loop write each helper's prompt and return there as files. This task writes the frozen task copy into that directory, closes the directory to gate calls, and grades its prompt and return files in the evals below. That task's pointer-only rule says each prompt names its inputs by path and carries no summary of them. The rule already keeps loop state out of every gate prompt, so this task adds the matching limit on what the gate itself reads.

## Approach

1. **Route commitment deletions.** Rewrite the structural sentence of `<verification_standard>` in place. That is the sentence beginning `Treat an edit group that would remove the majority of the task body`. Its new form defines one class of edits that the user decides, at both scales:
   - An edit group that removes most of the body, deletes a load-bearing section, or collapses either into a summary line or code pointer belongs to the class.
   - Any edit that deletes a requirement, rule, constraint, promise, or Acceptance item the frozen task carried, or narrows one so it promises less, also belongs to it.

   The verifier returns such an edit as `human_routed`. The route carries the affected passages verbatim and the gate's fix text for the issue. It also names the options in play: prove it, narrow it with an `**Out of scope:**` deferral naming its owner or an explicit rejection, or delete it. The loop reports the route through the `<structural_split_boundary>` channel, which stops that repair and reports the run as stuck for the user, and applies none of it. Three kinds of edit stay on the ordinary repair path:

   - A refresh that renames, relocates, or re-anchors a detail the code moved stays ordinary.
   - A supersession that the interaction-scan carve-out already requires stays ordinary. That carve-out makes the verifier keep the replacement of an Acceptance item that a confirmed interaction with the code has made false.
   - A change to text that an earlier round of the same run added stays ordinary.

   The verifier's own narrowing of a proposal to its intent-safe core, the part that keeps the frozen intent, stays as it is. Rewrite the verifier's routing rule in place to match.
2. **Give the verifier the frozen copy.** In the `<freeze>` step, write the task file as frozen into the relay directory as `frozen-task.txt`. Name that file in every verifier prompt. The verifier decides from that file what the frozen task carried.
3. **Bound the gate's reads.** Add one `<policy>` rule to `plugins/ai_dev/agents/auto_gate_task.md`. The gate judges the task file as it stands. It reads only its admitted inputs, plus what its walk through the readiness checklist reaches in the project's code, skills, and guardrail docs. It never searches or reads helper transcripts, session or harness state directories, the loop's relay directory, or an earlier gate verdict. Add an `isolation:` line to the verdict's `## Evidence` section. The line reads `confirmed`, or it names each read outside those bounds. Rewrite `<gate>` so the loop re-runs, once and in a fresh call, any verdict that names such a read, and uses the re-run's verdict.
4. **Refute a last-call ready.** Rewrite the trigger passage of `<gate>` in place. This is the passage that decides when the loop sends a `ready` verdict's citations to the verifier for refutation. The refutation fires on the first-call signature. It also fires on a `ready` verdict from the last gate call `<loop_bounds>` permits, meaning the call after which no further round fits under the cap. It fires on no other `ready`. The passage states the new cost bound: at most one verifier call and one gate call beyond the cap, and only on runs that reach `ready` on that last call.
   - When every citation survives, the stamp stands and the run continues as the passage already says.
   - When the verifier refutes a citation at the cap, the loop re-gates once with the refuted-citation set and applies no body repair. It then proceeds to `<finalize_mechanical_lint>`, the final mechanical lint step, as the cap path does. It stops through the stuck channel at the status that gate writes. The stuck channel is the loop's report of what it leaves for the user.

   Point `<loop_bounds>` at this exception, so its hard cap names the one refutation beyond the cap. Keep the sentence the script test pins under the label `immediate ready path routes the repeated-link round before finalize`.
5. **Report.** Extend `<output_contract>` so the report names the refutation trigger that fired, each deletion decision handed to the user with its options, and each isolation re-run, meaning each re-run caused by an out-of-bounds read.
6. **Record the rules.** Update `wiki/concepts/agent-delegated-automation.md` through the wiki skill family. `### Nothing is resolved silently` names the deletion or narrowing of any frozen commitment, and `### The verifier refutes by default` names the last-call case.
7. **Prove it.** Add three evals to `tests/task_auto_check/evals/`. Each gets a fixture under `evals/fixtures/`, an `evals.json` entry, `stage.sh` and `grade.sh` arms, and a place in the runner's `DEFAULT_IDS` list.
   - `committed_rule_deletion_routed` stages a task whose Approach commits to three named rules while its Acceptance proves one, so the gate flags two unproven promises.
   - `last_call_ready_refuted` stages a task that needs one repair round and runs it with "max rounds 2", so `ready` arrives on the last permitted call.
   - `regate_isolated` stages a task that needs one repair round. A decoy gate verdict from an earlier run sits under another directory in `.task_auto_check/` and claims every issue cleared, while the task keeps a defect that a fresh walk finds.

   Add one check to the `repair_to_ready` grader arm as the narrowness control, which shows that a `ready` reached before the cap draws no refutation. Write the graders under TESTING.md's `## Test Design Principles`, and prove the evals under TESTING.md's vendor rule.

## Acceptance

1. `<verification_standard>` states one class of edits that the user decides, covering both scales, together with what its route carries and the three kinds of edit that stay on the ordinary path. Searching the skill for the threshold finds one canonical statement, and the sentence beginning `Treat an edit group that would remove the majority of the task body` is superseded.
2. The verifier's routing rule matches that class and names `frozen-task.txt` as its evidence of what the frozen task carried. `<freeze>` writes that file.
3. `auto_gate_task.md` carries the read-boundary rule once and the `isolation:` line in `## Evidence`. `<gate>` re-runs once any verdict that names an out-of-bounds read.
4. The `<gate>` trigger passage states both triggers, the cost bound beyond the cap, and the stop after a refutation at the cap, in one canonical statement. `<loop_bounds>` points at that exception. The phrase ``never on a verdict that raised issues or on a `ready` reached after repair rounds`` no longer appears, and `tests/task_auto_check/script_tests/run.sh` still passes.
5. `<output_contract>` requires the trigger that fired, each deletion decision with its options, and each isolation re-run.
6. `committed_rule_deletion_routed` passes. Each of the three committed rules is still found verbatim by grep in the final task file. Every verifier return in the relay directory that touches the two unproven rules records them `human_routed`, or approves an added proof.
7. `last_call_ready_refuted` passes. The relay directory holds a citation-mode verifier return after the second gate return. The final status reads `ready` only when every citation in that return reads `survived`.
8. The `repair_to_ready` control passes with its new check. Its `ready` arrives before the cap, and no return in its relay directory carries `mode: citation`.
9. `regate_isolated` passes. Every gate prompt file carries only the admitted inputs, and no line of forty characters or more copied from an earlier relay return. Every gate return reads `isolation: confirmed`. The first gate return raises the planted defect.
10. The concept page names the deletion class and the last-call refutation, and the update ran through the wiki skill family.
11. Before the commit, a manual read of every changed shipped file and of this task's own diff finds no session, company, or project name, and no denylist is committed.
