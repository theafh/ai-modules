---
name: task_auto_check
description: Autonomously drive one task from open or checked to ready through task_check, verifier-approved body repairs, and final mechanical task-lint cleanup. Use when a user asks to auto-fix readiness issues, make a task ready, refresh a stale task against the current codebase, or run an autonomous readiness loop without implementing the task. A task whose premise the code invalidates stops the loop and surfaces deferral as the user's option.
version: 1.0.15
author: Andreas F. Hoffmann
license: MIT
---

# task_auto_check

<task_auto_check_skill>

<role>
task_auto_check is the opt-in autonomous readiness loop for one task file. It freezes the task's current title and Goal, runs one committed-intent drift check, uses `task_check` as the only readiness gate, then asks modular `auto_*_task` agents to propose and verify minimal task-body repairs until the task becomes `ready` or no verified intent-preserving repair remains. Before reporting ordinary stop results, it finalizes the target file with the base task linter and applies mechanically fixable lint repairs. It prepares a task for `task_implement`; it never implements the task's work and never closes or archives it.
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
Resolve the base `task` and `task_check` skills from the same plugin bundle as this skill when possible: this skill lives at `skills/task_auto_check/SKILL.md`, so sibling skills live under `../task/` and `../task_check/`. Resolve the helper agents by their published names — `auto_drift_task`, `auto_gate_task`, `auto_reviewer_task`, and `auto_verifier_task` — using the current harness's normal agent mechanism. When a harness exposes only file paths, those agents live in the same plugin at `../../agents/` relative to this skill directory.
</path_resolution>

<inputs>
The user supplies one task file path or one unambiguous task name. The optional user prompt may also supply:

- A max-round override, expressed as a positive integer such as "max rounds 2".
- Creation-time intent context, used only when the loop runs immediately after a task is drafted.
- An explicit request to use an available foreign-model reviewer stance. The default is single-model operation with no foreign-model stance.
</inputs>

<loop_policy>
<single_gate>
Use `task_check` verbatim as the gate. The loop consumes the structured verdict returned by `auto_gate_task`: task path, status stamp, prior status, ready boolean, per-item checklist record, issue list, and evidence labels. It does not compute a second readiness score and does not override `task_check`'s `ready` or `checked` stamp.
</single_gate>

<frozen_intent>
Freeze the original task's `# Title` and `## Goal` before the first gate call. When the user supplied creation-time intent, freeze that prompt alongside the title and Goal. Every proposal and every applied edit must preserve this frozen intent; the loop may clarify expression, add missing implementation context, or make acceptance checks verifiable, but it must not change what the task is for.
</frozen_intent>

<intent_drift_boundary>
Invoke `auto_drift_task` once at freeze time, before the first `<gate>` call and any repair. A `drift` classification is human-routed through the same surfaced stuck channel as `<structural_split_boundary>` and `<mechanical_lint_boundary>`: report the intention check that names the field `auto_drift_task` flagged in its `drifted_fields` — `Attention: this task's Title appears to have already drifted from its original intent.` for title-only drift, `…this task's Goal appears…` for goal-only drift, or `…this task's Title and Goal appear…` when both drifted — with the recovered-versus-current evidence, halt the auto-repair path for this run, leave the task body unchanged, and keep `<frozen_intent>` intact. Use the recovered origin as evidence for the human, not as an edit target; the loop never auto-repairs toward the recovered original intent. Clean, meaning-preserving, and `low_confidence_clean` results proceed without surfacing the intention check.
</intent_drift_boundary>

<invalidated_premise_boundary>
When the gate verdict's premise line reports the base premise check's invalidated outcome — the codebase contradicts the task's reason to exist — stop the body-repair path for the run: a repair that rewrites a task to survive a dead premise changes what the task is for and breaks `<frozen_intent>`. Leave the body unchanged at the status the gate wrote, and surface the stop through the same human-routed stuck channel as `<structural_split_boundary>`, reporting the gate's contradiction evidence alongside the base rule's disposition options: close the task `deferred` through `task_finish`, re-scope the intent as a user-owned edit, or refute the finding with evidence and re-run. The loop presents these options and performs none of them — deferral is never automatic. Premise findings the gate labels drifted stay on the ordinary repair path and are refreshed against the current codebase.
</invalidated_premise_boundary>

