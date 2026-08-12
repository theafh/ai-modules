---
description: Give the base task skill an output_contract, widen not_in_scope for sibling preference, and a Pattern A hub-<update> eval proving the contract.
scope: plugins/ai_dev/skills/task
created: 2026-08-11T18:58:50
updated: 2026-08-12T09:11:28
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Complete the base task skill's contract surfaces

## Goal

The base `task` skill states what a run reports back and when a focused sibling
serves a request better than the hub does. An agent that has loaded the hub then
hands off deliberately instead of absorbing work a sibling owns, and closes every
workflow in one predictable reporting shape. Two sections of
`plugins/ai_dev/skills/task/SKILL.md` change: a new `<output_contract>`, and a
widened `<not_in_scope>` that carries the sibling-preference boundary beside the
wiki boundary it already states.

## Context

Every `task_*` sibling skill under `plugins/ai_dev/skills/` carries an
`<output_contract>` section. The hub carries none. Its sections run from `<role>`
through `<family>` with no statement of what a run returns, so each hub workflow
(`<create>`, `<query>`, `<update>`, `<archive>`, `<lint>`) ends without a shared
reporting shape while its front ends all define one.

The sibling contracts each define their own report shape rather than sharing one
template — `task_create` reports "the relative path of the one task file created",
`task_fix` closes on `audit complete — N issues resolved, K flagged for review`,
and `task_select` opens its report with `# Recommendation` and states it makes no
edits. Approach derives the hub's shared reporting envelope from the hub workflows'
shared reporting needs, not from a universal sibling template.

The hub's `<not_in_scope>` states one boundary only, led by "The wiki skill
captures durable knowledge". Nothing in the body says when a request naming a
single task is better served by a focused sibling than by the hub. The `<family>`
section already lists every sibling with a one-line role, so the new boundary
points at that list rather than repeating it.

The boundary is a routing preference rather than a capability denial: `<family>`
opens by stating the hub "can do all of the backlog work itself", and that stays
true. The shipped `<when_to_activate>` already invites create, list, update,
finish, defer, and lint asks that are often single-task; Approach states how the
widened `<not_in_scope>` coexists with that capability entry list.

The router reads only `description:` frontmatter and never the body, a limit
measured by [the sibling trigger-routing task](task-family_sibling-trigger-routing.md).
A body-level boundary therefore changes how an already-loaded agent hands off and
leaves trigger routing untouched.

