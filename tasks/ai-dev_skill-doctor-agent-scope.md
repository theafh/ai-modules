---
description: Settle whether skill_doctor can check agents, since its agents sentence promises a path for a named agent that the resolver provides no way to reach.
scope: plugins/ai_dev/skills/skill_doctor
created: 2026-08-10T23:20:58
updated: 2026-08-10T23:29:13
status: open
reported-by: Andreas Hoffmann
---

# Settle skill_doctor's handling of a named agent

## Goal

A user who names an agent in a `skill_doctor` request gets a coherent answer:
either the skill states plainly that agents are checked elsewhere, or it
resolves and checks the named agent. Today that request dead-ends on a
resolver error that reads as a typo.

## Context

`<scope_resolution>` in `plugins/ai_dev/skills/skill_doctor/SKILL.md` says
`Exclude agents unless the user names them.` and adds that agents live under
`plugins/*/agents/` and sit outside the default walk. The trailing clause
promises behaviour for the named case, and no mechanism delivers it.
`scripts/resolve_scope.py` builds its mode group from `--skill`, `--family`,
and `--all` only, and `discover_skills` globs `*/skills/*/SKILL.md`. Naming
an agent therefore fails as a missing skill: `--skill auto_shaper_task` exits
2 with `skill not found: auto_shaper_task`, and passing the agent's own path
exits 2 with `skill path not found:`, because the path branch accepts only a
`SKILL.md` file or a directory holding one.

Every other naming surface of the skill scopes it to skills. `<role>` calls
it a doctor for `the AI component artifacts of a plugin-shaped repository`
and then narrows to selected `SKILL.md` files; `<when_to_activate>` lists
only skill requests; the frontmatter `description:` offers
`one skill, a skill family, or every skill in the repo`. The shipping task
[ai-dev_skill-doctor-skill.md](archive/ai-dev_skill-doctor-skill.md) carried
the same sentence without ever giving it a mechanism, so the promise is an
authoring residue rather than a dropped feature.

Agent definitions do carry a checkable surface. Each file under
`plugins/*/agents/` opens with `name`, `description`, and `version`
frontmatter, the same triple `scripts/discovery_safety.py` inspects, so the
discovery-safety pass would largely transfer. Two mechanics differ: an agent
is one `.md` file rather than a directory holding `SKILL.md`, so the
directory-equals-`name:` check keys on the filename stem instead; and agent
frontmatter carries harness fields such as `model` and `effort` that no skill
check knows about.

Related: [ai-dev_skill-doctor-scope-failure-reporting.md](ai-dev_skill-doctor-scope-failure-reporting.md)
rewrites the same `<scope_resolution>` block and the same resolver, so the two
coordinate on one file and one script.

## Approach

Rewrite the `Exclude agents unless the user names them.` passage in place so
one canonical statement of the skill's agent handling remains, and make the
resolver agree with whatever that statement promises.

**Open decision:** whether `skill_doctor` gains an agent scope.

- **Narrow the sentence (the default an implementer takes without further
  input).** Rewrite the passage to state that this skill checks skills and
  that an agent request routes elsewhere, naming where an agent-definition
  review belongs. Every naming surface of the skill already scopes it to
  skills, so this settles the contradiction with the smallest change and
  leaves the resolver untouched. When a user names an agent, the skill says
  so and stops rather than emitting a missing-skill error.
- **Add an agent scope.** Give `resolve_scope.py` an `--agent` mode that
  resolves a name or a path under `plugins/*/agents/`, teach
  `discovery_safety.py` to key the identity check on the filename stem for an
  agent target, and extend `<workflow>` so the registration and
  instruction-quality passes state what they check on an agent host. This
  buys real coverage and costs a second target shape through every pass.

## Acceptance

- `rg "Exclude agents unless the user names them" plugins/ai_dev/skills/skill_doctor/SKILL.md`
  returns no match, and `<scope_resolution>` carries one statement of the
  skill's agent handling that the resolver satisfies.
- Naming an agent produces the behaviour that statement promises: under the
  narrowing, the skill reports agents as out of its scope and names where the
  review belongs, and emits no `skill not found:` for an agent that exists;
  under the agent scope, `--agent auto_shaper_task` and the same agent's path
  both resolve to that file and exit 0.
- Under the agent scope only, `scripts/discovery_safety.py` run on an agent
  definition reports its `name`, `description`, and `version` findings and
  keys the identity check on the filename stem, so a mismatch between the
  stem and frontmatter `name:` blocks.
- `tests/skill_doctor/script_tests/run.sh` gains a scenario for the settled
  behaviour on an agent target, and the suite passes with every scenario
  reported.