<reviewer_stances>
Spawn `auto_reviewer_task` once per applicable stance. The standing stance set is selected lazily from the issues `task_check` raised and cites the base `task` skill's `<body>` repair rules by name:

- Self-sufficiency advocate — cite the base `<body>` self-sufficient / single-shot-ready rule.
- Minimum-change advocate — cite **Compact only to the implementable floor**.
- State-once advocate — cite **State once**.
- Decide-or-label advocate — cite **Decide or label**. Propose an evidence-grounded reconciliation of an open decision drawn from that rule's ordered evidence base rather than a bare relabel; when no evidence in that base settles the decision, propose surfacing it as a labeled decision with suggested options through the existing human-routed stuck channel rather than inventing a choice.
- Acceptance-contract advocate — cite the base `<body>` **Acceptance** contract.
- Rewrite-in-place advocate — cite **Rewrite in place, don't append**.
- Positive-reframe advocate — cite the base `<body>` positive, action-oriented authoring rule.
- Redact-by-generalizing advocate — cite **Redact by generalizing**.
- Boundary advocate — cite the base `<body>` **Declare exclusions as an Out of scope boundary** rule. Propose normalizing a variant exclusion phrasing to the canonical `**Out of scope:**` block, or reconciling a body-versus-boundary contradiction against the evidence per **Decide or label**; when no evidence settles which side wins, propose surfacing it as a labeled decision with options through the existing human-routed stuck channel rather than crossing or dropping the boundary silently.
- Interaction-scan advocate — cite the base `<readiness_checklist>` **Interaction scan** lens for the finding and the base `<body>` **Rewrite in place, don't append**, **Acceptance** contract, and **Edit items supersede the stale passage** rules for its repair. Propose the minimum body edit that refreshes the task against the interacting code the lens found — reconciling a contradiction or accounting for an unattended interaction — and carry that refresh through every section the interaction touches, not Context alone. When the interaction makes an existing Acceptance item stale — it contradicts what that item promises, the way a shipped page-size cap contradicts a test asserting an over-cap page — superseding that Acceptance item is a required part of the repair per **Edit items supersede the stale passage**, not an optional add-on: noting the interaction in Context while leaving the now-false Acceptance item standing is an incomplete repair. When the interaction invalidates no existing item, add a new edit-supersedes Acceptance item that proves it is now handled. When no evidence in **Decide or label**'s ordered base settles the fix, propose surfacing it as a labeled decision with suggested options through the existing human-routed stuck channel rather than inventing a reconciliation.

Add emergent task-specific stances only as concrete applications of those same base repair rules to the task's domain, for example an exit-code skeptic for a script task or an overcompression skeptic for dense prose. Union the proposals across stances; never count agreement, votes, consensus, or majority.
</reviewer_stances>

<structural_split_boundary>
When `task_check` raises scope-sizing, focus, or complexity defects whose proper repair creates or splits task files, stop the auto-edit path for that issue. Ask `auto_reviewer_task` for a split proposal summary, surface the loop as stuck for a human or for `task_fix`'s `auto_shaper_task` escalation, and leave the current file's body unchanged for that structural change.
</structural_split_boundary>

<mechanical_lint_boundary>
Resolve task-linter findings through the finalization step, separate from the reviewer/verifier body-repair path. Apply only the base `<lint>` mechanically fixable finding set for the single target file, and surface judgement-call findings through the same stuck/human-routed channel as `<structural_split_boundary>`. Compose with the intent-drift boundary by reporting surfaced findings in that shared channel while keeping each boundary's rule text in its own tag.
</mechanical_lint_boundary>

