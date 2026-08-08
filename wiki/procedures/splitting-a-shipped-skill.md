---
title: Splitting a shipped skill
created: 2026-08-08
updated: 2026-08-08
type: procedure
tags: [authoring, skill, portability]
sources: []
confidence: high
---

# Splitting a shipped skill

When a skill body has grown into a reference manual, move the reference material
out and keep the rules, then audit the split in three directions before calling
it done, and repair every artefact that pointed into the part you removed.

## When this applies

A skill body has grown large enough that its cost is paid on every trigger, or it
has accumulated dated facts that decay while the rules around them stay stable.
The signal is a body a reader would consult rather than obey.

## The rule

Classify every block by genre before moving anything, using
[deciding where knowledge belongs](deciding-where-knowledge-belongs.md). Convert
a rule that was embedded inside a reference block into an explicit rule in the
policy section rather than letting it leave with the facts around it. This is
where most loss happens: guidance stated as an aside inside a fact block reads as
part of the fact and travels out with it.

Then audit in three directions, because each catches a different failure.

Check that nothing was dropped from both homes. Walk the original block by block
and confirm each one has a destination. A block that reads as background is the
one most likely to have carried a rule nobody noticed.

Check that nothing was removed without being relocated. A fact deleted from the
artefact and never written anywhere is gone, and it will be re-derived at the
cost that motivated recording it in the first place.

Check that nothing stayed that should have moved. Read the reduced artefact for
anything perishable: a path, a version, a key name, a tool vocabulary. Their
presence means the split stopped halfway.

Finally, repair the inbound references. Anything that cited a region of the
artefact by name now points at nothing. Each of those references must carry the
information it needs inline rather than depending on the link, so that following
the link is optional. Where a reference told a future reader to record a finding
in the removed region, redirect it to wherever that knowledge now lives.

## Pitfalls

Deleting a whole block because most of it was reference material takes the rules
with it. Read for the imperative sentences before removing anything.

A trigger description shrinks with the body, and it should, but the terms that
make the artefact fire have to survive the cut or the rules stop reaching the
work.

A split changes an artefact's structure rather than fixing a detail, so the
version increment should say so.

## See Also

- [Deciding where knowledge belongs](deciding-where-knowledge-belongs.md) for the
  genre classification this depends on.
- [Skill family architecture](../concepts/skill-family-architecture.md) for the
  cost model that makes the split worth doing.
