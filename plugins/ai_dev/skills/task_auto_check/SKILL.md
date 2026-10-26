---
name: task_auto_check
description: Autonomously drive one task from open or checked to ready through task_check, verifier-approved body repairs, and final mechanical task-lint cleanup. Use when a user asks to auto-fix readiness issues, make a task ready, refresh a stale task against the current codebase, or run an autonomous readiness loop without implementing the task. A task whose premise the code invalidates stops the loop and surfaces deferral as the user's option.
version: 1.0.23
author: Andreas F. Hoffmann
license: MIT
---

# task_auto_check

<task_auto_check_skill>

<role>
task_auto_check is the opt-in autonomous readiness loop for one task file. It freezes the task's current title and Goal, runs one committed-intent drift check, uses `task_check` as the only readiness gate, and runs `auto_dryrun_task` before the gate of every ordinary repair round so the implementer's seat reads the task before anything is judged ready, then asks modular `auto_*_task` agents to propose and verify minimal task-body repairs until the task becomes `ready` or no verified intent-preserving repair remains. Before reporting ordinary stop results, it finalizes the target file with the base task linter and applies mechanically fixable lint repairs. It prepares a task for `task_implement`; it never implements the task's work and never closes or archives it.
</role>

<when_to_activate>
Activate when the user points at one task and asks for the task itself to be made implementation-ready:

- "Auto-check this task until it is ready."
- "Make `<task>` ready without implementing it."
- "Run the autonomous readiness loop on `<task>`."
- "Fix the readiness issues from task_check if they are safe."

Route to `task_check` when the user wants a single read-only readiness verdict. Route to the base `task` skill or `task_create` when the user wants to write or manually edit a task. Route to `task_implement` when the user wants the task's described code/docs work built. Route to `task_finish` for close-out and archive moves.
</when_to_activate>

<authority>
The base `task` skill owns the task-file format, lifecycle stamps, `<readiness_checklist>`, `<body>` repair rules, `<backward_move_guard>`, discovery, timestamp, lint rules, and the `<lint>` mechanically fixable finding set. `task_check` owns the ready/checked verdict and status write. Read both skills before running the loop, cite their rules by name, and keep this skill to orchestration and safe edits.
</authority>

<path_resolution>
Resolve the base `task` and `task_check` skills from the same plugin bundle as this skill when possible: this skill lives at `skills/task_auto_check/SKILL.md`, so sibling skills live under `../task/` and `../task_check/`. Resolve the helper agents by their published names, `auto_drift_task`, `auto_dryrun_task`, `auto_gate_task`, `auto_reviewer_task`, and `auto_verifier_task`, using the current harness's normal agent mechanism. When a harness exposes only file paths, those agents live in the same plugin at `../../agents/` relative to this skill directory.
</path_resolution>

<inputs>
The user supplies one task file path or one unambiguous task name. The optional user prompt may also supply:

- A max-round override, expressed as a positive integer such as "max rounds 2".
- Creation-time intent context, used only when the loop runs immediately after a task is drafted.
- An explicit request to use an available foreign-model reviewer stance. The default is single-model operation with no foreign-model stance.
- An optional `attested_intent` statement that a change to the title or Goal is deliberate, passed through to `auto_drift_task`.
</inputs>

<loop_policy>
<single_gate>
Use `task_check` verbatim as the gate. The loop consumes the structured verdict returned by `auto_gate_task`: task path, status stamp, prior status, ready boolean, per-item checklist record, issue list, and evidence labels. It does not compute a second readiness score and does not override `task_check`'s `ready` or `checked` stamp.
</single_gate>

<frozen_intent>
Freeze the original task's `# Title` and `## Goal` before the first gate call. When the user supplied creation-time intent, freeze that prompt alongside the title and Goal. Every proposal and every applied edit must preserve this frozen intent; the loop may clarify expression, add missing implementation context, or make acceptance checks verifiable, but it must not change what the task is for.
</frozen_intent>

<relay>
Keep the run's helper hand-offs under `<project-root>/.task_auto_check/<task-file-stem>/`. During `<freeze>`, create that relay directory, clear everything an earlier run left there for the same task-file stem, and create `.task_auto_check/.gitignore` containing `*`. Keep the relay directory in place after the run and name it in the report. Every relay artifact uses the `.txt` extension:

```text
.task_auto_check/<task-file-stem>/
  frozen-intent.txt
  frozen-task.txt
  attested-intent.txt
  freeze-lint.txt
  r<N>-<helper>-prompt.txt
  r<N>-<helper>.txt
  r<N>-pre-apply.txt
  r<N>-lint.txt
  r<N>-apply.diff.txt
  r<N>-refuted-citations.txt
```

