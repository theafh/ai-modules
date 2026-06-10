---
description: Require task_check to verify every reported issue against the repo before ranking it, and move pure style findings into an unnumbered tail below the numbered issues list.
scope: plugins/ai_dev/skills/task_check
created: 2026-06-09T12:34:16
updated: 2026-06-09T13:32:19
status: open
---

# Grounded check issues: verify on disk, style notes to the tail

## Goal

`task_check` reports only issues it has verified against the repository, and
its numbered list carries implementation-divergence risks exclusively: every
entry in `## Issues` is grounded by checking the actual files, code, and
policies it implicates before it is written, and pure style findings
(negation framing, phrasing polish) move to a short unnumbered tail below the
ranked list.

## Context

- Evidence from mined check runs (2026-05/06): ungrounded checks emitted
  disk-disprovable issues — a "stale eval path" finding was retracted on the
  next run once the path was verified to exist — and unstable verdicts on an
  unchanged file (ready, then not-airtight with two new issues under a higher
  effort setting). The one check that verified every claim itself (running
  shellcheck and counting variable usages on the park-managed-rules task)
  produced one cosmetic finding and a task that sailed through implement,
  audit, and finish without friction.
- Style findings were acted on zero times across every mined session, while
  the numbered list is worked as a coordinate system — replies triage per
  number, including rejections. Polish entries dilute that list.
- Edit sites in `task_check/SKILL.md`: the `<assessment>` step gains the
  grounding requirement; the `<output_contract>` gains the numbered-list /
  style-tail split.
- Ordering — implement after these have landed:
  - [task-skill_shared-readiness-checklist.md](task-skill_shared-readiness-checklist.md)
    rewrites `<assessment>` to defer to the relocated base checklist; the
    grounding requirement is added to that settled shape.
  - [task-skill_soft-pointer-references.md](task-skill_soft-pointer-references.md)
    lands the locate-by-label clause in `<output_contract>`; the style-tail
    split extends the same settled block.

## Approach

- In `<assessment>`, require verification before reporting: an issue enters
  the report only after the check confirmed it against the repo — read the
  file the issue implicates, run the command the acceptance names, check the
  policy the task cites. An unverifiable suspicion is voiced as a question in
  the general assessment, never as a numbered issue.
- In `<output_contract>`, split the report: the ordered `## Issues` list
  carries only verified issues that risk a wrong or divergent one-shot
  implementation; style-level findings (negation framing, wording polish) go
  to a short unnumbered "Style notes" tail after the list, omitted when
  empty.
- Keep the rest of the contract intact: the general-assessment lead, the
  ranked ordering, the read-only stance.

## Acceptance

- `task_check/SKILL.md` `<assessment>` requires on-disk verification before
  an issue is reported, with the unverifiable-suspicion disposition stated.
- `<output_contract>` defines the numbered list as verified
  implementation-divergence issues only and routes style findings to an
  unnumbered tail.
