---
description: Add a read-only task_explain sibling skill that gives a compact high-level what/why/how readout of one task file, and register it across the family rosters, READMEs, and manifests.
scope: plugins/ai_dev
created: 2026-06-28T14:36:58
updated: 2026-06-28T16:46:25
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Add the `task_explain` sibling skill

## Goal

Add a small, read-only sibling skill named `task_explain` to the `ai_dev` plugin's `task_*` family. Given one task file, it produces a compact, high-level explanation of that task organized along three beats — **what** the task is about, **why** it is being done, and **how** it is meant to be achieved — so a reader can orient on a task without reading the whole file.

The skill is light: a thin front end over the base `task` skill, the way `task_create` is. It cites the base skill for discovery and file-format knowledge rather than re-deriving them, and carries only the behaviour unique to explaining a task. Its output is an explanation, never an edit — it does not change task files, status, timestamps, or location, and it does not judge readiness or recommend what to work on next, which belong to its siblings.

The skill encodes a request pattern that recurs in practice, illustrated by the phrasing that motivated it: "give me a high-level, compact description of what this task is about, why it is done, and how it is supposed to be achieved" for a named task.

## Context

The `task_*` family already has read-only members that each answer one question about a task without editing it: `task_check` (is it ready to build), `task_select` (what should I work on next), and `task_audit` (is it done). `task_explain` adds a fourth, orientation-focused question — what is this task about, why, and how — aimed at understanding rather than judgement. No single sibling is the right thing to clone: `task_create` is the model for *form and weight* (a light, thin front end that cites the base skill), while the finished [`task_select` sibling-skill task](task-family_select-sibling-skill.md) is the precedent for the *read-only contract* and the *registration footprint* this task repeats — not for `task_select`'s ranking, scoring, whole-backlog scan, or archive-exclusion, all of which `task_explain` deliberately omits.

Affected surfaces:

- New skill body at `plugins/ai_dev/skills/task_explain/SKILL.md`.
- The `<family>` routing block carried by every task-family `SKILL.md` (the base `task` skill plus every `task_*` sibling) enumerates the family members; each must gain a `task_explain` entry. The base `task` skill's `<family>` block is the canonical roster the siblings mirror.
- The per-skill bullet list in `README.md` and in `plugins/ai_dev/README.md`, the skills directory tree in `README.md` that enumerates `task_create/`, `task_check/`, … , and the read-only-helpers framing in those READMEs (the sentence answering "is this ready to build, what should I work on next, and is it done").
- Plugin and marketplace metadata: `plugins/ai_dev/.claude-plugin/plugin.json`, `plugins/ai_dev/.codex-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `.agents/plugins/marketplace.json`.

## Approach

Write `plugins/ai_dev/skills/task_explain/SKILL.md` following the standing repo rules for skill authoring — positive, action-oriented wording per `ai_instruction_writing` and pseudo-XML organization per `ai_instruction_formatting`; this task supplies only the `task_explain`-specific behaviour. Ship it at `version: 1.0.0` and apply the standing repo rules for adding a skill to an existing plugin, including the `ai_dev` plugin version bump and metadata.

Compose the skill from scoped precedents rather than mirroring one sibling — this is what keeps a one-shot implementer on the rails:

- **Form, weight, and base-skill deference come from `task_create`.** Reuse its section skeleton (`<role>`, `<when_to_activate>`, `<authority>`, `<path_resolution>`, `<workflow>`, `<output_contract>`, `<family>` under one root tag), its thin-front-end framing, and its `<authority>` stance of citing the base skill — trimmed to the `<discover>` and `<file_format>` / `<body>` that reading a task needs.
- **The read-only contract and the registration footprint come from `task_select`.** Adopt its no-mutation sentence ("make no file edits, status changes, timestamp changes, or archive moves") and repeat the registration surfaces its sibling-add covered.
- **Single-target resolution (including `tasks/archive/`) and the three-beat what/why/how output are this skill's own core.** Neither precedent supplies them.

Do not carry over: `task_create`'s write / lint / timestamp / `<prior_art>` / `<lossless_conversion>` / readiness-self-check spine, which is create-only; and `task_select`'s scoring rubric, ranking method, whole-backlog filtering, and archive-exclusion, which are selection-only. Each is machinery `task_explain` must not grow.

Behaviour the skill defines:

- **Role.** A read-only orientation helper that explains one task file at a high level. A thin front end over the base `task` skill: cite its `<discover>` and `<file_format>` rather than restating them.
- **Activation.** Fire on phrasings like "explain this task", "what is this task about", "give me a high-level / compact description of this task", "what's the goal / why / how of \<task\>", "summarize this task", and "walk me through \<task\>". Route to `task_check` for readiness, `task_select` for next-work, `task_audit` for done-verification, and the base `task` / `task_create` skills for any edit.
- **Target resolution.** Resolve exactly one task from a path, an exact or partial name, or "this task" in conversation context, matching across both `tasks/` and `tasks/archive/`. Explaining an archived task is in scope — orientation applies to closed work too, unlike `task_select`. When the reference is ambiguous, list the candidates and ask one sharp disambiguating question before explaining.
- **Output contract.** A compact, high-level explanation in flowing prose, organized along the three beats: what the task is about (its goal and user-visible deliverable in plain terms), why it is being done (the motivating problem and rationale), and how it is to be achieved (the intended approach and mechanism, at altitude). Synthesize and explain rather than echoing the file's sections verbatim. Add a short orienting frame — the task's status and scope, plus any load-bearing dependencies or cross-linked tasks — and lead with the bottom line.
- **Read-only guarantee.** Never edit the task body, frontmatter, status, timestamps, or location, and never run a fix or lint mutation — the no-mutation contract borrowed from `task_select` above.

Decided (resolve these in the skill; do not reopen):

- `task_explain` is an off-chain read-only orientation helper, not a stage in the manual `create → check → select → implement → audit → finish` lifecycle. Add it to the family roster wherever members are enumerated, and present it in the READMEs as a read-only orientation helper distinct from the three read-only gates; the "three questions" gates sentence stays accurate as-is, and the lifecycle-chain sentence is left unchanged.
- Filename scope `task-skill` and frontmatter scope `plugins/ai_dev`, matching the `task_select` sibling-creation precedent.

Registration, in the same change:

- Add a `task_explain` entry to the `<family>` block in every task-family `SKILL.md`, keeping the base `task` skill's roster and the siblings' rosters in agreement.
- Add a `task_explain` bullet to the per-skill lists in `README.md` and `plugins/ai_dev/README.md`, add `task_explain/` to the skills directory tree in `README.md`, and account for it in the read-only-helpers framing there.
- Register the skill in `plugins/ai_dev/.claude-plugin/plugin.json`, `plugins/ai_dev/.codex-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `.agents/plugins/marketplace.json`. These four manifests carry no per-skill array — each names the family's siblings only inside its prose `description` string (the enumeration reading "...create, check, auto-check, select, implement, audit, finish, and fix siblings..."). Weave `explain` into that enumeration in each of the four files; there is no separate per-skill entry to add.