`frozen-intent.txt` holds the frozen title, Goal, and creation-time intent. `frozen-task.txt` holds the complete task file at freeze time, byte for byte, and stays unchanged throughout the run. Write `attested-intent.txt` only when the run prompt supplies an `attested_intent`. `freeze-lint.txt` holds the freeze-time file-scoped linter output. Write `r<N>-refuted-citations.txt` from the citation-mode verifier return's refuted rows, byte for byte, only when citation mode refutes at least one citation. The `<helper>` token is `drift`, `dryrun`, `gate`, `reviewer-<stance>-<issue>`, `verifier`, or `delta`; `<issue>` is the gate issue number or `rl<k>` for a recorded `repeated-link` finding. A second call of one helper in one round takes a `-2` suffix.

Apply one pointer-only prompt rule to every helper call, including each dry-run call, each gate call, the freeze-time drift call, the citation-mode verifier call, the refuted-citation gate re-invocation, and the delta audit. Write each helper prompt before its call, send the helper exactly the text of that prompt file, and save the helper return byte for byte. Each prompt names its inputs by path and carries only what the called agent's `<inputs>` admits:

- A drift prompt names the task path, `frozen-intent.txt`, the project root, the base `task` skill path, and `attested-intent.txt` when that file exists.
- A dry-run prompt names the task path, the base `task` skill path, the project root, and `frozen-intent.txt`.
- A gate prompt names the task path, the `task_check` skill path, the base `task` skill path, the project root, `frozen-intent.txt`, and that round's `r<N>-dryrun.txt`. A gate re-invocation with refuted citations also names `r<N>-refuted-citations.txt`.
- A reviewer prompt names the task path, the gate return, its issue number or the `freeze-lint.txt` finding, `frozen-intent.txt`, the assigned stance name, and the base repair rule name the stance cites.
- A proposal-mode verifier prompt names the task path, the gate return, every reviewer return, `frozen-intent.txt`, and `frozen-task.txt`.
- A citation-mode verifier prompt names the gate return, `frozen-intent.txt`, and `frozen-task.txt` only. The verifier reads the `clean` content-lens citations from the gate return in place.
- A delta-mode verifier prompt names the task path, `r<N>-apply.diff.txt`, that round's proposal-mode verifier return, `r<N>-lint.txt`, and `frozen-task.txt`.

A prompt carries no digest, paraphrase, expected verdict, preference, merge instruction, or criterion or repair supplied by the orchestrator. When the orchestrator has a repair idea, send it to `auto_reviewer_task` as an emergent stance beside the standing stances.

A saved return holds every section exactly as the helper returned it, with no summary, elision, or pointer to other text standing in for any section's content. Write it once, as its call completes, and leave it as written for the rest of the run. A restore or re-application under `<audit_delta>` writes the task file and regenerates only `r<N>-lint.txt` and `r<N>-apply.diff.txt`, so every saved prompt and return keeps its bytes. A return whose output-contract section arrives summarized or missing is contract-violating output under `<agent_failure_policy>`.
</relay>

<intent_drift_boundary>
Invoke `auto_drift_task` once at freeze time, before the first `<gate>` call and any repair. That agent returns `drift` only when the working-tree `# Title` or `## Goal` broadens what the task is for compared with the last-commit baseline; narrowing, refinement, bug fixes, and resolved labeled open decisions classify `clean`. A `drift` classification is human-routed through the same surfaced stuck channel as `<structural_split_boundary>` and `<mechanical_lint_boundary>`: report the intention check that names the field `auto_drift_task` flagged in its `drifted_fields`, along with the recovered-versus-current evidence, then halt the auto-repair path for this run, leave the task body unchanged, and keep `<frozen_intent>` intact. The intention check reads `Attention: this task's Title appears to have already drifted from its original intent.` for title-only drift, `…this task's Goal appears…` for goal-only drift, or `…this task's Title and Goal appear…` when both drifted. Use the recovered origin as evidence for the human, not as an edit target; the loop never auto-repairs toward the recovered original intent. The agent's four classifications are exactly `clean`, `drift`, `low_confidence_clean`, and `unassessable`; `clean` and `low_confidence_clean` proceed without surfacing the intention check, and `unassessable` follows `<agent_failure_policy>`.
</intent_drift_boundary>

<invalidated_premise_boundary>
When the gate verdict's premise line reports the base premise check's invalidated outcome, meaning the codebase contradicts the task's reason to exist, stop the body-repair path for the run: a repair that rewrites a task to survive a dead premise changes what the task is for and breaks `<frozen_intent>`. Leave the body unchanged at the status the gate wrote, and surface the stop through the same human-routed stuck channel as `<structural_split_boundary>`, reporting the gate's contradiction evidence alongside the base rule's disposition options: close the task `deferred` through `task_finish`, re-scope the intent as a user-owned edit, or refute the finding with evidence and re-run. The loop presents these options and performs none of them; deferral is never automatic. Premise findings the gate labels drifted stay on the ordinary repair path and are refreshed against the current codebase.
</invalidated_premise_boundary>

<reviewer_stances>
Spawn `auto_reviewer_task` once per applicable stance. The standing stance set is selected lazily from the run's admissible issues, meaning the gate verdict's issues — confirmed dry-run findings included once they are gate issues — plus the `repeated-link` findings `<freeze>` recorded, and each stance cites the base `task` skill rule it applies by name:

