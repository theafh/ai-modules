---
description: Give task_fix an opt-in cohort-coherence pass that jointly assesses a scoped set of live tasks against each other and their shared target artifacts, then reconciles accepted findings minimally.
scope: plugins/ai_dev
created: 2026-08-05T18:22:13
updated: 2026-08-05T18:22:13
status: open
reported-by: Andreas Hoffmann
---

# Cohort-coherence pass for task_fix: assess and reconcile a task cohort jointly

## Goal

`task_fix` gains an opt-in cohort-coherence pass: given a cohort of live tasks (a scope filter, an explicit list, or the whole live tree), it reads the cohort and the target artifacts those tasks point at once, jointly, judges the tasks against each other and against the code as it stands, and reports per-task verdicts — ship as-is, alter with concrete minimum edits, or defer candidate — plus a coherent ship order. On the user's acceptance it applies the minimum, intent-preserving repairs and surfaces only what context cannot settle. The pass catches the defect class every per-task surface structurally misses: two tasks that are each individually ready can still contradict each other, double-own one edit, reintroduce a hazard a sibling fixes, or sit stale against work that shipped after they were written. The pass is written entirely against the base `task` skill's own conventions — `scope` frontmatter, body links, statuses, `<dependency_signals>` — and derives the target-artifact set from each task's own scope and links, so it works on any repo's tasks tree with no repo-specific assumptions.

## Context

The family's existing surfaces each look at the wrong granularity for this class. `task_check` and `task_auto_check` judge one task at a time (the base `<readiness_checklist>`), so a cross-task finding is outside their structural reach. `task_fix`'s assess phase walks every task with format-level advisory checks and never reads the target artifacts; its `<surface_for_review>` carries one bare cross-task bullet — "Contradictions between tasks — mirror `wiki_fix`'s contested protocol" — that names an output shape but no detection procedure. `auto_shaper_task` resolves escalated defects but only receives what task_fix's assess produces. No surface reads a cohort plus its shared target artifacts in one head.

The motivating session, generalized: a 17-task cohort sharing one scope was assessed jointly against the plugin it targets, on the prompt "should these all ship, or do some need altering or deferring to stay coherent with each other and the current code?". The joint read surfaced, with greppable evidence: one task introducing a warn-severity finding that recreated exactly the unreachable-clean-bar hazard a sibling task existed to fix; one edit double-owned by two tasks while a third assumed one of them owned it; a task enumerating one of the five sites its own rule implied; four sibling-file sites missing from another task's sweep; sibling tasks answering the same surface-versus-auto-repair question oppositely — one distinction principled, one accidental; quoted anchors invalidated by siblings that had shipped since; and references to finished archived tasks phrased as still pending. None of this is visible from any single task file, and each would have degraded the target artifacts if shipped blindly. The subsequent reconcile pass repaired ten task files with minimum edits, left every status standing, and surfaced nothing — every call settled from task intent, sibling tasks, archived precedent, or the code.

Placement follows the shipped precedent in [task-family_autonomous-tree-shaper.md](archive/task-family_autonomous-tree-shaper.md): whole-tree capability grows inside `task_fix` rather than as a second skill, heavy judgement routes through the existing `auto_shaper_task` escalation with `auto_verifier_task` gating, and a family rule is authored once in the base `task` skill (the `<readiness_checklist>` precedent) and cited by its consumers.

Files involved:

- [plugins/ai_dev/skills/task/SKILL.md](../plugins/ai_dev/skills/task/SKILL.md) — the new cohort-coherence lens set, a tagged sibling section to `<readiness_checklist>`.
- [plugins/ai_dev/skills/task_fix/SKILL.md](../plugins/ai_dev/skills/task_fix/SKILL.md) — the opt-in mode: activation, cohort selector, workflow hook, report shape; the `<surface_for_review>` "Contradictions between tasks" bullet rewritten in place to route through the lens set.
- [plugins/ai_dev/agents/auto_shaper_task.md](../plugins/ai_dev/agents/auto_shaper_task.md) — accept cohort-coherence defects in its escalated defect set, citing the base lens set by tag.

## Approach

