---
description: Add a task_fix advisory check that surfaces task bodies restating a rule the project's standing instructions own, proposing citation or removal instead of the copy.
scope: plugins/ai_dev/skills/task_fix
created: 2026-06-09T12:34:16
updated: 2026-06-09T13:32:19
status: open
---

# task_fix surfaces restated standing rules

## Goal

The whole-tree sweep catches rule copies: `task_fix` gains an advisory check
that surfaces every task body restating a rule the project's standing
instructions own — copied rule prose and generic project-gate acceptance
items alike — proposing citation or removal of the copy, so purges of copied
boilerplate happen once instead of repeating as fresh tasks reintroduce it.

## Context

- Ordering — implement after these have landed:
  - [task-skill_self-sufficiency-concept.md](task-skill_self-sufficiency-concept.md)
    lands the cite-don't-restate corollary in the base skill; the new check
    cites that corollary as its rule source instead of wording it again.
  - [task-skill_acceptance-contract.md](task-skill_acceptance-contract.md)
    lands the task-specific-gates clause; the advisory's acceptance-item
    boundary cites that clause.
- Evidence: the version-bump rule (owned by this repo's `CLAUDE.md` at commit
  time) was copied into 13 task bodies, drifted into two inconsistent
  wordings ("one-bump-per-session" vs "one-bump-per-commit"), and was
  mass-stripped in commit 3e48d5e — then recurred in three fresh tasks within
  two days, needing a second strip. Generic `make lint` / dry-run acceptance
  items showed the same pattern on 2026-06-10: present in every open
  task-skill task, restating the commit-time gates `CLAUDE.md` already
  mandates. Without a standing detector the purge repeats forever.
- Edit site: the advisory checks in `task_fix/SKILL.md`'s assess phase
  (alongside topic mixing, single-shot readiness, and cross-link value),
  which already follow the surface-don't-auto-fix pattern for judgement
  calls.
- Detection input: the check reads the project's standing instruction
  documents (`CLAUDE.md` / `AGENTS.md` and equivalents) and compares
  task-body passages against the rules stated there.

## Approach

- Add the advisory to `task_fix`'s assess walk: a body passage restating a
  rule a standing instruction document owns is surfaced as a judgement call,
  quoting the matched rule and proposing the fix — replace the copy with a
  citation, or drop it when the surrounding text carries nothing else.
  Auto-removal stays out: drift between copy and source is exactly why the
  user's explicit go-ahead decides.
- Draw the acceptance-item boundary per the base contract's
  task-specific-gates clause: a generic project-gate item (lint, dry-run,
  full suite — an outcome this task's work does not change) is a restatement
  and gets surfaced; a task-specific executable check (a staged fixture, a
  named new scenario, a file state the task creates) draws no finding.
- Point the check at the base skill's cite-don't-restate corollary and gate
  clause for the rule definitions rather than restating either in
  `task_fix`.
- Keep historical narration compliant: a body *describing* that a rule
  existed or changed (changelog-style context) draws no finding; the check
  targets passages that *instruct* the implementer with a copied rule.

## Acceptance

- `task_fix/SKILL.md`'s assess phase lists the restated-standing-rule
  advisory with the surface-and-propose disposition, the generic-gate
  acceptance-item boundary, and the instruct-vs-narrate distinction.
- The advisory defers to the base corollary and gate clause for the rule
  definitions (one statement family-wide).