- Self-sufficiency advocate: cite the base `<body>` self-sufficient / single-shot-ready rule. Select this stance only when the issue text itself names that rule, whether by the bar's name or by the stance's cited rule name.
- Minimum-change advocate: cite **Compact only to the implementable floor**.
- State-once advocate: cite **State once**.
- Decide-or-label advocate: cite **Decide or label**. Propose an evidence-grounded reconciliation of an open decision drawn from that rule's ordered evidence base rather than a bare relabel; when no evidence in that base settles the decision, propose surfacing it as a labeled decision with suggested options through the existing human-routed stuck channel rather than inventing a choice.
- Acceptance-contract advocate: cite the base `<body>` **Acceptance** contract.
- Rewrite-in-place advocate: cite **Rewrite in place, don't append**.
- Positive-reframe advocate: cite the base `<body>` positive, action-oriented authoring rule.
- Redact-by-generalizing advocate: cite **Redact by generalizing**.
- Boundary advocate: cite the base `<body>` **Declare exclusions as an Out of scope boundary** rule. Propose normalizing a variant exclusion phrasing to the canonical `**Out of scope:**` block, or reconciling a body-versus-boundary contradiction against the evidence per **Decide or label**; when no evidence settles which side wins, propose surfacing it as a labeled decision with options through the existing human-routed stuck channel rather than crossing or dropping the boundary silently.
- Grouping advocate: cite the base `<markdown_policy>` grouping rule and the base `<lint>` **Repeated-link react protocol**. This is the one stance a lint-originated `repeated-link` finding selects rather than a gate issue. Propose the reorganization that protocol defines, gathering the material about the counted target that belongs together into the one passage where it reads as one account, or, for a repeat inside one paragraph, naming the target again in plain text inside that paragraph, with the meaning of `## Goal` and the Acceptance contract unchanged. Surface the finding only with an organizational reason from that protocol: when the only reorganization would change Goal or the Acceptance contract, or no grouping keeps the body's meaning, propose no edit and surface the finding with that reason; when reorganizing reveals the body grew into separate concerns, route it through `<structural_split_boundary>` as a split summary.
- Interaction-scan advocate: cite the base `<readiness_checklist>` **Interaction scan** lens for the finding and the base `<body>` **Rewrite in place, don't append**, **Acceptance** contract, and **Edit items supersede the stale passage** rules for its repair. Propose the minimum body edit that refreshes the task against the interacting code the lens found, whether by reconciling a contradiction or accounting for an unattended interaction, and carry that refresh through every section the interaction touches, not Context alone. When the interaction makes an existing Acceptance item stale (it contradicts what that item promises, the way a shipped page-size cap contradicts a test asserting an over-cap page), superseding that Acceptance item is a required part of the repair per **Edit items supersede the stale passage**, not an optional add-on: noting the interaction in Context while leaving the now-false Acceptance item standing is an incomplete repair. When the interaction invalidates no existing item, add a new edit-supersedes Acceptance item that proves it is now handled. When no evidence in **Decide or label**'s ordered base settles the fix, propose surfacing it as a labeled decision with suggested options through the existing human-routed stuck channel rather than inventing a reconciliation.

Add emergent task-specific stances only as concrete applications of those same base repair rules to the task's domain, for example an exit-code skeptic for a script task or an overcompression skeptic for dense prose. Union the proposals across stances; never count agreement, votes, consensus, or majority.
</reviewer_stances>

<structural_split_boundary>
When `task_check` raises scope-sizing, focus, or complexity defects whose proper repair creates or splits task files, stop the auto-edit path for that issue. Ask `auto_reviewer_task` for a split proposal summary, surface the loop as stuck for a human or for `task_fix`'s `auto_shaper_task` escalation, and leave the current file's body unchanged for that structural change.
</structural_split_boundary>

<mechanical_lint_boundary>
Resolve task-linter findings through the finalization step, separate from the reviewer/verifier body-repair path. Apply only the base `<lint>` mechanically fixable finding set for the single target file, and surface judgement-call findings through the same stuck/human-routed channel as `<structural_split_boundary>`. Compose with the intent-drift boundary by reporting surfaced findings in that shared channel while keeping each boundary's rule text in its own tag.

**Repeated-link disposition filter.** `repeated-link` stays outside the mechanically fixable set this step applies, so the body-repair path dispositions it instead. Only a finding the run regrouped is filtered out of the finalization report's surfaced-but-not-fixed line and out of the stuck/human-routed channel: it carries its own disposition line and leaves nothing for the user. A finding the reviewer surfaced and a reorganization the verifier rejected stay in that channel as the user's call.
</mechanical_lint_boundary>

