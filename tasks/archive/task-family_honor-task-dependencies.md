---
description: Lift the dependency-signal taxonomy into the base task skill, add a task_implement pre-flight stop on live prerequisites, and repoint task_select to inherit it and honor an out-of-scope inbound note.
scope: plugins/ai_dev/skills
created: 2026-07-14T19:30:46
updated: 2026-07-18T18:47:15
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Honor task dependencies across the task_* family

## Goal

Make the `task_*` family honor inter-task dependencies at both points where a user acts on a single task — choosing what to build next, and building it — from one shared definition of what makes a task a prerequisite. The general behaviour is that a task with live prerequisites, meaning other backlog tasks that must ship first, is never quietly built or recommended ahead of them, so the user does not build blocked work and force a rework.

The user-visible outcome:

- The base `task` skill gains one authoritative dependency-signal taxonomy that the family inherits, so `task_select` and `task_implement` detect prerequisites the same way instead of each carrying their own copy.
- `task_implement`, pointed at one task, first checks whether that task depends on other live tasks. When it does, the skill surfaces those prerequisites in dependency order with the evidence for each, asks whether the task should really be implemented before them, and **stops before any code edit** until the user answers. On an explicit go-ahead it proceeds; with no live prerequisites it proceeds without interruption.
- `task_select`, already dependency-aware, is repointed to inherit the base taxonomy and reinforced so an explicit ordering note is honored no matter which of the two related tasks authored it — including when the task carrying the note sits outside a user-applied scope filter.

Both skills keep their existing roles: `task_select` stays read-only, and `task_implement`'s gate is read-only until the user green-lights the build.

## Context

Three files change:

- `plugins/ai_dev/skills/task/SKILL.md` (the base `task` skill)
- `plugins/ai_dev/skills/task_select/SKILL.md`
- `plugins/ai_dev/skills/task_implement/SKILL.md`

**Why the base skill.** The repo's `CHARTER.md` invariant "Skill-family rules live in the family base skill when they govern the whole family; front-end skills inherit those rules instead of carrying divergent copies" applies the moment both `task_select` and `task_implement` need the dependency taxonomy. So the taxonomy is authored once in the base `task` skill and inherited by both front-ends, rather than living in a peer front-end and being cross-cited.

**`task_select` is already dependency-aware — this repoints and reinforces it, it is not a rebuild.** The archived [dependency-aware-ordering task](task-family_select-dependency-aware-ordering.md) shipped that behaviour, and the current `task_select/SKILL.md` carries it: the `<scoring_criteria>` **Dependency and ordering relationships** criterion enumerates the relationship signals (explicit relationship prose such as `depends on` / `blocked by` / `must follow` / `after`, dependency cross-links, forward references to an artefact another candidate creates, and shared-surface collisions), defines a prerequisite as a live eligible candidate not yet done, and separates hard ordering dependencies from soft companion relationships; `<ranking_method>` ranks a prerequisite ahead of its dependent regardless of impact; and the `<workflow>` step **Derive dependency and ordering relationships.** does the derivation. Today that taxonomy lives only in this criterion — the lift moves the definition into the base skill so both front-ends inherit it.

**`task_implement` has no dependency awareness at all today.** Its `<workflow>` opens with **Read the task end-to-end.**, then **Load the guardrails.**, then **Understand the existing codebase, and confirm the work isn't already done.** — that codebase step checks only whether *the artifact or behaviour itself* is already built, never whether the task depends on another live task. Pointed directly at task A while live task B must ship first, `task_implement` builds A regardless. This gate is the substantial new work.

**The one `task_select` gap is directional.** Its derivation step reads *the filtered candidates' own* relationship prose and forward references and resolves them against the full live eligible set. So when the ordering note lives in the *other* task — task B's body says "B must ship before A" while candidate A's body is silent — the note is caught only because B is itself read as a candidate. Under a scope filter that excludes B, B's inbound note is never read, so A can be recommended as unblocked even though B must precede it. The archived task already handled the mirror case where A's *own* body names an outside-scope prerequisite; the inbound-note direction is what remains.

A prerequisite is a live eligible task — frontmatter status `open`, `checked`, or `ready` — that is not yet done; a relationship to an `implemented`, `audited`, `finished`, `deferred`, or archived task is already satisfied and imposes no ordering. That rule and the base `task` skill's `<markdown_policy>` definition of a task-to-task dependency link ("this task builds on, extends, or must follow the other") are the ground the new taxonomy block builds on.

## Approach

Edit the three `SKILL.md` files in positive, action-oriented language and their existing pseudo-XML structure. Author the taxonomy once in the base skill; both front-ends inherit it.

**Base `task` skill — author the shared taxonomy:**

