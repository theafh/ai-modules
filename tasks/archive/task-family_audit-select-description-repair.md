---
description: Repair task_audit and task_select descriptions for dual-audience Use when coverage and harness-agnostic wording; no regression vs the Context-defined pre-edit Findings-era baseline.
scope: "task_* family: task_audit + task_select descriptions"
created: 2026-08-11T18:58:50
updated: 2026-08-11T21:17:14
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Repair the task_audit and task_select descriptions and re-measure family trigger routing

## Goal

Two `task_*` sibling descriptions meet the standing repo rules they currently
miss. `task_audit` gains the `Use when` trigger clause the dual-audience
description rule requires, so a user browsing skills and an LLM router both get
what they need from it. `task_select` loses the single harness vendor name from
its description, so the text reads correctly on every harness the skill deploys
to. Trigger routing for the family comes out no worse than the Context-defined
pre-edit Findings-era baseline.

## Context

`task_audit` is the only skill the skill doctor's `discovery_safety.py` flags,
under the code `description_missing_triggers`. Its description opens "Audit one
implemented or finished task against the actual codebase. Use after implementation
or for drift checks before close out." It carries no `Use when` clause and no
user-phrase variants, which leaves its trigger surface thinner than every sibling's
while the standing repo rule asks a description to serve a browsing user and a
router deliberately.

`task_select`'s description names one harness vendor, in the clause "asks Codex to
pick or prioritize backlog work". The deploy dry-run confirms this skill also lands
in the Claude, Cursor, Antigravity, Copilot, and OpenCode configuration
directories, where naming a single vendor reads wrong.

[The sibling trigger-routing task](task-family_sibling-trigger-routing.md)
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

That same task fixes the measurement protocol these edits are judged against. The
surface is `tests/trigger_evals/task.json` run through
`tests/trigger_evals/run.py` with `--skill task --skill-path plugins/ai_dev/skills/task --runs-per-query 3`, a 50% per-query
threshold, and rates taken from that run's written `results.json` per-query
`results` rows rather than from the file's aggregate `summary` or from a single
invocation. The Findings-era subset is every row whose `expected_skill` is one of
`task_create`, `task_check`, `task_implement`, `task_audit`, `task_finish`,
`task_fix`, `task`, or `null` — the membership that produced the historical
Findings record of precise 15/25. Keep 15/25 as that historical record only; it
is not the active no-regression bar. The active bar is the Findings-era-subset
precise rate from a pre-edit run against the current catalog with today's
descriptions live (request deploy under the standing repo rule when they are
not already live), scored under this same protocol and denominator; score the
post-edit Findings-era subset at or above that pre-edit rate. Companion-reported
rows are every other `expected_skill` in the same run (`task_explain`,
`task_select`, and any later companion-owned skill including `task_auto_check`);
report their pass rate separately so a changed denominator never inflates the
headline. Soft companion: [the test-harness consolidation
task](../task-family_test-harness-consolidation.md) shares this eval set and owns
adding further cases (including `task_auto_check`) under that
separate-denominator reporting rule.

## Approach

Rewrite `task_audit`'s description in place so its existing purpose summary stays
the opening and a `Use when` clause follows it, carrying the phrasings a user
actually types for this skill — verifying a believed-done task, checking claimed
completion against the code, a drift check before close-out. Add trigger coverage
only; leave the description free of any clause that cedes a verb to a sibling or
hedges the skill's own territory, since that is the shape that regressed.

