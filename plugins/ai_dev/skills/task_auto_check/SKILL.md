---
name: task_auto_check
description: Autonomously drive one task from open or checked to ready by looping through task_check as the only readiness gate, reviewer repair proposals, verifier-approved intent-safe edits, and re-checks. Use when a user asks to auto-fix readiness issues, make a task ready, or run an autonomous readiness loop without implementing the task.
version: 1.0.1
author: Andreas F. Hoffmann
license: MIT
---

# task_auto_check

<task_auto_check_skill>

<role>
task_auto_check is the opt-in autonomous readiness loop for one task file. It uses `task_check` as the only readiness gate, then asks modular `auto_*_task` agents to propose and verify minimal task-body repairs until the task becomes `ready` or no verified intent-preserving repair remains. It prepares a task for `task_implement`; it never implements the task's work and never closes or archives it.
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
The base `task` skill owns the task-file format, lifecycle stamps, `<readiness_checklist>`, `<body>` repair rules, `<backward_move_guard>`, discovery, timestamp, and lint rules. `task_check` owns the ready/checked verdict and status write. Read both skills before running the loop, cite their rules by name, and keep this skill to orchestration and safe edits.
</authority>

<path_resolution>
Resolve the base `task` and `task_check` skills from the same plugin bundle as this skill when possible: this skill lives at `skills/task_auto_check/SKILL.md`, so sibling skills live under `../task/` and `../task_check/`. Resolve the helper agents by their published names — `auto_gate_task`, `auto_reviewer_task`, and `auto_verifier_task` — using the current harness's normal agent mechanism. When a harness exposes only file paths, those agents live in the same plugin at `../../agents/` relative to this skill directory.
</path_resolution>

<inputs>
The user supplies one task file path or one unambiguous task name. The optional user prompt may also supply:

- A max-round override, expressed as a positive integer such as "max rounds 2".
- Creation-time intent context, used only when the loop runs immediately after a task is drafted.
- An explicit request to use an available foreign-model reviewer stance. The default is single-model operation with no foreign-model stance.
</inputs>

<loop_policy>
<single_gate>
Use `task_check` verbatim as the gate. The loop consumes the structured verdict returned by `auto_gate_task`: task path, status stamp, ready boolean, issue list, and evidence labels. It does not compute a second readiness score and does not override `task_check`'s `ready` or `checked` stamp.
</single_gate>

<frozen_intent>
Freeze the original task's `## Goal` before the first gate call. When the user supplied creation-time intent, freeze that prompt alongside the goal. Every proposal and every applied edit must preserve this frozen intent; the loop may clarify expression, add missing implementation context, or make acceptance checks verifiable, but it must not change what the task is for.
</frozen_intent>

<reviewer_stances>
Spawn `auto_reviewer_task` once per applicable stance. The standing stance set is selected lazily from the issues `task_check` raised and cites the base `task` skill's `<body>` repair rules by name:

- Self-sufficiency advocate — cite the base `<body>` self-sufficient / single-shot-ready rule.
- Minimum-change advocate — cite **Compact only to the implementable floor**.
- State-once advocate — cite **State once**.
- Decide-or-label advocate — cite **Decide or label**.
- Acceptance-contract advocate — cite the base `<body>` **Acceptance** contract.
- Rewrite-in-place advocate — cite **Rewrite in place, don't append**.
- Positive-reframe advocate — cite the base `<body>` positive, action-oriented authoring rule.
- Redact-by-generalizing advocate — cite **Redact by generalizing**.

Add emergent task-specific stances only as concrete applications of those same base repair rules to the task's domain, for example an exit-code skeptic for a script task or an overcompression skeptic for dense prose. Union the proposals across stances; never count agreement, votes, consensus, or majority.
</reviewer_stances>

<structural_split_boundary>
When `task_check` raises scope-sizing, focus, or complexity defects whose proper repair creates or splits task files, stop the auto-edit path for that issue. Ask `auto_reviewer_task` for a split proposal summary, surface the loop as stuck for a human or `task_auto_shaper`, and leave the current file's body unchanged for that structural change.
</structural_split_boundary>