1. Add a dependency-signal taxonomy block (for example `<dependency_signals>`) to `plugins/ai_dev/skills/task/SKILL.md` that defines, once for the family: the prerequisite rule (a live eligible task with status `open`, `checked`, or `ready` that is not yet done, where a relationship to an `implemented`, `audited`, `finished`, `deferred`, or archived task is satisfied and imposes no order); the relationship signals (explicit ordering prose `depends on` / `blocked by` / `must follow` / `after` and companion references, dependency cross-links, forward references to an artefact another task creates, and shared-surface collisions); bidirectionality (a task is a prerequisite by its own outbound signals or by another live task's inbound declaration); and the hard-ordering-dependency versus soft-companion-relationship split, with the directional-evidence rule that a shared surface is a hard dependency only when one task creates, renames, removes, or rewrites a block, symbol, rule, or file state the other consumes. Cross-reference the existing `<markdown_policy>` dependency-link definition rather than restating it, and place the block so `<markdown_policy>` and the front-end skills can cite it by a verbatim label.

**`task_select` — inherit the taxonomy, add the inbound direction:**

1. Rewrite the `<scoring_criteria>` **Dependency and ordering relationships** criterion in place so it inherits the base taxonomy block instead of re-enumerating the relationship signals and the prerequisite rule, keeping only its ranking-specific content: that a hard ordering dependency sequences the prerequisite ahead of its dependent while soft companion relationships are surfaced without reordering. Preserve the shipped ranking behaviour.
2. Rewrite the `<workflow>` step **Derive dependency and ordering relationships.** in place so it also scans the full live eligible set for inbound ordering declarations pointing at any candidate — a live task whose body names a first-ship order over a candidate or forward-references an artefact the candidate creates — and honors that note whether it was authored in the candidate or in the pointing task, including when the pointing task is outside the applied scope filter. Leave `<ranking_method>`'s hard-versus-soft application intact.

**`task_implement` — add the pre-flight gate:**

1. Insert a new pre-flight dependency-gate step into `<workflow>` immediately after the **Read the task end-to-end.** step and renumber the steps that follow. The gate runs before the guardrails-load, codebase, and implementation steps, and it performs no code edit and no status change while it runs.
2. Have the gate apply the base dependency-signal taxonomy to the task-at-hand in both directions — outbound signals in the task-at-hand's own body, and inbound ordering declarations authored in other live eligible tasks that point at it — count only live eligible prerequisites, then list them in dependency order (a prerequisite's own live prerequisites named first), surface the evidence for each (the signal and the task file it came from), ask whether the task-at-hand should really be implemented ahead of them, and **stop** with no code edit until the user answers. Surface any soft companion relationships alongside without letting them force the stop, and surface a dependency cycle rather than looping on it.
3. On the user's explicit go-ahead, proceed into the rest of the workflow; when the gate finds no live prerequisites, proceed without interrupting the user. Rewrite the `<workflow>` ordering preamble **Make no code edit before the first three steps are complete.** in place so it accounts for the inserted gate step and states the gate can stop the workflow before any later step runs.

Non-goals: keep the dependency-signal taxonomy authored once in the base skill's block and inherited by both front-ends — do not leave the definition in a front-end skill and do not copy the signal enumeration into more than one place. Do not add a dependency field to the task-file frontmatter or otherwise change the base `task` skill's file format; the relationships stay inferred from existing content. Do not change the eligibility rule in `task_select`'s `<candidate_policy>`, make `task_select` write files, or let `task_implement`'s gate edit code or change status before the user confirms. Do not add scripts or new tooling. Keep this to the skill prose change proven on staged fixtures; broader eval-suite growth is a separate session per the standing repo rule that keeps skill changes and harness expansion apart.

## Acceptance

- `plugins/ai_dev/skills/task/SKILL.md` carries a single dependency-signal taxonomy block defining the prerequisite rule, the relationship signals, bidirectionality, and the hard-versus-soft split with the directional-evidence rule for shared surfaces, cross-referencing `<markdown_policy>` for the dependency-link marker rather than restating it.
- `task_select/SKILL.md`'s `<scoring_criteria>` **Dependency and ordering relationships** criterion inherits that base taxonomy instead of enumerating the relationship signals and the prerequisite rule itself, retaining only its ranking-specific application; a grep confirms the signal enumeration and prerequisite definition live in the base skill and are not duplicated in `task_select`.
- `task_select/SKILL.md`'s `<workflow>` step **Derive dependency and ordering relationships.** is rewritten in place to also scan the full live eligible set for inbound ordering declarations pointing at a candidate and to honor an ordering note whether authored in the candidate or in the pointing task, including when the pointing task is outside the scope filter, while `<ranking_method>`'s hard-versus-soft application is unchanged.
- `task_implement/SKILL.md`'s `<workflow>` carries a new pre-flight dependency-gate step placed immediately after the **Read the task end-to-end.** step and before the guardrails-load and codebase steps, and the step states it makes no code edit and no status change while it runs.
- The gate applies the base dependency-signal taxonomy to the task-at-hand in both directions (outbound signals in its body, inbound ordering declarations in other live eligible tasks) and counts only live eligible tasks as prerequisites, drawing both the signals and the prerequisite rule from the base skill rather than restating them.
- On one or more hard prerequisites the gate lists them in dependency order with per-item evidence, asks whether to implement the task-at-hand first, and stops without any code edit or status change; soft companion relationships are surfaced without forcing the stop, and a dependency cycle is surfaced rather than looped on.
- On the user's explicit go-ahead the gate proceeds into the rest of the workflow, and with no live prerequisites it proceeds without interrupting the user.
- The `task_implement/SKILL.md` `<workflow>` preamble that read **Make no code edit before the first three steps are complete.** is rewritten in place so it covers the inserted gate step and states the gate can stop the workflow before later steps run, leaving one canonical ordering statement.
- A grep over `task_implement/SKILL.md` and `task_select/SKILL.md` confirms both cite the base skill's dependency-signal taxonomy for the signals and the prerequisite rule rather than each carrying their own enumeration.
- Running `task_implement` against a staged fixture of task A whose body forward-references a block that live task B creates surfaces B as a prerequisite, lists it, asks, and stops with no code edit; running it against a staged task A with no live prerequisites proceeds without a dependency stop.
- Running `task_select` under a scope filter that includes candidate A but excludes task B, where B's body names a first-ship order over A, reports B as A's blocking prerequisite; the archived fixtures — task B forward-referencing a block A creates yields A ranked first, and two file-disjoint companions surface without a forced order — still hold.
