---
title: Deciding where knowledge belongs
created: 2026-08-08
updated: 2026-08-08
type: procedure
tags: [authoring, skill, repo-structure]
sources: []
confidence: high
---

# Deciding where knowledge belongs

When you are about to write down something durable, send it to the skill body if
it changes what an agent does, to the skill's `references/` directory if an agent
needs it in another repository, and to this wiki if it is evidence, derivation, or
a decision record. The deciding question is whether the knowledge has to travel,
because the wiki is checked into this repository and reaches nowhere else.

## When this applies

You have just learned or decided something worth keeping: a verified fact about a
tool, a rule for how work should be done, the reasoning behind a choice, or a
finding that contradicts what an artefact currently says. You are about to open a
file to write it into.

It also applies in reverse, when a shipped artefact has grown past its job and you
are deciding what to move out of it.

## The rule

Sort the item by genre first, because the three genres have different homes and
different decay rates.

A rule changes what an agent does at the moment it acts. It is stable, it is
short, and it must fire without anyone going to look for it. Rules belong in the
skill body, where a trigger loads them.

A fact is perishable: a path, a key name, a version threshold, a vocabulary, a
flag. Facts belong wherever they are needed. If an agent needs one while working
in another repository, it ships with the artefact, in the skill's `references/`
directory, which loads on demand rather than on every trigger. If it is only ever
needed while working here, it belongs in the wiki with the date it was verified
and the source it came from.

A derivation is the evidence, the alternatives that were rejected, and the
reasoning that produced a rule. It belongs in the wiki always. A rule that
carries its own derivation charges every invocation for reasoning that only
matters once.

Two consequences follow, and they are the ones people get wrong.

The wiki does not travel, so anything an agent needs elsewhere cannot live only
here. State the conclusion in the artefact and keep the evidence in the wiki.

A skill body is not free. Its description is standing context and its body loads
in full whenever the trigger fires, so a fact parked in a skill body is paid for
by every unrelated invocation.

## Pitfalls

A rule and its evidence are easy to write as one paragraph. Split them, and let
the rule stand without the evidence, or it will not survive the move.

Duplicating a rule into both homes creates two versions that drift, and the drift
is discovered by whoever read only one. Where both places genuinely need it, one
of them states it and the other points at that one.

Process records are not knowledge. A page that exists to note that something ran,
or that a routine step completed, is noise the next reader has to filter.

## See Also

- [Splitting a shipped skill](splitting-a-shipped-skill.md) for the larger move
  this rule governs.
- [Skill family architecture](../concepts/skill-family-architecture.md) for why a
  skill body's size is a running cost.