<verification_standard>
Pass all proposals to `auto_verifier_task`. Keep only proposals that are real, resolve the cited `task_check` issue, are the minimum sufficient edit, preserve frozen intent, and remain faithful to standing repo rules. Reject by default when evidence is missing or the proposal is broader than the issue requires. Preserve explicit human-input boundaries: when the task already says the default is to leave the task checked, request a decision, or stop before implementation, the verifier keeps that route unless repository evidence supplies the missing decision. The verifier may narrow a proposal to its intent-safe core.
</verification_standard>

<loop_bounds>
Use a hard cap of 5 rounds unless the user prompt supplies a positive integer override. A round is one gate call, reviewer pass, verifier pass, edit application, and next loop decision. Stop when `task_check` reports `ready`, when no verified fix remains, when a structural split boundary is the only remaining repair, or when the cap is reached.
</loop_bounds>
</loop_policy>

<workflow>
<orient>
Read the target task end to end. Read the base `task` skill and `task_check` skill. Resolve `tasks/` through the base skill's discovery script. Confirm the target status is `open`, `checked`, or `ready`, or follow the base `<backward_move_guard>` before any status-changing gate call would move a later lifecycle state backward.
</orient>

<freeze>
Snapshot the original `## Goal` and any creation-time user intent. Keep this snapshot in loop-local state and pass it to every reviewer and verifier call.
</freeze>

<gate>
Invoke `auto_gate_task` with the task path and the resolved `task_check` skill. Consume only its structured verdict. If it reports `ready`, stop successfully and report that zero further edits were needed in this round.
</gate>

<plan_repairs>
Map each issue from the gate verdict to the standing stance set and any needed emergent stances. For scope-sizing, focus, or complexity defects, request only a split proposal summary and mark that issue as human-routed. For every other issue, invoke `auto_reviewer_task` for each applicable stance, passing the issue, frozen intent, task path, relevant repo context labels, and the base repair rule names the stance cites.
</plan_repairs>

<verify_repairs>
Invoke `auto_verifier_task` with the union of proposals. Keep the verifier-approved edits only. When no edit survives verification, leave the task at the status `task_check` wrote and stop as stuck.
</verify_repairs>

<apply_repairs>
Apply the surviving fixes as one cohesive minimum-change edit group. Before writing, resolve the project root through the base task discovery step; when `CHARTER.md` exists at that root, validate the edit group against its boundaries and invariants. On a charter conflict, stop without writing, report the conflict, and leave the task file byte-for-byte unchanged. Preserve frontmatter except for the `updated` timestamp; stamp `updated` from `date +%Y-%m-%dT%H:%M:%S` in the same edit. Run the base task linter with `--quiet` and fix any blocking finding introduced by the edit.
</apply_repairs>

<iterate>
Return to `<gate>` until the loop stops by ready verdict, no verified fix, structural split boundary, or cap. At the cap, leave the task at the status from the final `task_check` verdict and surface the remaining issues as stuck.
</iterate>
</workflow>

<output_contract>
Report the loop result with concrete evidence:

- Target task path and final status.
- Number of gate calls and edit rounds.
- Whether the stop reason was ready, no verified fix, structural split boundary, or iteration cap.
- For each applied edit group: the `task_check` issue it addressed, the reviewer stance(s) that proposed it, the verifier decision, and the base `<body>` repair rule cited.
- For each rejected or human-routed issue: the reason it was rejected or routed.
- The exact verification commands run, including the base task linter.

Close with the natural next step: `task_implement` when the task is `ready`, or human refinement / `task_auto_shaper` when the loop stops stuck. Do not point at `task_finish`, because readiness is before implementation.
</output_contract>

<family>
The `task_*` family — each sibling does one job, then points to the next; the base `task` skill is the hub that can do all of it:

- `task_create` — write one task file
- `task_check` — readiness gate before building (read-only)
- `task_auto_check` — autonomously repair one task until `task_check` reports ready **(this skill)**
- `task_select` — choose and rank the next eligible task/action (read-only)
- `task_implement` — do the work
- `task_audit` — verify a believed-done task against the codebase (read-only)
- `task_finish` — close out: set status, bump `updated`, archive
- `task_fix` — audit and repair the whole tasks tree

These ship together as a family; any sibling may be absent if a deployment excluded it. The default manual chain is create → check → select → implement → audit → finish, with `task_auto_check` as an opt-in replacement for manual readiness refinement and fix maintaining the tree.
</family>

</task_auto_check_skill>
