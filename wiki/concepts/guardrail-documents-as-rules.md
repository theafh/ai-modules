---
title: Guardrail documents as normative rules
created: 2026-08-09
updated: 2026-08-09
type: concept
tags: [skill, authoring, repo-structure]
sources: []
confidence: high
---

# Guardrail documents as normative rules

## Definition

A guardrail document is a standing, human-owned markdown file at a repository
root carrying one domain of durable project truth: `CHARTER.md` for identity,
and `ARCHITECTURE.md`, `TESTING.md`, and `SECURITY.md` for design and
verification. It is the channel through which the skills and agents this
repository ships consume repository-specific guidance while they work.

The statements in one are normative. A guarding statement says what must be true
of the project, not what happens to be true of the tree today. That distinction
is where the whole value sits, and it is the thing an AI coding agent gets wrong
most reliably.

## Current state of knowledge

### Consumption is a lookup performed by the consuming skill

A skill or agent that reaches a stage where one of these docs would inform it
goes looking for the file, reads it on a hit, applies what it says, and carries
on unchanged on a miss. Nothing hands the doc to the skill. The filename is the
interface, so there is no registry, no manifest, and no wiring step, and a
repository that carries none of these files behaves exactly as it did before.

This is worth stating plainly because the neighbouring mechanism works
differently and the two are easy to conflate. A harness rule file such as
`CLAUDE.md` or `AGENTS.md` is loaded by the harness, and even that is not a
uniform guarantee across products: Cursor selects among four activation modes
per rules file, so an `.mdc` rule can be conditional on a glob, on a
description match, or on being mentioned by hand, as recorded on
[Cursor](../entities/cursor.md). Describing guardrail docs as arriving
automatically imports a promise the mechanism never made.

### Adoption is optional, and the content is the repository's own

A user of these plugins is under no obligation to adopt any guardrail document,
and under no obligation to accept any particular rule once one exists. The
skills supply the mechanism and never the content: each doc carries the
direction its own repository has chosen, and a project that prefers to guard its
work another way loses nothing by carrying none of these files. Absence is a
supported state rather than a gap to be filled.

### The misreading: a doc read as a description

An agent that treats a guardrail doc as an account of the current tree will
soften a rule the moment the code disagrees with it, which inverts what the doc
exists to do. Code that falls short of a rule is unmet work, not evidence that
the rule is wrong. A rule that only ever states what is already true guards
nothing, so a doc restricted to describing the present has no guarding half at
all.

### How a rule becomes true

Three paths carry a rule from stated to satisfied: work filed and done to close
the gap deliberately, new code written to the rule from the start, and existing
code brought up to the rule whenever ordinary work touches or rewrites it. The
third carries most of the distance, and it is the reason a rule needs no
migration plan attached to be worth stating. It is also an obligation on the
agent rather than a check that fires, which is the honest limit of the model.

### A rule carries nothing perishable

A guarding statement holds no link to a task or backlog item, no line number or
other code position, and no clause marking the rule as not yet met. Each of
those is wrong the second the code changes, while the rule itself is not. This
is the reasoning that retired a planned-marker convention considered for this
family: a marker naming what is unfinished today is exactly the content that
goes stale, and the rule reads correctly without it. Where a rule needs to point
into the repository, it names its target by a stable, greppable name.

### Guarding and describing carry different obligations

The two halves of a doc answer to different standards, and collapsing them
produces the misreading above. A guarding statement is falsifiable in that a
reviewer can check one concrete change against it, not in that the whole tree
satisfies it. A describing statement stays true to the repository, and it is
there that intention presented as fact does its damage, which is why an account
of a system's shape may still label an intended component or a migration
underway as direction while a rule never carries a not-yet-met qualifier.

### Where a rule belongs among the docs

A rule discovered while working on one surface tends to get written into that
surface's doc, which leaves every other surface it governs unguided. The general
form belongs in the doc that owns the general domain, and the narrower doc
carries what the rule means for its own surface. The pattern has a failure mode
worth recognising: where a repository carries no harness rule file, or its
operating rules sit in a rules file only one product loads, general operating
rules migrate up into the domain docs for want of anywhere else to live.

## Open questions

Whether the touch-it-and-fix-it path actually closes gaps in practice is
unmeasured. It is an obligation on the agent with nothing structural behind it,
and the alternative reading — that agents quietly skip it and gaps persist
until someone files the work — has not been ruled out.

Telling a guarding statement from a describing one is judgement rather than a
mechanical test. A sentence that does both at once has no clean verdict, and
nothing yet says how an audit should rank one.

## Related concepts

- [Deciding where knowledge belongs](../procedures/deciding-where-knowledge-belongs.md)
  for why the rules live in the skill while this reasoning lives here.
- [Skill family architecture](../concepts/skill-family-architecture.md) for the
  same one-canonical-statement principle applied to a skill family.
- [The ai-modules repository](../summaries/ai-modules-repository.md) for how this
  document set sits beside the wiki.

## Derived from

- The `guardrail` and `guardrail_audit` skill sources under `plugins/ai_dev/skills/`.
- A working session in August 2026 that applied the doc set to a Rust project and
  produced the rules this page explains. Local chat session on the author's
  workstation; the reasoning is captured above rather than by reference.