<concurrent_modification_guard>
Track the target file's on-disk state the loop last established: the freeze-time snapshot, every edit this run has already applied, and the status/`updated` stamp each `<gate>` call writes through `task_check`. Immediately after consuming each gate verdict, establish the target's post-gate content from the freshest evidence in hand: a post-edit snapshot of the target the harness surfaced in the current turn serves as this read, and a fresh re-read of the target supplies it when no such snapshot arrived. Confirm any divergence from the prior baseline is exactly the expected status/`updated` stamp — the verdict's `updated` field names the value to expect — and adopt the post-gate content as the new baseline; any other divergence at this check fires the guard. Re-read the target again immediately before writing any edit group, in both `<apply_repairs>` and `<finalize_mechanical_lint>`; this pre-write check is always a fresh read of the file itself, because a snapshot surfaced earlier in the turn ages while reviewer and verifier calls run. When the on-disk content diverges from the last-established baseline — an edit's `old_string` no longer matches, the `updated` stamp differs from the baseline's value, or the body already carries the change this round intended — stop without writing, leave the file byte-for-byte unchanged, and surface the run as stuck through the same human-routed channel as the other boundaries: report that the task file changed under the run since freeze, so a concurrent `task_auto_check` run or an external edit modified it. Report only that observed fact; name no specific actor and never infer that a sub-agent wrote outside its contract. The human decides whether to re-run on the updated file.
</concurrent_modification_guard>

<verification_standard>
Pass all proposals to `auto_verifier_task`. Keep only proposals that are real, resolve the cited `task_check` issue, are the minimum sufficient edit, preserve frozen intent, and remain faithful to standing repo rules. Reject by default when evidence is missing or the proposal is broader than the issue requires. Preserve explicit human-input boundaries: when the task already says the default is to leave the task checked, request a decision, or stop before implementation, the verifier keeps that route unless the base **Decide or label** rule's evidence base supplies the missing decision — so it keeps a proposed open-decision reconciliation only when that reconciliation is evidence-supported from that base and intent-preserving, and otherwise preserves the surface-to-human route through the existing stuck channel with suggested options. The verifier may narrow a proposal to its intent-safe core, with one carve-out: when a confirmed interaction has made an existing Acceptance item false, superseding that item is part of the minimum sufficient edit rather than surplus — the verifier keeps that supersession and never narrows an interaction repair down to a Context or Approach note that leaves the stale item standing, because a task still carrying a now-false Acceptance item is an incomplete repair under the base **Edit items supersede the stale passage** rule. Treat an edit group that would remove the majority of the task body, delete an entire load-bearing section, or collapse either into a summary line or code pointer as a structural change rather than a repair: human-route it through the `<structural_split_boundary>` reporting channel instead of applying it, even when each removed passage looks individually justified as false, redundant, or derivable — a finding at that scale needs the user's read on whether the task is misconceived, not silent gutting.
</verification_standard>

<agent_failure_policy>
The helper agents are delegation vehicles, not authorities, and the loop consumes a helper result only from a real, completed invocation. When a helper invocation fails to spawn, dies mid-run, or returns output that violates its output contract, retry it once with the identical prompt; a self-reported `unassessable` verdict is a completed, deliberate result and skips the retry. One narrow failure shape earns a second identical-prompt retry before the stop: the spawn-echo glitch, where the helper returns near-instantly with zero tool uses and its whole output is harness boilerplate — system-reminder or skills-listing text — rather than any attempt at its contract. That signature marks a known harness injection glitch that re-invocation usually clears, and no legitimate helper result matches it because every helper's first real step uses a tool; every other contract violation keeps the single retry, so a substantive-but-wrong result still stops fast. When the failure persists past its allowed retries — or the `unassessable` verdict arrives — stop the run as a helper-failure stop: apply no further edit, leave the task file exactly as the last completed step left it, and surface one clear error report that names the failed helper, states the observed failure (spawn error, mid-run death, contract-violating output, or the helper's own `unassessable` reason), names the workflow step the loop stopped at, and lists the options the loop sees — typically fixing the agent deployment and re-running, explicitly approving a named degraded alternative (for example running `task_check` directly in the main context as a one-shot gate), or abandoning the run. Ask the user how to proceed and act only on their explicit choice: no degraded alternative, retry loop, or recovery runs automatically. A degraded alternative is presented, never taken unprompted — running `task_check` directly is an option the report offers, not a step this run performs, and when no user reply can arrive in the current run, the error report ending in the question is the run's final output and the run ends there.