The Pattern A hub behavioural suite at `tests/tasks/evals/` inventories every
scenario id in the table under `## The eval set (every \`id\` in \`evals.json`)`
in `tests/tasks/evals/README.md`; the hub peers already listed there are `query`,
`update`, and `triage`.

## Approach

Write `<output_contract>` as one section covering every hub workflow rather than a
per-workflow contract, since the workflows already differ in their steps and share
their reporting needs: the files touched with relative paths (none when unused); the
status or lifecycle move made where one applies; the linter outcome (not-run when
unused); and the assumptions and judgement calls the user should correct (always).
Place the section where the siblings place theirs so a reader moving between family
files finds it in the same position.

Widen `<not_in_scope>` in place so it holds both boundaries as one statement of
what the hub defers: keep the existing wiki sentence as the single canonical
statement of that boundary, and add the sibling-preference boundary next to it,
pointing at `<family>` for the per-sibling roles. State the preference positively —
a request naming one task and one lifecycle step is served by the sibling that owns
that step, while broad or multi-task backlog work stays with the hub.

Keep `<when_to_activate>` as the capability entry list: it continues to invite the
hub for create, list, update, finish, defer, lint, and related backlog asks. Only
the widened `<not_in_scope>` carries the sibling-preference for an agent that has
already loaded the hub. Leave `<when_to_activate>` unedited.

Add one Pattern A hub-`<update>` behavioural eval in `tests/tasks/evals/` that
asserts a hub run closes in the shape the new `<output_contract>` defines,
extending the existing `update` eval pattern beside the `query` / `update` /
`triage` hub peers rather than replacing the existing `update` eval's purpose.
Wire it as a full runnable suite entry: fixture `setup.sh`, a matching
`stage.sh` case, `grade.sh` programmatic checks plus `note_agent_attest` notes,
the matching `evals.json` entry, and an in-place rewrite of that inventory table
so the new scenario id appears beside `query` / `update` / `triage`. Prove the
four shared reporting needs Approach already enumerates through response and
filesystem observables: the relative path of the file touched and that edit on
disk; status stays `open` with no archive move; the reported linter outcome with
a clean backlog lint; and assumptions or judgement calls for the user, or an
explicit none. That eval set's directory
[the test-harness consolidation task](../task-family_test-harness-consolidation.md)
relocates.

**Out of scope:** editing the hub's `description:` frontmatter to cede sibling
verbs or add a counter-boundary. [The sibling trigger-routing task](task-family_sibling-trigger-routing.md)
measured that lever, recorded a regression from precise 14/25 to 12/25 and family
20/25 to 14/25, reverted it, and holds the approach rejected; it also records the
hub firing for a bare action verb as a known accepted limitation. Rewriting
`<when_to_activate>` so single-task lifecycle asks prefer a sibling.

## Acceptance

- `rg '<output_contract>' plugins/ai_dev/skills/task/SKILL.md` returns a hit,
  where it returns nothing today.
- In `plugins/ai_dev/skills/task/SKILL.md`, `</output_contract>` is followed by
  `<family>` as the next top-level pseudo-XML section tag (no other section tag
  between them), matching sibling relative position.
- The new `<output_contract>` names the shared reporting needs Approach already
  enumerates for every hub workflow (files touched with relative paths — none when
  unused; status or lifecycle move where one applies; linter outcome — not-run when
  unused; assumptions and judgement calls for the user — always).
- `python3 plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py plugins/ai_dev/skills/task/SKILL.md`
  reports PASS with the new tag closed and snake_case.
- The hub's `<not_in_scope>` states the sibling-preference boundary with both
  sides of the positive preference Approach already names (one task and one
  lifecycle step → owning sibling; broad or multi-task backlog work → hub), and
  the sentence led by "The wiki skill captures durable knowledge" remains the
  single statement of the wiki boundary rather than being duplicated elsewhere in
  the body.
- The sibling boundary refers to `<family>` for the per-sibling roles, so one
  canonical sibling list remains in the file.
- Hub `<when_to_activate>` still invites create, list, update, finish, defer, and
  lint asks, and sibling-preference appears only in the widened `<not_in_scope>`.
- `tests/tasks/evals/` gains the Approach-named Pattern A hub-`<update>`
  scenario (fixture `setup.sh`, `stage.sh` case, `grade.sh`
  checks/`note_agent_attest`, `evals.json` entry) whose response and filesystem
  observables prove the four shared reporting needs Approach enumerates for
  `<output_contract>`. Run it with
  `python3 tests/tasks/evals/run.py <scenario_id>` (or the suite's
  stage → agent → `grade.sh` path); the recorded pass/fail against the
  suite's fixed denominator is the deliverable. When the scenario fails, revise
  the contract or scenario once and re-run, or record the failure as a known
  limit with evidence — do not gate done on an unmeasured hoped-for pass.
- The new scenario id appears in the inventory table under `## The eval set (every
  \`id\` in \`evals.json`)` in `tests/tasks/evals/README.md` beside the existing
  hub peers `query`, `update`, and `triage`.

## Findings

The scenario shipped as `update_contract` and passed on its first measured run:
13 of 13 programmatic `grade.sh` checks, worker rc 0, sonnet-pinned, run directory
`tests/tasks/evals/workspace/run-20260812-083350/`. No revision of the contract or
the scenario was needed, so the one-revision fail branch the Acceptance names went
unused. The captured `response.txt` carries all four reported parts under their own
bold lead-ins, in the contract's order and with nothing else between them: the file
touched as `tasks/auth_token-rotation.md`, `Status move: none — status stays open`,
a clean linter outcome naming the invocation, and three judgement calls surfaced
for the user. Before the measured run, the grader was confirmed bidirectional
against the same fixture: 5 of the 13 checks fail on an unrun sandbox and all 13
pass on a completed one, so the scenario cannot pass on a no-op.

The hub-peer regression set re-ran live in the same run against the edited hub
skill, with no cached verdicts: `query`, `update`, `triage`, and `lossless_split`
each passed, for 5 of 5 evals overall.
