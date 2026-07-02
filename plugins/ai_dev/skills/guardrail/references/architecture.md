# ARCHITECTURE.md — general template and rules

The tier-2 descriptive guardrail: an actively maintained account of how the project is structured and where that structure is deliberately headed — its goals, stack, components, the design decisions that shape them, and the architectural direction the humans have set. It sits at the descriptive end of the enforcement spectrum: it informs work and never blocks it, and its guard value is truthfulness — an agent that reads a truthful architecture doc extends the intended design instead of inventing a competing one, while a doc that no longer matches the project, or passes intention off as fact, misleads every future session. It is the project's structure and direction explained once, so each agent session can stop re-deriving them.

## Base template

```markdown
# Architecture

## System Overview

<One or two paragraphs: what the system is, the core idea behind its shape,
and the goals the structure serves.>

## Components

<Per component or major area: its responsibility, its boundaries, and how it
interacts with its neighbours. Match the repo's real units — modules,
services, plugins, content areas.>

## Technology Choices

<Each load-bearing choice of language, framework, storage, or tooling, with
the rationale that makes it durable.>

## Design Decisions

<The decisions that shape the structure: what was decided, why, and the
tradeoff accepted. The rationale is the payload — it is what keeps a future
change from silently reversing a deliberate call.>

## Direction

<Optional: the architectural direction deliberately chosen — a target shape,
a planned component, a migration underway — labeled as direction so a reader
tells built from intended.>

## Out of Scope

<Optional: structural directions deliberately not taken, so they read as
decisions rather than gaps.>
```

## General rules

- **Present and direction, told apart.** The doc describes the structure as it stands *and* the architectural direction the project is deliberately taking — a target shape, a planned component, a migration underway — with built and intended clearly told apart. A guardrail bounds evolution; it never freezes the project: work that develops the architecture along the declared direction is the system working as designed. What misleads is a description that no longer matches the project, or an intention presented as fact.
- **Durable direction here, steps in the work system.** The doc carries the architectural direction worth standing on; the fine-grained path — stages, tasks, ordering, status — lives in the work system. The doc is a description, never an index: no stage plan, spec index, status board, or build-order view. (Its predecessor in the spec framework doubled as a spec index — the guardrail role sheds that half and keeps the architecture.)
- **Rationale over inventory.** A bare component list restates what the file tree already shows. The durable value is the why: responsibilities, boundaries, interactions, and the reasoning behind the shape.
- **Refreshed as the project evolves.** Work that extends or reshapes the design updates the doc as part of closing out — landed direction moves from intended to built, and superseded description is rewritten rather than left behind. That refresh is what keeps the descriptive tier trustworthy.
- **Subordinate narrative.** The doc explains; it never overrides the charter's falsifiable boundaries, and a conflict between the two resolves in the charter's favor and is surfaced.

## Tailoring

The template's "components" flex to the repo's nature. A software system describes runtime components, data flow, and technology choices. A knowledge repository describes its corpus organization — page types, taxonomy, linking rules, source-of-truth structure. A meta-repository describes its artefact layout, packaging model, and deployment surfaces. A mixed multi-project layout carries one architecture doc per sub-project rather than a root doc spanning unrelated systems.

## Consumption

Consumers read the doc for design context and declared direction before shaping new work — for example, task creation reads it (with `FEATURES.md` when present) ahead of a codebase scan — and refresh it at close-out when the finished work extended the design. When absent, consumers continue unchanged.
