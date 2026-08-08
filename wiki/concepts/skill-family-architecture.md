---
title: Skill family architecture
created: 2026-08-08
updated: 2026-08-08
type: concept
tags: [skill, agent, authoring, repo-structure]
sources: []
confidence: high
---

# Skill family architecture

## Definition

A skill family is a group of skills that share one capability and one authority.
The `task_*` family and the `wiki_*` family are the two worked examples here.
Each has a base skill that owns the format, the lifecycle, and the rules, and a
set of front-end siblings that each cover one step and inherit the base rules
through an authority reference rather than restating them.

The shape solves a context problem. A one-shot request to create a task should
load a narrow surface, not the whole backlog workflow, so `task_create` exists
as a thin front end over `task`. The rule about what a well-formed task looks
like still lives in exactly one place.

## Current state of knowledge

### Naming by invocation mode and collision risk

Three naming patterns are in use, and the choice between them is decided by who
invokes the artefact and whether a sibling would collide.

A skill that is the only entry point for its capability keeps the ordinary
family-first name, even when it delegates the work to an agent. `wiki_fix` is
that case: it hands off to `auto_shaper_wiki` and still reads as a plain member
of the family.

A skill that automates a capability which also has a classical manual sibling
takes the `<family>_auto_<rest>` form, so `task_auto_check` sits beside
`task_check` without either name implying the other does not exist.

An agent that only ever gets spawned leads with `auto_` and ends with the family
token, giving `auto_shaper_wiki` and `auto_implementer_task`. The name is a
signal to the router and to a human reader that no user invokes this directly.

### Rules live once, in the base skill

A rule that governs a whole family is written once in that family's base skill.
The siblings inherit it. Enforcement is paired with the canonical rule rather
than restated beside it, so a maintenance sibling such as `task_fix` carries a
pointer back to the base rule instead of a second copy of it.

This is the same principle the wiki applies to itself, and the same one that
motivated splitting the portability skill: two copies of a rule drift, and the
drift is discovered by an agent that read only one of them.

### Skills bundle their own scripts

A script that supports a skill lives at
`plugins/<plugin>/skills/<skill>/scripts/<name>` and is referenced from the
`SKILL.md` by a skill-relative path. The reason is distribution, covered in
[plugin packaging and versioning](plugin-packaging-and-versioning.md): the
plugin is what travels, so a helper at the repository root reaches nobody.

Bundled scripts do more than tidy the layout. They hand mechanical work to a
program that cannot hallucinate, which is why wiki discovery, initialisation,
linting, and source hashing are all scripts rather than prose instructions.

### The description is a routing surface, and it is not free

A skill's `description` frontmatter is read before the body loads, by an LLM
router and by a human browsing a list. It has to serve both, which in practice
means a precise compact summary followed by keyword-rich trigger contexts.

The cost side is easy to miss. Descriptions are standing context in every
session that lists skills, and a skill body is loaded in full the moment its
trigger fires. A long description over-triggers, and a large body charges every
trigger for content the current task does not need. The portability skill was
the extreme case: at roughly 94 KB it charged about 32,000 tokens to answer a
question about quoting a shell variable. Splitting facts out to this wiki and to
a `references/` directory is the standing remedy, since a `references/` file
ships with the plugin and loads only when the skill sends the agent to it.

## Open questions

There is no measured threshold for when a skill body is too large. The 94 KB
case was obvious, but the boundary between a skill that carries its rules and
one that has quietly become a reference manual has so far been judged by
reading rather than by any rule.

## Related concepts

- [Plugin packaging and versioning](plugin-packaging-and-versioning.md).
- [The ai-modules repository](../summaries/ai-modules-repository.md).

## Derived from

- `CLAUDE.md` and `AGENTS.md` at this repository root, authoring conventions.
- The `task_*` and `wiki_*` skill sources under `plugins/`.