<concurrent_modification_guard>
Track the target file's on-disk state the loop last established: the freeze-time snapshot, every edit this run has already applied, and the status/`updated` stamp each `<gate>` call writes through `task_check`. Immediately after consuming each gate verdict, establish the target's post-gate content from the freshest evidence in hand: a post-edit snapshot of the target the harness surfaced in the current turn serves as this read, and a fresh re-read of the target supplies it when no such snapshot arrived. Confirm any divergence from the prior baseline is exactly the expected status/`updated` stamp, the value named by the verdict's `updated` field, and adopt the post-gate content as the new baseline; any other divergence at this check fires the guard.

Re-read the target immediately before `<apply_repairs>`, `<finalize_mechanical_lint>`, and every write `<audit_delta>` triggers: each restore of `r<N>-pre-apply.txt`, and the re-application of the approved edits that follows a failed first audit. Each pre-write check is a fresh read of the file itself, because a snapshot surfaced earlier in the turn ages while helper calls run. When the on-disk content diverges from the last-established baseline, whether an edit's anchor no longer matches, the `updated` stamp differs from the baseline's value, or the body already carries the change this round intended, stop without writing, leave the file byte-for-byte unchanged, and surface the run as stuck through the same human-routed channel as the other boundaries: report that the task file changed under the run since freeze, so a concurrent `task_auto_check` run or an external edit modified it. Report only that observed fact; name no specific actor and never infer that a sub-agent wrote outside its contract. The human decides whether to re-run on the updated file.
</concurrent_modification_guard>

<verification_standard>
Invoke `auto_verifier_task` in proposal mode through `<relay>`. Keep only proposals that are real, resolve the cited issue, are the minimum sufficient edit, preserve frozen intent, and remain faithful to standing repo rules. Two cited-issue classes are approvable on equal terms: an issue from the gate verdict, and a lint-originated `repeated-link` finding `<freeze>` recorded, whose proposals the verifier judges against the base `<lint>` **Repeated-link react protocol**, keeping a gathering that leaves the meaning of `## Goal` and the Acceptance contract unchanged and rejecting one that would change either. Reject by default when evidence is missing or the proposal is broader than the issue requires. Preserve explicit human-input boundaries: when the task already says the default is to leave the task checked, request a decision, or stop before implementation, the verifier keeps that route unless the base **Decide or label** rule's evidence base supplies the missing decision, so it keeps a proposed open-decision reconciliation only when that reconciliation is evidence-supported from that base and intent-preserving, and otherwise preserves the surface-to-human route through the existing stuck channel with suggested options. The verifier may narrow a proposal to its intent-safe core, with one carve-out: when a confirmed interaction has made an existing Acceptance item false, superseding that item is part of the minimum sufficient edit rather than surplus. The verifier keeps that supersession and never narrows an interaction repair down to a Context or Approach note that leaves the stale item standing, because a task still carrying a now-false Acceptance item is an incomplete repair under the base **Edit items supersede the stale passage** rule. Route one user-decided class as `human_routed`: an edit group that removes most of the body, deletes a load-bearing section, or collapses either into a summary line or code pointer, and any edit, at any size, that deletes a requirement, rule, constraint, promise, or Acceptance item carried by `frozen-task.txt`, or narrows it so the task promises less. Carry the affected frozen passages verbatim, the gate's fix text for the issue, and the options in play: prove the commitment, narrow it through an `**Out of scope:**` deferral naming its owner or an explicit rejection, or delete it. Stop that repair, apply none of it, and report the run as stuck through `<structural_split_boundary>`. Keep three kinds of edit on the ordinary repair path: a refresh that renames, relocates, or re-anchors a detail the code moved; the interaction-scan supersession required above; and a change to text an earlier round of this run added. Judge what the frozen task carried from `frozen-task.txt`, so the minimum-change preference cannot silently trade a commitment for a smaller proof set.
</verification_standard>

<agent_failure_policy>
The helper agents are delegation vehicles, not authorities, and the loop consumes a helper result only from a real, completed invocation. When a helper invocation fails to spawn, dies mid-run, or returns output that violates its output contract, retry it once with the identical prompt; a self-reported `unassessable` verdict is a completed, deliberate result and skips the retry. One narrow failure shape earns a second identical-prompt retry before the stop: the spawn-echo glitch, where the helper returns near-instantly with zero tool uses and its whole output is harness boilerplate (system-reminder or skills-listing text) rather than any attempt at its contract. That signature marks a known harness injection glitch that re-invocation usually clears, and no legitimate helper result matches it because every helper's first real step uses a tool; every other contract violation keeps the single retry, so a substantive-but-wrong result still stops fast. When the failure persists past its allowed retries, or the `unassessable` verdict arrives, stop the run as a helper-failure stop: apply no further edit, leave the task file exactly as the last completed step left it, and surface one clear error report that names the failed helper, states the observed failure (spawn error, mid-run death, contract-violating output, or the helper's own `unassessable` reason), names the workflow step the loop stopped at, and lists the options the loop sees: typically fixing the agent deployment and re-running, explicitly approving a named degraded alternative (for example running `task_check` directly in the main context as a one-shot gate), or abandoning the run. Ask the user how to proceed and act only on their explicit choice: no degraded alternative, retry loop, or recovery runs automatically. A degraded alternative is presented, never taken unprompted; running `task_check` directly is an option the report offers, not a step this run performs, and when no user reply can arrive in the current run, the error report ending in the question is the run's final output and the run ends there.