Two invariants hold on every failure path: no unverified proposal is ever applied, and no helper result is ever improvised — the loop never role-plays a missing gate, drift, reviewer, or verifier result in the main context and never computes a readiness verdict outside `task_check`.

When the current harness offers no agent-spawn mechanism at all, stop before `<freeze>` with the same error report: state that this harness cannot run the loop's delegated architecture and offer the manual routes — a direct `task_check` run for a one-shot readiness verdict, or manual refinement with the base `task` skill — instead of executing helper roles inline.
</agent_failure_policy>

<loop_bounds>
Use a hard cap of 5 rounds unless the user prompt supplies a positive integer override. A round is one gate call, reviewer pass, verifier pass, edit application, and next loop decision. Stop when `task_check` reports `ready`, when no verified fix remains, when a structural split boundary is the only remaining repair, when a freeze-time intent drift boundary fires, when the gate verdict fires the invalidated-premise boundary, when the concurrent-modification guard fires, when a helper failure stops the run per `<agent_failure_policy>`, or when the cap is reached.
</loop_bounds>
</loop_policy>

<workflow>
<orient>
Read the target task end to end. Read the base `task` skill and `task_check` skill. Resolve `tasks/` through the base skill's discovery script. Confirm the target status is `open`, `checked`, or `ready`, or follow the base `<backward_move_guard>` before any status-changing gate call would move a later lifecycle state backward.
</orient>

<freeze>
Snapshot the original `# Title`, `## Goal`, and any creation-time user intent, and record the target file's current on-disk content and `updated` stamp as the `<concurrent_modification_guard>` baseline. Keep this snapshot in loop-local state and pass it to every reviewer and verifier call. Invoke `auto_drift_task` with the task path, resolved project root, resolved base `task` skill, and frozen title/Goal exactly once, before the first `<gate>` call and any repair. If it returns `clean` or `low_confidence_clean`, continue to `<gate>` without surfacing an intention check. If it returns `drift`, surface the single human intention check from `<intent_drift_boundary>`, report the recovered-versus-current evidence, leave the task body unchanged, preserve `<frozen_intent>`, and stop before `task_check`, body repair, or mechanical lint finalization. Treat a failed or `unassessable` drift invocation per `<agent_failure_policy>`.
</freeze>

<gate>
Invoke `auto_gate_task` with the task path, the resolved `task_check` skill path, the resolved base `task` skill path, the project root, and any frozen creation-time intent. Pass pointers, never a digest: the gate prompt names the readiness authorities by path and leaves reading and applying the `<readiness_checklist>` to the gate agent — a prompt that paraphrases, summarizes, or enumerates checklist items anchors the gate to the named checks and starves the rest of the lens, so the loop writes no checklist content into the prompt beyond the authorities' locations. Consume only the structured verdict, then re-baseline per `<concurrent_modification_guard>`. A failed or `unassessable` gate invocation follows `<agent_failure_policy>`. When the verdict reports `ready`, skip body-repair planning for this round and test the immediate-approval signature before trusting the stamp — the conjunction of four fields the verdict already reports: this is the run's first gate call, `prior_status` is `open`, `status` is `ready`, and the verdict's `## Issues` is empty with every checklist line `clean`. The trigger is deliberately that narrow so its cost stays bounded on the face of this contract: it fires only on a first-call approval that surfaced nothing, the pattern observed overturns landed on, and never on a verdict that raised issues or on a `ready` reached after repair rounds, where `prior_status` is already `checked`. When the signature does not hold, proceed to `<finalize_mechanical_lint>` before reporting. When it holds, invoke `auto_verifier_task` with the verdict's citations and the frozen intent, framing the question as whether each citation supports the `clean` claim it was written for; a refutation round counts as a round against the `<loop_bounds>` cap, and a failed or `unassessable` refutation invocation follows `<agent_failure_policy>`. When every citation survives, the `ready` stamp stands and the run proceeds to `<finalize_mechanical_lint>` as on any other `ready` verdict. When the verifier refutes one or more citations, re-invoke `auto_gate_task` with the refuted-citation set supplied as input — run evidence the gate's own `<inputs>` admits, not the checklist digest the pointer rule forbids: the gate consumes each entry per its refuted-citation `<policy>` rule and surfaces it as a readiness issue in the fresh verdict, `task_check` writes whatever status its own re-assessment reaches, the surfaced issues enter the ordinary repair path, and a subsequent gate call never re-enters citation refutation. If the verdict's premise line reads `invalidated`, stop per `<invalidated_premise_boundary>` before any repair planning and report the disposition options.
</gate>