1. **Author the lens set once in the base `task` skill**, under one greppable tag, defined over a cohort C (the selected live tasks) and the shared target-artifact set T (the union of C's `scope` directories and the files C's bodies link):
   - **Joint orientation.** Read every task in C in full and read T once; every later lens runs against that shared context — the shared read is what makes N premise checks affordable and is the precondition for every cross-task lens.
   - **Premise freshness against shipped state.** The base premise check applied cohort-cheap, per task: quoted anchors that no longer grep in T, references to archived tasks phrased as pending, described gaps the code has since closed. An invalidated premise makes the task a defer candidate with disposition handed to the user, per the base rule; drifted details are ordinary repair findings.
   - **Shared-surface ownership.** Map each task's claimed edits onto T; flag an edit claimed by two or more tasks, and an edit the cohort's own rules imply that no task owns. Repair shape: one owner, a verify-only step in the other task, reciprocal coordination links.
   - **Emergent contradiction.** Derive each task's post-state and check pairwise compatibility on shared surfaces and against invariants other cohort tasks establish or repair. Canonical case: task A carves an exception so an autonomous loop can terminate cleanly, and task B adds a finding at the severity that re-blocks that loop with no handling. Repair shape: change the offending parameter with its rationale recorded once, or couple the change to the sibling that owns its precondition.
   - **Posture consistency.** The same design question answered differently across siblings (severity tier, auto-fix versus on-demand, naming): reconcile an accidental divergence; record a principled one on the task that carries it.
   - **Sweep completeness.** When a task states a rule and enumerates its edit sites, search T for the rule's actual site set and flag the un-enumerated remainder.
   - **Ship-order coherence.** Derive waves from the base `<dependency_signals>` plus shared surfaces; name the tasks that stay coherent only when landed together or in a stated order.
2. **Wire the opt-in mode into `task_fix`.** Activation on an explicit cohort-coherence request ("do these tasks ship coherently", "assess the <scope> backlog against the code", "reconcile the cohort"); selector defaults to the whole live tree when the user names no filter. The everyday mechanical pass is unchanged and never reads T. The assessment report is the phase-one deliverable: per-task verdicts with concrete minimum edits, ship-order waves, and greppable evidence for every finding; the pass writes nothing until the user disposes.
3. **Reconcile on acceptance.** Route accepted repairs through task_fix's existing split: staleness and anchor refreshes inline; judgement reconciliations via the existing `auto_shaper_task` escalation, verifier-gated, single writer. Repairs preserve each task's frozen `## Goal`, follow the base **Decide or label** procedure (reconcile from task intent, then guardrails, then sibling and archived tasks, then the code; surface what that evidence leaves open), bump `updated`, and re-lint.
4. **Status discipline — the change-significance rule.** A repair that leaves a task's Goal, Approach, and Acceptance semantics unchanged leaves its status standing, `ready` included; a repair that alters the implementation contract flags the task for re-check in the report. Stamps stay owned by `task_check` / `task_auto_check`; the pass never writes `ready`.

**Out of scope:**

- Implementing any cohort task — `task_implement` owns builds; this pass only makes the backlog coherent to build from.
- Readiness promotion — the pass flags re-checks and never stamps `ready`; promotion stays with `task_check` / `task_auto_check`.
- A new user-facing skill or a new agent — the archived tree-shaper decision holds: `task_fix` stays the sole whole-tree entry point and the existing agents carry escalation.
- Scheduled or default-on runs — the pass is opt-in per invocation, and the default `task_fix` behavior is unchanged.

## Acceptance

1. The base `task` skill carries the cohort-coherence lens set under one greppable tag, covering all seven lenses from Approach step 1; `task_fix` and `auto_shaper_task` cite that tag rather than restating the lenses, and `rg` for the tag returns the definition plus the two citations.
2. `task_fix` documents the opt-in mode (activation, selector, joint read, report shape, propose-then-act), and its former `<surface_for_review>` "Contradictions between tasks" bullet is superseded in place by a pointer into the mode — `rg "mirror .wiki_fix..s contested protocol" plugins/ai_dev/skills/task_fix/SKILL.md` returns no match.
3. A staged fixture backlog, following the repo's harness conventions, plants: (a) one edit double-owned by two tasks; (b) a task whose quoted anchor a finished fixture sibling invalidated; (c) a pair where one task's new finding re-blocks the loop exception a sibling establishes; (d) a task enumerating a subset of the sites its own rule implies in a fixture artifact; (e) two siblings answering the same severity question oppositely with no recorded reason; (f) one genuinely underdetermined fork. The assessment surfaces (a)–(e) as findings with evidence and (f) as a labeled decision with options and a suggested path.
4. The reconcile pass over the accepted findings fixes (a)–(e) with the named repair shapes — single owner plus verify-only counterpart, refreshed anchor, recorded-rationale parameter change, completed enumeration, reconciled-or-recorded posture — does not auto-resolve (f), leaves every fixture status unchanged, and bumps `updated` on every edited file.
5. The change-significance rule holds on fixtures: a `ready` fixture task receiving only an additive out-of-scope note stays `ready`; a fixture whose Acceptance semantics changed is flagged for re-check in the report, not re-stamped.
6. A default `task_fix` invocation on the same fixture tree runs the existing mechanical pass with no cohort-coherence section in its report; the mode's report appears only on the explicit request.