Rewrite `task_select`'s description in place so the vendor clause `asks Codex to
pick or prioritize backlog work` becomes `asks the agent to pick or prioritize
backlog work`, keeping the surrounding trigger phrases intact. This is a wording
substitution rather than a trigger change.

Before the description edits, establish the Context-defined pre-edit
Findings-era baseline under that measurement protocol (deploy today's
descriptions on explicit user ask when they are not already live). After the
edits, re-measure under the same protocol and denominator rule with the edited
descriptions live — again request deploy under the standing repo rule rather
than running it unprompted — and treat the recorded comparison against that
pre-edit baseline as the deliverable.

**Out of scope:** editing the base `task` skill's description, and adding any
verb-ceding or hedging clause to either description. Both are the reverted lever
[the sibling trigger-routing task](task-family_sibling-trigger-routing.md)
holds rejected. Defer growing or re-annotating the family trigger-eval set
(including adding `task_auto_check` cases) to [the test-harness consolidation
task](../task-family_test-harness-consolidation.md).

## Acceptance

- `python3 plugins/ai_dev/skills/skill_doctor/scripts/discovery_safety.py plugins/ai_dev/skills/task_audit plugins/ai_dev/skills/task_select`
  reports no `description_missing_triggers` warning for `task_audit`, where it
  reports one today, and adds no new warning for either skill.
- `task_audit`'s description is one canonical rewrite whose opening remains the
  existing purpose summary and whose following clause is a `Use when` trigger
  clause; the prior trigger-free description is superseded rather than left beside
  a second statement.
- That `Use when` clause includes the Approach-named user phrasings: verifying a
  believed-done task, checking claimed completion against the code, and a drift
  check before close-out.
- `task_select`'s description names no harness vendor: a case-insensitive search of
  that description for `codex`, `claude`, `cursor`, `antigravity`, `copilot`, and
  `opencode` returns nothing, where it matches today.
- The substituted clause is `asks the agent to pick or prioritize backlog work`
  (no harness vendor), preserving today's user-asks / agent-picks sense of that
  trigger.
- The surrounding trigger phrases from today's description remain present: asks
  what task to work on next; rank open tasks; choose from tasks/; recommend the
  next task/action without editing task files.
- Neither edited description contains a clause ceding an action verb to a sibling
  or hedging the skill's own territory.
- After the Context-defined pre-edit baseline exists, and after deploy-on-ask for
  the edited descriptions, run
  `python3 tests/trigger_evals/run.py --eval-set tests/trigger_evals/task.json --skill task --skill-path plugins/ai_dev/skills/task --runs-per-query 3`
  (50% per-query threshold). From that run's `results.json` per-query `results`
  rows, score the Context-defined Findings-era subset; its precise rate is at or
  above the Context-defined pre-edit Findings-era baseline, and the
  Context-defined companion-reported rows are reported separately; write the
  pre-edit baseline, the post-edit Findings-era rate, and the companion rate
  into this task body as a Findings note citing both run directories. The
  historical Findings record of 15/25 stays history only and is not this gate.
- A Findings-era-subset precise rate below the Context-defined pre-edit baseline
  reverts both description edits and records the measured drop in the same
  Findings note, leaving the descriptions as they stand today. The recorded
  measurement is the deliverable rather than its direction.

## Findings

Both runs used the Context-defined protocol: `tests/trigger_evals/task.json`
through `tests/trigger_evals/run.py` with `--skill task --skill-path
plugins/ai_dev/skills/task --runs-per-query 3`, a 50% per-query threshold, and
rates counted from each run's `results.json` per-query `results` rows rather
than its aggregate `summary`. Under that membership rule the eval set's 31 rows
split into a 25-row Findings-era subset and 6 companion-reported rows.

- Pre-edit baseline, `tests/trigger_evals/results/task/2026-08-11_204958/`, run
  after confirming the deployed descriptions were byte-identical to the repo
  copies: Findings-era precise **11/25**, family 18/25. Companion-reported
  precise 4/6, family 4/6. This 11/25 is the active no-regression bar, and the
  historical 15/25 record stays history.
- Post-edit, `tests/trigger_evals/results/task/2026-08-11_210206/`, run after
  the deploy put the edited descriptions live: Findings-era precise **14/25**,
  family 22/25. Companion-reported precise **4/6**, family 4/6, unchanged.
- Verdict: no regression. Findings-era precise rose by three and family by
  four, and no query lost a precise pass, so the revert branch stayed unused.

Three queries flipped from precise fail to precise pass and none flipped the
other way. Two are `task_audit` rows the new `Use when` clause targets. "audit
this task — is the work really implemented and backed by tests?" went from
loading no skill on any of three runs to `task_audit` on all three, and "is this
task actually done? verify it against the code" went from no skill to
`task_audit` on two of three. The Context records that second phrasing as a
known accepted limitation, so the clause reached a case this task did not chase.
The third flip is a `task_check` row whose pre-edit runs included one
`task_select` steal. Read it as within-run sampling variance rather than an
effect of these edits, since neither edited description names readiness.

The one `task_audit` row still failing is "re-check this archived task; did the
codebase drift away from what it describes?", which loads no skill on any run.
That matches the instrument-limited annotation already carried on that entry in
`task.json`: the model answers inline instead of loading a skill, so no
description wording reaches it.

The runs also surfaced a routing issue outside this task's scope. Both
`task_implement` rows "build the thing described in this task now" and "go do
task auth_session-rotation end to end" load `task_select` on all three runs, in
the pre-edit and post-edit runs alike. That is sibling bleed from `task_select`
into `task_implement` territory, unchanged by the vendor-word substitution and
untouched here because this task adds no verb-ceding or hedging clause.
