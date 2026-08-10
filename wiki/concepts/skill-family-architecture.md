---
title: Skill family architecture
created: 2026-08-08
updated: 2026-08-10
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
the extreme case before its split: a body of accumulated per-harness facts was
loaded whole to answer a question about quoting a shell variable. Splitting
facts out to this wiki and to a `references/` directory is the standing remedy,
since a `references/` file ships with the plugin and loads only when the skill
sends the agent to it.

### The rules acquired a checker, and it reads them rather than restating them

The conventions above have a mechanical auditor, `skill_doctor`, which checks a
single skill, a family, or every skill in the tree and edits nothing. It covers the surfaces this page describes: directory name
against frontmatter `name:` against the H1 heading, the dual-audience
`description`, sibling activation boundaries inside a selected family, and the
registration and version lockstep from
[plugin packaging and versioning](plugin-packaging-and-versioning.md). It also
checks that the applicable verification surface exists for each selected skill,
which is a different question from whether that surface passes; both are on
[verification surfaces for a shipped skill](verification-surfaces.md).

Two design choices in it matter beyond the skill itself. The first is that it
cites the authoring rules instead of carrying copies of them, reading
`ai_instruction_formatting` and `ai_instruction_writing` at check time and
pointing at the standing repository rule for descriptions. That is the
rules-live-once principle applied across skills rather than within a family, and
it is what keeps the auditor from becoming a second, drifting statement of the
house style.

The second is where it draws the line between blocking and warning. A finding
blocks only when it states a mechanical fact about the file: frontmatter that is
absent or unparseable, a missing `name`, `description`, or `version`, a name that
disagrees with its directory, a parser-hostile character, or a purpose summary
byte-identical to a sibling's. Every judgement about description *quality* warns
instead, because no heuristic separates a description that carries no trigger
coverage from one that phrases its triggers differently, and a false block on a
healthy shipped skill costs the reader more than a warning they dismiss. Severity
governs what a run gates on, never what it inspects, so every dimension is still
reported.

### Authoring and checking constrain each other

The two sides are coupled in both directions, which is easy to miss when reading
either skill alone. The checker cites the authoring rule for remediation, and one
authoring rule exists because of a checker constraint: inside an unquoted YAML
scalar such as a frontmatter `description:`, a sentence that needs restructuring
is split in two rather than joined with a colon, because a mid-value colon is the
parser footgun the discovery check flags. Both sides also hold the same position
on typographic characters, treating an em dash or a curly quote as a question
about what the consuming parser reads rather than as a prose defect, so the
character stays as written once UTF-8 is confirmed.

## Open questions

There is no measured threshold for when a skill body is too large. The
portability case was obvious on sight, but the boundary between a skill that
carries its rules and one that has quietly become a reference manual has so far
been judged by reading rather than by any rule. The auditor did not close this.
What it measures is description length, and only relative to the siblings in the
selected set, so it catches a description that is unlike its neighbours and says
nothing about a body that has outgrown its purpose. The size question is
therefore still answered by reading.

## Related concepts

- [Plugin packaging and versioning](plugin-packaging-and-versioning.md).
- [The ai-modules repository](../summaries/ai-modules-repository.md).

## Derived from

- `CLAUDE.md` and `AGENTS.md` at this repository root, authoring conventions.
- The `task_*` and `wiki_*` skill sources under `plugins/`.
- The `skill_doctor` skill and its bundled discovery-safety script, for the
  severity split and the description checks.