Coverage: add activation/trigger coverage consistent with the repo's convention for behaviour-only skills (see `tests/` and the standing testing rules) — confirm `task_explain` fires on the orientation phrasings above and stays distinct from the sibling triggers — or record why coverage is absent.

## Acceptance

- `plugins/ai_dev/skills/task_explain/SKILL.md` exists with frontmatter `name: task_explain`, `version: 1.0.0`, and a description distinct from its siblings, and its body is organized in pseudo-XML with positive, action-oriented wording.
- Given one task (by path, exact or partial name, or "this task" in context, resolving across `tasks/` and `tasks/archive/`), the skill returns a compact high-level explanation covering all three beats — what it is about, why it is done, how it is achieved — plus the task's status and scope; on an ambiguous reference it lists candidates and asks before explaining. Proven on one fixture task: the explanation names the goal, the motivation, and the approach without reproducing the file verbatim.
- The skill performs no writes: a run over a fixture task leaves the file's bytes, status, timestamps, and location unchanged.
- The skill's role text states its boundary against `task_check`, `task_select`, and `task_audit` — it explains intent and plan, and does not judge readiness or done-ness or recommend next work.
- Every task-family `SKILL.md` `<family>` block lists `task_explain`, and the base `task` skill's roster and the sibling rosters agree; no roster omits it.
- `README.md` and `plugins/ai_dev/README.md` list `task_explain` in their per-skill bullets, `README.md`'s skills directory tree includes `task_explain/`, and the read-only-helpers framing in those READMEs accounts for it while the three-questions gates sentence and the `create → check → select → implement → audit → finish` lifecycle sentence stay unchanged.
- In each of `plugins/ai_dev/.claude-plugin/plugin.json`, `plugins/ai_dev/.codex-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `.agents/plugins/marketplace.json`, the `ai_dev` `description` string's task-sibling enumeration names `task_explain`, with one canonical sibling list per file rather than the prior enumeration that stopped at "finish, and fix siblings"; the new skill ships at `1.0.0` and the `ai_dev` plugin version rises in lockstep across all four files per the standing repo rules for adding a skill.
- Behaviour/trigger coverage for `task_explain` exists consistent with the repo's behaviour-only-skill convention, or the task records why it is absent.
- `make lint` passes.