Two invariants hold on every failure path: no unverified proposal is ever applied, and no helper result is ever improvised. The loop never role-plays a missing dry-run, gate, drift, reviewer, or verifier result in the main context and never computes a readiness verdict outside `task_check`.

When the current harness offers no agent-spawn mechanism at all, stop before `<freeze>` with the same error report: state that this harness cannot run the loop's delegated architecture and offer the manual routes (a direct `task_check` run for a one-shot readiness verdict, or manual refinement with the base `task` skill) instead of executing helper roles inline.
</agent_failure_policy>

<loop_bounds>
Use a hard cap of 5 rounds unless the user prompt supplies a positive integer override. An ordinary repair round is one dry run, gate call, reviewer pass, verifier pass, edit application, and next loop decision. The citation-refutation round and the repeated-link repair round keep the shapes `<gate>` already gives them and still count as rounds against the cap; when they re-invoke the gate, they name the `r<M>-dryrun.txt` from the ordinary round whose gate return is under citation check, or the one that produced the `ready` entering the repeated-link path, with no new dry run. Stop when `task_check` reports `ready`, when no verified fix remains, when a structural split boundary is the only remaining repair, when a freeze-time intent drift boundary fires, when the gate verdict fires the invalidated-premise boundary, when the concurrent-modification guard fires, when a helper failure stops the run per `<agent_failure_policy>`, or when the cap is reached. The `<gate>` last-call citation-refutation exception is the sole extension beyond this cap. An isolation replacement belongs to the gate call it replaces and adds no round.
</loop_bounds>
</loop_policy>

<workflow>
<orient>
Read the target task end to end. Read the base `task` skill and `task_check` skill. Resolve `tasks/` through the base skill's discovery script. Confirm the target status is `open`, `checked`, or `ready`. A target at `implemented`, `audited`, `finished`, or `deferred` stops the run here with the file unchanged, because its gate call would move it backward, which the base `<backward_move_guard>` refuses, and its body stays as delivered under the base `<status_discipline>` rule.
</orient>

<freeze>
Create and initialize the relay directory through `<relay>`. Copy the complete current task file byte for byte to `frozen-task.txt` before any helper call. Write the original `# Title`, `## Goal`, and any creation-time user intent to `frozen-intent.txt`; write any run-prompt attestation to `attested-intent.txt`. Record the target file's current on-disk content and `updated` stamp as the `<concurrent_modification_guard>` baseline. Run the base task linter file-scoped over the target with `--file <path> --quiet`, save its output as `freeze-lint.txt`, and record its `repeated-link` findings, each with the sections that link the counted target, as the run's repeated-link finding set.

Invoke `auto_drift_task` exactly once through the drift path set in `<relay>`, before the first `<gate>` call and any repair. The agent's four classifications are exactly `clean`, `drift`, `low_confidence_clean`, and `unassessable`. If it returns `clean` or `low_confidence_clean`, continue to `<dry_run>` without surfacing an intention check. If it returns `drift`, surface the single human intention check from `<intent_drift_boundary>`, report the recovered-versus-current evidence, leave the task body unchanged, preserve `<frozen_intent>`, and stop before `task_check`, body repair, or mechanical lint finalization. Treat a failed or `unassessable` drift invocation per `<agent_failure_policy>`.
</freeze>

<dry_run>
Invoke `auto_dryrun_task` through the dry-run path set in `<relay>`, on the task as it stands: write the prompt before the call as `r<N>-dryrun-prompt.txt` and save the return byte for byte as `r<N>-dryrun.txt`, with `<N>` the number of the round whose gate call follows. Treat a failed invocation or an `unassessable` return per `<agent_failure_policy>`. The round's gate call then receives that `r<N>-dryrun.txt` as an admitted input, and the gate grounds and confirms each dry-run finding before it reaches the repair path.
</dry_run>

<gate>
Invoke `auto_gate_task` through the gate path set in `<relay>`. Every gate call in a round, an isolation replacement and a refuted-citation re-invocation included, names that round's `r<N>-dryrun.txt` in its prompt. Consume only the structured verdict, then re-baseline per `<concurrent_modification_guard>`. Inspect its `isolation:` evidence before using its assessment. When that line names any out-of-bounds read, retain the return and re-run the gate once in a fresh helper call with the identical admitted-input prompt, saving both calls through `<relay>`. Use only the replacement verdict and re-baseline after its stamp as well. An isolation replacement belongs to the same round and inherits the replaced call's first-call or last-call position. For the first-call signature, retain the prior status the original call read before its discarded stamp, since the replacement may read that stamp as its prior status. If the replacement still names an out-of-bounds read, stop through `<agent_failure_policy>` as persistent contract-violating output, with no further retry. A missing isolation line, failed invocation, or `unassessable` verdict follows `<agent_failure_policy>`. If the accepted verdict's premise line reads `invalidated`, stop per `<invalidated_premise_boundary>` before repair planning and report the disposition options.