<plan_repairs>
Map each issue from the gate verdict to the standing stance set and any needed emergent stances; a drifted premise finding maps like any other issue, with its repair grounded in the codebase as it stands now so the applied edit refreshes the task's described current state rather than restating the stale one. An **Interaction scan** finding maps the same way: its repair is grounded in the interacting code the lens found so the applied edit refreshes the task against it across every section the interaction touches — superseding any existing Acceptance item the interaction has made false rather than noting the interaction in Context alone, and otherwise adding a new edit-supersedes Acceptance item that proves the interaction is now handled — and an unreconcilable one routes to the existing human-routed stuck channel rather than a newly added one. For scope-sizing, focus, or complexity defects, request only a split proposal summary and mark that issue as human-routed. For every other issue, invoke `auto_reviewer_task` for each applicable stance, passing the issue, frozen intent, task path, relevant repo context labels, and the base repair rule names the stance cites.
</plan_repairs>

<verify_repairs>
Invoke `auto_verifier_task` with the union of proposals. Keep the verifier-approved edits only. When no edit survives verification, leave the task at the status `task_check` wrote, proceed to `<finalize_mechanical_lint>`, and stop as stuck.
</verify_repairs>

<apply_repairs>
Apply the surviving fixes as one cohesive minimum-change edit group. Before writing, honor `<concurrent_modification_guard>`: re-read the target and stop without writing if its on-disk content diverged from the loop's last-established state. Then resolve the project root through the base task discovery step; when `CHARTER.md` exists at that root, validate the edit group against its boundaries and invariants. On a charter conflict, stop without writing, report the conflict, and leave the task file byte-for-byte unchanged. Preserve frontmatter except for the `updated` timestamp; stamp `updated` from `date +%Y-%m-%dT%H:%M:%S` in the same edit. Run the base task linter with `--quiet` and fix any blocking finding introduced by the edit.
</apply_repairs>

<finalize_mechanical_lint>
Run before every reporting exit path after `<gate>`, including an immediate `ready` verdict from `<gate>`, a no-verified-fix stop, a structural split stop, and an iteration-cap stop. Invoke the base task linter directory-wide with `--quiet`, filter the reported findings to the target file across blocking, warn, and info severities, and apply the base `<lint>` mechanically fixable finding set directly to that file. A freeze-time intent drift stop exits before this step because the run owns no task edits once the committed intent is contested, an invalidated-premise stop exits before this step because the task's disposition — defer, re-scope, or refute — is the user's open decision, a concurrent-modification stop exits before this step because the file is no longer the one the run froze, and a helper-failure stop exits before this step because the run halts awaiting the user's decision.

Keep this path separate from the body-repair reviewer/verifier path: do not spawn `auto_reviewer_task` or `auto_verifier_task` for mechanical lint findings, and do not re-run `task_check` after applying them because lint cleanliness does not change the readiness verdict. For an over-budget `description`, write one compact replacement that preserves the named scope, important nouns, and user-visible deliverable; the stale over-budget wording disappears. For a determinable broken local link, re-point the link. For an unambiguous non-ISO datetime or malformed frontmatter value, normalise or fill it. For a determinable wikilink or footnote, convert it to standard markdown.

Surface judgement-call findings instead of guessing: an oversized task that needs a split, a broken link with no determinable target, an unclear frontmatter value, an ambiguous wikilink or footnote conversion, and any finding outside the base mechanically fixable set. Use `<structural_split_boundary>` as the reporting model, and compose with the intent-drift boundary by leaving human-owned or drift-sensitive changes untouched.

