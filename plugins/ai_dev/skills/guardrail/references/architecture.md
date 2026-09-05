# ARCHITECTURE.md: general template and rules

The tier-2 architecture guardrail: an actively maintained account of how the project is structured and where that structure is deliberately headed: its goals, stack, components, the design decisions that shape them, and the architectural direction the humans have set. It informs work and never blocks it, and its content sits in three enforcement registers. A guarding rule states what must hold of the structure, and code short of it is unmet work. A present-tense description says what stands as it stands, and truthfulness is its guard value. An agent that reads a truthful account extends the intended design instead of inventing a competing one, while a passage that no longer matches the project, or passes intention off as fact, misleads every future session. A declared direction, carried by the `## Direction` section, names the target shape the project is steered toward, and it holds as a standing commitment whether or not the code has reached it: code short of the target is unmet work the next change drives toward, never a falsehood to soften away. It is the project's structure and direction explained once, so each agent session can stop re-deriving them.

## Base template

```markdown
# Architecture

## System Overview

<One or two paragraphs: what the system is, the core idea behind its shape,
and the goals the structure serves.>

## Components

<Per component or major area: its responsibility, its boundaries, and how it
interacts with its neighbours. Match the repo's real units, such as modules,
services, plugins, and content areas.>

## Technology Choices

<Each load-bearing choice of language, framework, storage, or tooling, with
the rationale that makes it durable.>

## Design Decisions

<The decisions that shape the structure: what was decided, why, and the
tradeoff accepted. The rationale is the payload, because it is what keeps a
future change from silently reversing a deliberate call.>

## Direction

<Optional: the architectural direction deliberately chosen, such as a target
shape, a planned component, or a migration underway, stated as the target the
project is steered toward. The section carries the target, never its completion
state: a reader tells built from intended by which section a statement sits
in, so no item here is marked shipped, landed, or remaining.>

## Out of Scope

<Optional: structural directions deliberately not taken, so they read as
decisions rather than gaps.>
```

## General rules

- **Present and direction, told apart.** This rule binds the doc's present-tense description and its declared direction alike. The doc describes the structure as it stands *and* the architectural direction the project is deliberately taking: a target shape, a planned component, a migration underway. Built and intended are told apart at the section boundary: the descriptive sections carry what stands, and the optional `## Direction` section carries the target the project is steered toward, stated as a standing commitment rather than as a report on how much of it exists. Per-item build-status narration inside `## Direction` is the drift this rule prevents: "the write side shipped", "landed", "what remains is", "two thirds done". A target annotated with its own completion state is a progress ledger, and build progress belongs to the work system. A guardrail bounds evolution; it never freezes the project: work that develops the architecture along the declared direction is the system working as designed. What misleads is a present-tense description that no longer matches the project, or an intention presented as fact. No rule carries a not-yet-met marker, and no target carries one either.
- **Durable direction here, steps in the work system.** The doc carries the architectural direction worth standing on; the fine-grained path of stages, tasks, ordering, and status lives in the work system. The doc is a description, never an index: no stage plan, spec index, status board, or build-order view. (Its predecessor in the spec framework doubled as a spec index; the guardrail role sheds that half and keeps the architecture.)
- **Rationale over inventory.** A bare component list restates what the file tree already shows. The durable value is the why: responsibilities, boundaries, interactions, and the reasoning behind the shape.
- **Refreshed as the project evolves.** This rule binds the doc's present-tense description and its declared direction alike. Work that extends or reshapes the design updates the doc as part of closing out: superseded description is rewritten rather than left behind, and a direction the project has reached is absorbed into `## Components` or `## Design Decisions` as what now stands. The `## Direction` statement itself is refreshed when the target changes, whether a new target, a target dropped, or a target reshaped, and never when one piece of the standing target ships. Refresh tracks design change, not build progress. That refresh is what keeps the doc trustworthy. No rule carries a not-yet-met marker.
- **Subordinate narrative.** The doc explains; it never overrides the charter's falsifiable boundaries, and a conflict between the two resolves in the charter's favor and is surfaced.

## Tailoring

The template's "components" flex to the repo's nature. A software system describes runtime components, data flow, and technology choices. A knowledge repository describes its corpus organization: page types, taxonomy, linking rules, source-of-truth structure. A meta-repository describes its artefact layout, packaging model, and deployment surfaces. A mixed multi-project layout carries one architecture doc per sub-project rather than a root doc spanning unrelated systems.

## Consumption

Consumers read the doc for design context and declared direction before shaping new work, and refresh it at close-out when the finished work extended the design. For example, task creation reads it (with `FEATURES.md` when present) ahead of a codebase scan. When absent, consumers continue unchanged.
