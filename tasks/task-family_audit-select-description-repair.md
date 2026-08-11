---
description: Give task_audit the missing dual-audience Use when clause without ceding verbs, and replace the harness vendor name in task_select's description with neutral wording.
scope: "task_* family: task_audit + task_select descriptions"
created: 2026-08-11T18:58:50
updated: 2026-08-11T18:58:50
status: open
reported-by: Andreas Hoffmann
---

# Repair the task_audit and task_select descriptions

## Goal

Two `task_*` sibling descriptions meet the standing repo rules they currently
miss. `task_audit` gains the `Use when` trigger clause the dual-audience
description rule requires, so a user browsing skills and an LLM router both get
what they need from it. `task_select` loses the single harness vendor name from
its description, so the text reads correctly on every harness the skill deploys
to. Trigger routing for the family comes out no worse than its recorded baseline.

## Context

`task_audit` is the only skill the skill doctor's `discovery_safety.py` flags,
under the code `description_missing_triggers`. Its description opens "Audit one
implemented or finished task against the actual codebase. Use after implementation
or for drift checks before close out." It carries no `Use when` clause and no
user-phrase variants, which leaves its trigger surface thinner than every sibling's
while the standing repo rule asks a description to serve a browsing user and a
router deliberately.

`task_select`'s description names one harness vendor, in the clause "asks Codex to
pick or prioritize backlog work". The standing repo rule requires
deployment-agnostic cross-references, and the deploy dry-run confirms this skill
also lands in the Claude, Cursor, Antigravity, Copilot, and OpenCode configuration
directories, where naming a single vendor reads wrong.

[The sibling trigger-routing task](archive/task-family_sibling-trigger-routing.md)
bounds how these edits may be written. It measured a description-sharpening attempt
across the base `task`, `task_audit`, and `task_fix` descriptions that ceded verbs
and bound siblings tighter, recorded a regression from precise 14/25 to 12/25 and
family 20/25 to 14/25, and reverted it. Three findings from that run constrain this
one: hedging a description with clauses ceding an action verb made the model fire
no family skill at all, skill-name tokens dominate description wording, and hedged
descriptions cost two clean baseline passers. It also records the phrasing "is this
task actually done? verify it against the code" routing to the base `task` skill as
a known accepted limitation, so this task adds trigger coverage without chasing
that case.

That same task fixes the measurement protocol these edits are judged against:
`--runs-per-query 3`, a 50% per-query threshold, and the verdict taken from the
written `results.json` summary of a run rather than a single invocation.

## Approach

Rewrite `task_audit`'s description in place so its existing purpose summary stays
the opening and a `Use when` clause follows it, carrying the phrasings a user
actually types for this skill — verifying a believed-done task, checking claimed
completion against the code, a drift check before close-out. Add trigger coverage
only; leave the description free of any clause that cedes a verb to a sibling or
hedges the skill's own territory, since that is the shape that regressed.

Rewrite `task_select`'s description in place so the vendor clause becomes neutral,
naming the asking party generically the way its sibling descriptions do while
keeping the surrounding trigger phrases intact. This is a wording substitution
rather than a trigger change.

Re-measure after the edits, using the protocol above, and treat the recorded
comparison as the deliverable. The measurement needs the edited descriptions live,
and the standing repo rule gates that deploy on the user's explicit ask, so request
it rather than running it unprompted.

**Out of scope:** editing the base `task` skill's description, and adding any
verb-ceding or hedging clause to either description. Both are the reverted lever
[the sibling trigger-routing task](archive/task-family_sibling-trigger-routing.md)
holds rejected.

## Acceptance

- `python3 plugins/ai_dev/skills/skill_doctor/scripts/discovery_safety.py plugins/ai_dev/skills/task_audit plugins/ai_dev/skills/task_select`
  reports no `description_missing_triggers` warning for `task_audit`, where it
  reports one today, and adds no new warning for either skill.
- `task_audit`'s description contains a `Use when` clause, and its prior
  trigger-free wording no longer appears in the file.
- `task_select`'s description names no harness vendor: a case-insensitive search of
  that description for `codex`, `claude`, `cursor`, `antigravity`, `copilot`, and
  `opencode` returns nothing, where it matches today.
- Neither edited description contains a clause ceding an action verb to a sibling
  or hedging the skill's own territory.
- The family trigger evals are re-run under the recorded protocol
  (`--runs-per-query 3`, 50% per-query threshold), and the precise rate read from
  the run's `results.json` summary is at or above the rate recorded in
  [the sibling trigger-routing task](archive/task-family_sibling-trigger-routing.md)'s
  Findings note. The comparison is written into this task body as a Findings note
  citing the new run directory.
- A precise rate below that baseline reverts both description edits and records the
  measured drop in the same Findings note, leaving the descriptions as they stand
  today. The recorded measurement is the deliverable rather than its direction.
