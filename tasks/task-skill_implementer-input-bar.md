---
description: "Align the sibling skills' one-shot bar sentences to the base self-sufficiency concept — replacing the sole-input vacuum phrasings — and have checks judge tasks as consumed."
scope: "task_* family skills"
created: 2026-06-09T10:45:16
updated: 2026-06-09T13:32:19
status: open
---

# Sibling bar sentences follow the self-sufficiency concept

## Goal

Every sibling skill states the family's bar the way
[task-skill_self-sufficiency-concept.md](task-skill_self-sufficiency-concept.md)
defines it in the base skill: a task file is enough on its own to implement,
and the implementer draws on everything actually available — the codebase, the
project's standing instructions (`CLAUDE.md` / `AGENTS.md` and equivalents),
the user. Checks judge tasks the way they are consumed: reliance on a standing
project rule reads as correct authoring, with the task citing the rule instead
of copying its text.

## Context

Builds on
[task-skill_self-sufficiency-concept.md](task-skill_self-sufficiency-concept.md),
which lands the concept and the base-skill rewrite (`<role>`, `<body>`,
`<single_shot_ready>`) — implement that task first; this one propagates the
definition into the siblings. Sites, all under `plugins/ai_dev/skills/`:

- `task_check/SKILL.md` `<assessment>`: "a one-shot AI coder receives this
  task as its sole input" — the sentence the readiness verdicts apply.
- `task_create/SKILL.md` `<workflow>` Gather step: "so a single-shot
  implementer could act on it from the file alone".
- `task_implement/SKILL.md` read-the-task step: "a single-shot implementer has
  everything needed from the file alone — treat the file as that contract".
- `task_fix/SKILL.md` single-shot-readiness advisory check: "act on from the
  file alone".

Motivation: the vacuum reading produced the family's worst observed false
positive (2026-06-02) — `task_check` demanded a version-bump acceptance bullet
although the repo's `CLAUDE.md` owns that rule at commit time — and it is why
repo rules were copied into 13 task bodies, where the copies drifted into two
inconsistent wordings and were mass-stripped (commit 3e48d5e), recurring in
fresh tasks two days later. ai-modules' own `CLAUDE.md` now guards the
version-bump case locally; the skills ship to other repos, so the corrected
bar belongs in the family itself.

Ordering:
[task-skill_shared-readiness-checklist.md](task-skill_shared-readiness-checklist.md)
relocates the `<assessment>` material around the bar sentence and follows
this task — with the sentence settled here first, the relocation moves it
unchanged.

## Approach

- Rewrite each site above in place to match the base concept: the task file is
  enough on its own, with every context actually available in play. Keep each
  site's own voice and brevity; the base skill carries the full formulation,
  the siblings echo it.
- In `task_check`, make the consumption stance explicit where the bar drives
  the verdict: a task that leans on a standing project instruction is judged
  as correctly authored when it cites the rule; flagging the absence of
  content a standing instruction owns is a false positive.
- Sweep the remaining family SKILL.mds (`task_audit`, `task_finish`) for
  further vacuum formulations and align any found.

## Acceptance

- `rg -i "sole input|only this file|from the file alone"
  plugins/ai_dev/skills/task*/SKILL.md` returns no matches (the base-skill
  sites are handled by the concept task this one builds on).
- The sibling echoes in `task_check`'s `<assessment>` and `task_create`'s
  Gather step carry the concept's two halves: file sufficiency and
  all-available-context.
- `task_check` treats reliance on cited standing rules as correct authoring.