When the verdict reports `ready`, skip gate-issue body-repair planning for this round and test these two citation-refutation triggers before trusting the stamp: the first-call signature (the run's first gate call, `prior_status: open`, `status: ready`, an empty `## Issues`, and every checklist line `clean`), or a `ready` on the last gate call permitted by `<loop_bounds>`, after which no further round fits under the cap. Refute no other `ready`. If both triggers hold, use one citation-mode verifier call and report both. When neither holds, run the repeated-link repair round and then proceed to `<finalize_mechanical_lint>`.

When a trigger holds, invoke `auto_verifier_task` in citation mode through `<relay>`. A refutation round comprises its citation verification and, when needed, its immediate re-gate; it counts as one round against the cap while room remains. This keeps a first-call refutation and its re-gate within the remaining round even when that round exhausts the cap. The last-call trigger permits at most one citation-verifier step and one re-gate assessment beyond the cap, only on a run that reaches `ready` on that last permitted call. Count these as logical steps under the existing round semantics: a helper-failure retry or the one isolation replacement completes the same step, while each physical invocation is counted and reported separately. This keeps the required fresh replacement available without opening another repair round. A failed or `unassessable` invocation follows `<agent_failure_policy>`. When every citation survives, the `ready` stamp stands through the repeated-link repair round, which writes no status and calls no gate, and the run then proceeds to `<finalize_mechanical_lint>`. At the cap that repeated-link round follows its existing skip-and-surface rule.

When the verifier refutes one or more citations, write the refuted rows and re-invoke `auto_gate_task` through the refuted-citation path set in `<relay>`. The gate consumes each entry per its refuted-citation policy, surfaces it as a readiness issue, and writes the status its own re-assessment reaches. This re-gate uses the same isolation and invalidated-premise checks above and never re-enters citation refutation. An invalidated premise takes its existing stop before mechanical finalization, including at the cap. When the refutation used the last-call exception, apply no body repair, proceed to `<finalize_mechanical_lint>`, and stop through the stuck channel at the status that re-gate wrote. Otherwise its issues enter the ordinary repair path while rounds remain; a later eligible last-call `ready` still receives its own refutation.

**Repeated-link repair round.** Every path that would reach `<finalize_mechanical_lint>` from a `ready` verdict without a body-repair round runs one repair round for the `<freeze>`-recorded `repeated-link` findings alone before finalize, so a task the gate approves still gets its scattered account gathered. That round runs `<plan_repairs>`, `<verify_repairs>`, `<apply_repairs>`, and `<audit_delta>` over those findings and nothing else, mapping each to the Grouping advocate. It runs once per run and counts as a round against the `<loop_bounds>` cap, the way a refutation round does. Skip it when an earlier round already dispositioned every recorded finding, when the recorded set is empty, and when the `<loop_bounds>` cap is already reached, reporting any still-undispositioned finding as surfaced in that last case. Every stop path that exits before `<finalize_mechanical_lint>` skips it too, since those paths own no task edits. A regroup keeps the meaning of `## Goal` and the Acceptance contract, so under the base `<status_discipline>` rule it keeps the `ready` stamp the gate wrote: the round writes no status, no gate call follows it, and the run proceeds from the round to `<finalize_mechanical_lint>`.
</gate>

<plan_repairs>
Map each issue from the gate verdict to the standing stance set and any needed emergent stances; a drifted premise finding maps like any other issue, with its repair grounded in the codebase as it stands now so the applied edit refreshes the task's described current state rather than restating the stale one. An **Interaction scan** finding maps the same way: its repair is grounded in the interacting code the lens found so the applied edit refreshes the task against it across every section the interaction touches (superseding any existing Acceptance item the interaction has made false rather than noting the interaction in Context alone, and otherwise adding a new edit-supersedes Acceptance item that proves the interaction is now handled), and an unreconcilable one routes to the existing human-routed stuck channel rather than a newly added one. Map each `repeated-link` finding `<freeze>` recorded to the Grouping advocate beside the gate verdict's issues, so a lint-originated finding reaches the reviewer on the same footing as a gate issue and its proposed regroup goes through `<verify_repairs>` and lands in the same `<apply_repairs>` edit group. For scope-sizing, focus, or complexity defects, request only a split proposal summary and mark that issue as human-routed. For every other issue, invoke `auto_reviewer_task` for each applicable stance through the reviewer path set in `<relay>`.
</plan_repairs>

<verify_repairs>
Invoke `auto_verifier_task` through the proposal-mode path set in `<relay>`. Keep the verifier-approved edits only. When no edit survives verification, leave the task at the status `task_check` wrote, proceed to `<finalize_mechanical_lint>`, and stop as stuck.
</verify_repairs>

<apply_repairs>
Before writing, honor `<concurrent_modification_guard>` and save the current target byte for byte as `r<N>-pre-apply.txt`. Resolve the project root through the base task discovery step; when `CHARTER.md` exists at that root, validate the approved edits against its boundaries and invariants. On a charter conflict, stop without writing, report the conflict, and leave the task file byte-for-byte unchanged.

Apply each approved edit in id order as one anchored replacement: replace its exact anchor in the current text with its exact replacement text, requiring one match. Preserve frontmatter except for the `updated` timestamp; stamp `updated` from `date +%Y-%m-%dT%H:%M:%S` in the same edit group. Run the base task linter with `--quiet`, save the output the apply step acts on as `r<N>-lint.txt`, and fix only findings in the base `<lint>` mechanically fixable finding set.
</apply_repairs>

<audit_delta>
Run after every `<apply_repairs>` that landed edits, including the `<gate>` repeated-link repair round, and complete it before `<finalize_mechanical_lint>` or any later gate. Write `r<N>-apply.diff.txt` as a zero-context unified diff (`diff -U0`) of `r<N>-pre-apply.txt` against the current task, so each hunk is one contiguous changed region, then invoke `auto_verifier_task` in delta mode through `<relay>`. The verifier licenses each hunk by every approved edit id, the `updated` stamp, and base `<lint>` mechanically fixable finding named in `r<N>-lint.txt` that covers its changed lines, so one hunk may carry several licenses. It marks a hunk `unmapped` when any changed line in it has no license, and confirms that every approved edit id maps to a hunk.

When the first audit reports an unmapped hunk or a missing approved edit, honor `<concurrent_modification_guard>` before each corrective write, restore `r<N>-pre-apply.txt`, and repeat the `<apply_repairs>` application over every approved edit in id order, with its `updated` stamp and its post-apply lint. That reverts every unmapped hunk and lands every missing edit while keeping each licensed change. Then regenerate the diff and audit once more. The audit and its one re-audit belong to the round whose edits they check and add no round against `<loop_bounds>`. When the second audit still reports an unmapped hunk or missing edit, restore `r<N>-pre-apply.txt`, run `<finalize_mechanical_lint>`, and stop through the human-routed stuck channel. The next `<gate>` runs only after a clean delta audit.

When a delta invocation fails or returns `unassessable`, restore `r<N>-pre-apply.txt` under `<concurrent_modification_guard>`, then follow `<agent_failure_policy>`. This helper-failure stop skips `<finalize_mechanical_lint>` under that step's existing helper-failure carve-out. No unverified text lands.
</audit_delta>

<finalize_mechanical_lint>
Run before every reporting exit path after `<gate>`, including an immediate `ready` verdict from `<gate>`, a no-verified-fix stop, a structural split stop, and an iteration-cap stop. Invoke the base task linter directory-wide with `--quiet`, filter the reported findings to the target file across blocking, warn, and info severities, and apply the base `<lint>` mechanically fixable finding set directly to that file. A freeze-time intent drift stop exits before this step because the run owns no task edits once the committed intent is contested, an invalidated-premise stop exits before this step because the task's disposition, whether to defer, re-scope, or refute, is the user's open decision, a concurrent-modification stop exits before this step because the file is no longer the one the run froze, and a helper-failure stop exits before this step because the run halts awaiting the user's decision.

Keep this path separate from the body-repair reviewer/verifier path: do not spawn `auto_reviewer_task` or `auto_verifier_task` for mechanical lint findings, and do not re-run `task_check` after applying them because lint cleanliness does not change the readiness verdict. For an over-budget `description`, write one compact replacement that preserves the named scope, important nouns, and user-visible deliverable; the stale over-budget wording disappears. For a determinable broken local link, re-point the link. For an unambiguous non-ISO datetime or malformed frontmatter value, normalise or fill it. For a determinable wikilink or footnote, convert it to standard markdown.

Surface judgement-call findings instead of guessing: an oversized task that needs a split, a broken link with no determinable target, an unclear frontmatter value, an ambiguous wikilink or footnote conversion, and any finding outside the base mechanically fixable set. Apply the `<mechanical_lint_boundary>` **Repeated-link disposition filter** to the `repeated-link` findings among them, so only a finding this run regrouped leaves the surfaced-but-not-fixed line and the stuck channel to its own disposition line. Use `<structural_split_boundary>` as the reporting model, and compose with the intent-drift boundary by leaving human-owned or drift-sensitive changes untouched.

Before writing, honor `<concurrent_modification_guard>` by re-reading the target and stopping if it diverged from the loop's last-established state, then resolve the project root through the base task discovery step; when `CHARTER.md` exists at that root, validate the mechanical edit group against its boundaries and invariants. Stamp `updated` from `date +%Y-%m-%dT%H:%M:%S` exactly once when the mechanical edit group changes the file; leave `updated` unchanged when there is no mechanical edit. Re-run the directory-wide linter after the edit and confirm the target file has no remaining fixable mechanical findings before reporting.
</finalize_mechanical_lint>

<iterate>
Return to `<dry_run>` until the loop stops by ready verdict, no verified fix, structural split boundary, intent drift boundary, invalidated-premise boundary, concurrent-modification guard, helper-failure stop, or cap. At the cap, leave the task at the status from the final `task_check` verdict, proceed to `<finalize_mechanical_lint>`, and surface the remaining issues as stuck.
</iterate>
</workflow>

<output_contract>
Report the loop result with concrete evidence:

- Target task path and final status.
- Number of gate assessments, physical gate and verifier invocations (including retries and isolation replacements), body edit rounds, and mechanical-lint edit groups.
- For each gate verdict: the stamp it wrote and the prior status it read, naming a `checked` → `ready` flip explicitly when one occurs. A flip means an earlier check found blocking issues this verdict no longer reports, and the user reads that movement rather than discovering it in git history.
- Per round: the dry run's `kind:`, its finding count, and each finding the gate confirmed with the issue number it became.
- Which citation-refutation trigger fired (first-call, last-call, both, or neither), whether each citation `survived` or was `refuted`, and whether the `ready` stamp stood or the run returned to the gate. Name the cap stop after a last-call refutation.
- Each isolation re-run, the out-of-bounds reads reported by the discarded verdict, and the replacement verdict used.
- Each deletion or narrowing decision handed to the user, with the affected frozen passages, the gate fix text, and its prove, narrow-with-disposition, or delete options from `<verification_standard>`.
- Whether the stop reason was ready, no verified fix, structural split boundary, intent drift boundary, invalidated-premise boundary, concurrent-modification guard, helper-failure stop, or iteration cap.
- For the freeze-time drift check: the `auto_drift_task` classification, the baseline commit whose version served as the baseline, the recovered-versus-current juxtaposition, any attestation relied on, whether the run halted before `<gate>`, and the exact human intention check message when surfaced.
- For each applied edit group: the cited issue it addressed, whether a `task_check` issue or a lint-originated `repeated-link` finding, the reviewer stance(s) that proposed it, the verifier decision, and the base repair rule cited.
- Relay directory path retained after the run.
- For each delta audit: hunks mapped, hunks reverted, and approved edits applied late.
- For each rejected or human-routed issue: the reason it was rejected or routed.
- For an invalidated-premise stop: the gate's contradiction evidence and the disposition options presented for the user's decision.
- For a concurrent-modification stop: the observed divergence (an unmatched edit, a newer `updated` stamp, or an already-applied change) and confirmation that the file was left unchanged, without attributing the change to any actor.
- For a helper-failure stop: the helper that failed or returned `unassessable`, the observed failure and retry outcome, the workflow step the loop stopped at, and the options presented for the user's decision.
- For mechanical lint finalization: the base `<lint>` findings applied, the target-file findings surfaced-but-not-fixed with the `<mechanical_lint_boundary>` **Repeated-link disposition filter** already applied to them, whether `updated` changed, and the post-fix linter result.
- For each `repeated-link` finding the run dispositioned: one line in the base `<lint>` **Repeated-link disposition line** shape. That shared per-finding disposition line shape is mandatory on every dispositioning path, whether the regroup landed through `<plan_repairs>` / `<verify_repairs>` / `<apply_repairs>` in an ordinary round or through the `<gate>` repeated-link repair round on a `ready` verdict, and whether the disposition reads regrouped or surfaced, the only two the protocol allows.
- The exact verification commands run, including the base task linter.

Close with the natural next step: `task_implement` when the task is `ready`; human intention confirmation when the intent drift boundary fires; the user's disposition decision, whether to defer through `task_finish`, re-scope the intent, or refute the finding, when the invalidated-premise boundary fires; a re-run on the updated file when the concurrent-modification guard fires; the user's decision on the surfaced options when a helper-failure stop fires; or human refinement / `task_fix` with `auto_shaper_task` escalation when the loop stops stuck on structural tree work. Point at `task_finish` only as that surfaced defer option; on every other path readiness is before implementation, and the loop never performs a close-out itself.
</output_contract>

<family>
In the `task_*` family, each sibling does one job, then points to the next, while the base `task` skill is the hub that can do all of it:

- `task_create`: write one task file
- `task_check`: readiness gate before building (read-only)
- `task_auto_check`: autonomously repair one task until `task_check` reports ready **(this skill)**
- `task_explain`: explain one task at a high level (read-only)
- `task_select`: choose and rank the next eligible task/action (read-only)
- `task_implement`: do the work
- `task_audit`: verify a believed-done task against the codebase (read-only)
- `task_finish`: close out (set status, bump `updated`, archive)
- `task_fix`: audit and repair the whole tasks tree

These ship together as a family; any sibling may be absent if a deployment excluded it. The default manual chain is create → check → implement → audit → finish, with `task_auto_check` as an opt-in readiness repair loop, `task_select` a read-only chooser for what to work on next, and `task_fix` maintaining the tree.
</family>

</task_auto_check_skill>
