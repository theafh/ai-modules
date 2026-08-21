---
description: Make skill_doctor state that it checks skills only, so a named-agent request gets an out-of-scope answer instead of a missing-skill error.
scope: plugins/ai_dev/skills/skill_doctor
created: 2026-08-10T23:20:58
updated: 2026-08-21T17:14:27
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Keep skill_doctor skills-only when a user names an agent

## Goal

A user who names an agent in a `skill_doctor` request is told that this skill
checks skills only, and where agent-definition review belongs. The request no
longer dead-ends on a resolver error that reads as a typo.

## Context

`<scope_resolution>` in `plugins/ai_dev/skills/skill_doctor/SKILL.md` says
`Exclude agents unless the user names them.` and adds that agents live under
`plugins/*/agents/` and sit outside the default walk. The trailing clause
promises behaviour for the named case, and no mechanism delivers it.
`scripts/resolve_scope.py` builds its mode group from `--skill`, `--family`,
and `--all` only, and `discover_skills` walks the repository tree for
case-insensitive `skill.md` filenames (pruning VCS/dependency/cache dirs,
then dropping gitignored paths). Naming an agent therefore fails as a
missing skill: `--skill auto_shaper_task` exits 2 with
`skill not found: auto_shaper_task`, and passing the agent's own path exits
2 with `skill path not found:`, because the path branch accepts only a
`SKILL.md` file or a directory holding one.

Every other naming surface of the skill already scopes it to skills. `<role>`
calls it a doctor for skill artifacts; `<when_to_activate>` lists only skill
requests; the frontmatter `description:` offers
`one skill, a skill family, or every skill in the repo`. The shipping task
[ai-dev_skill-doctor-skill.md](ai-dev_skill-doctor-skill.md) carried
the same sentence without ever giving it a mechanism, so the promise is an
authoring residue rather than a dropped feature.

**Settled decision:** agents stay out of `skill_doctor`. The skill name and
every other naming surface already make that the product boundary; this task
removes the contradictory named-agent promise rather than adding an agent
scope.

Agent-definition review already has a home for the portable runtime surface:
`harness_portability` covers agent and subagent definitions and agent
frontmatter. Route a named-agent `skill_doctor` request there (and to
`ai_instruction_writing` / `ai_instruction_formatting` when the ask is prose
authoring).

Related: [ai-dev_skill-doctor-scope-failure-reporting.md](ai-dev_skill-doctor-scope-failure-reporting.md)
rewrote the same `<scope_resolution>` block and the same resolver; coordinate
wording so the skills-only agent statement and the failure remedies stay one
coherent block.

## Approach

Rewrite the `Exclude agents unless the user names them.` passage in
`<scope_resolution>` in place so one canonical statement remains: this skill
checks skills only; agents under `plugins/*/agents/` stay outside every
scope mode; before invoking `resolve_scope` for a name or path selector,
when that selector identifies a definition under `plugins/*/agents/`, the
skill reports that boundary, routes to `harness_portability` (and the
instruction-writing siblings when the ask is prose), and stops.

Leave `scripts/resolve_scope.py` and `scripts/discovery_safety.py` on their
skill-only shapes. The skill-level stop for a named agent is what prevents the
missing-skill misread; the resolver need not gain an `--agent` mode.

Rewrite `scope_resolution_keeps_the_agent_statement` in
`tests/skill_doctor/script_tests/run.sh` in place so it asserts the new
skills-only agent statement inside `<scope_resolution>` rather than
`Exclude agents unless the user names them.`

**Out of scope:**

- Adding an `--agent` resolver mode, agent target shape, or discovery-safety
  pass over `plugins/*/agents/` files.
- Building a dedicated agent-doctor skill; routing uses the existing
  `harness_portability` and instruction-writing surfaces named in Context.

## Acceptance

- `rg "Exclude agents unless the user names them" plugins/ai_dev/skills/skill_doctor/SKILL.md`
  returns no match, and `<scope_resolution>` carries one skills-only statement
  of agent handling that matches Approach.
- Naming an agent produces that statement's behaviour: the skill reports
  agents as out of its scope, names `harness_portability` (and the
  instruction-writing siblings when relevant), and emits no
  `skill not found:` for an agent that exists under `plugins/*/agents/`.
- Rewrite `scope_resolution_keeps_the_agent_statement` in
  `tests/skill_doctor/script_tests/run.sh` so it asserts the skills-only
  agent statement the `rg "Exclude agents unless the user names them"`
  Acceptance check requires inside `<scope_resolution>`, not
  `Exclude agents unless the user names them.`; then
  `tests/skill_doctor/script_tests/run.sh` exits 0 and reports every
  scenario. When the skill's check path is script-testable for a named-agent
  target, the suite also gains a scenario for that settled out-of-scope
  behaviour; otherwise the `Naming an agent produces` Acceptance check is
  proven by reading the rewritten `<scope_resolution>` block plus a
  walkthrough of the named-agent path.
- Approach's leave-scripts statement holds: the mode group in
  `scripts/resolve_scope.py` remains `--skill` / `--family` / `--all` only,
  and neither that script nor `scripts/discovery_safety.py` gains an agent
  target shape.