Before writing, honor `<concurrent_modification_guard>` by re-reading the target and stopping if it diverged from the loop's last-established state, then resolve the project root through the base task discovery step; when `CHARTER.md` exists at that root, validate the mechanical edit group against its boundaries and invariants. Stamp `updated` from `date +%Y-%m-%dT%H:%M:%S` exactly once when the mechanical edit group changes the file; leave `updated` unchanged when there is no mechanical edit. Re-run the directory-wide linter after the edit and confirm the target file has no remaining fixable mechanical findings before reporting.
</finalize_mechanical_lint>

<iterate>
Return to `<gate>` until the loop stops by ready verdict, no verified fix, structural split boundary, intent drift boundary, invalidated-premise boundary, concurrent-modification guard, helper-failure stop, or cap. At the cap, leave the task at the status from the final `task_check` verdict, proceed to `<finalize_mechanical_lint>`, and surface the remaining issues as stuck.
</iterate>
</workflow>

<output_contract>
Report the loop result with concrete evidence:

- Target task path and final status.
- Number of gate calls, body edit rounds, and mechanical-lint edit groups.
- For each gate verdict: the stamp it wrote and the prior status it read, naming a `checked` → `ready` flip explicitly when one occurs — a flip means an earlier check found blocking issues this verdict no longer reports, and the user reads that movement rather than discovering it in git history.
- Whether the immediate-ready refutation trigger fired, and when it fired: whether each citation `survived` or was `refuted`, and whether the `ready` stamp stood or the run returned to the gate.
- Whether the stop reason was ready, no verified fix, structural split boundary, intent drift boundary, invalidated-premise boundary, concurrent-modification guard, helper-failure stop, or iteration cap.
- For the freeze-time drift check: the `auto_drift_task` classification, baseline commit when available, recovered-versus-current evidence, whether the run halted before `<gate>`, and the exact human intention check message when surfaced.
- For each applied edit group: the `task_check` issue it addressed, the reviewer stance(s) that proposed it, the verifier decision, and the base `<body>` repair rule cited.
- For each rejected or human-routed issue: the reason it was rejected or routed.
- For an invalidated-premise stop: the gate's contradiction evidence and the disposition options presented for the user's decision.
- For a concurrent-modification stop: the observed divergence (an unmatched edit, a newer `updated` stamp, or an already-applied change) and confirmation that the file was left unchanged, without attributing the change to any actor.
- For a helper-failure stop: the helper that failed or returned `unassessable`, the observed failure and retry outcome, the workflow step the loop stopped at, and the options presented for the user's decision.
- For mechanical lint finalization: the base `<lint>` findings applied, the target-file findings surfaced-but-not-fixed, whether `updated` changed, and the post-fix linter result.
- The exact verification commands run, including the base task linter.

Close with the natural next step: `task_implement` when the task is `ready`; human intention confirmation when the intent drift boundary fires; the user's disposition decision — defer through `task_finish`, re-scope the intent, or refute the finding — when the invalidated-premise boundary fires; a re-run on the updated file when the concurrent-modification guard fires; the user's decision on the surfaced options when a helper-failure stop fires; or human refinement / `task_fix` with `auto_shaper_task` escalation when the loop stops stuck on structural tree work. Point at `task_finish` only as that surfaced defer option — on every other path readiness is before implementation, and the loop never performs a close-out itself.
</output_contract>

<family>
The `task_*` family — each sibling does one job, then points to the next; the base `task` skill is the hub that can do all of it:

- `task_create` — write one task file
- `task_check` — readiness gate before building (read-only)
- `task_auto_check` — autonomously repair one task until `task_check` reports ready **(this skill)**
- `task_explain` — explain one task at a high level (read-only)
- `task_select` — choose and rank the next eligible task/action (read-only)
- `task_implement` — do the work
- `task_audit` — verify a believed-done task against the codebase (read-only)
- `task_finish` — close out: set status, bump `updated`, archive
- `task_fix` — audit and repair the whole tasks tree

These ship together as a family; any sibling may be absent if a deployment excluded it. The default manual chain is create → check → implement → audit → finish, with `task_auto_check` as an opt-in readiness repair loop, `task_select` a read-only chooser for what to work on next, and `task_fix` maintaining the tree.
</family>

</task_auto_check_skill>
