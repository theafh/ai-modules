---
title: System prompt substitution experiments
created: 2026-08-08
updated: 2026-08-09
type: summary
tags: [experiment, system-prompt, authoring, codex, opencode, claude]
sources: []
confidence: medium
---

# System prompt substitution experiments

## Topic and scope

This page holds an idea that has not been run yet: take a harness's whole system
prompt, rewrite it under this repository's own AI writing and formatting skills,
install it in the slot that accepts a whole prompt, and see how the agent then
behaves.

The two authoring skills, `ai_instruction_writing` and
`ai_instruction_formatting`, encode claims about how instructions should be
written: positive action-oriented language as the primary carrier of every
instruction, and pseudo-XML sectioning so a model can find the right passage by
structure rather than by re-reading prose. Both have so far been applied to
artefacts authored here and judged by reading them back. Neither has been tested
on prose written by someone else, at the scale of a whole system prompt, with the
resulting behaviour observed.

The synthesizable tier described in
[system prompt substitution across harnesses](../comparisons/system-prompt-substitution-across-harnesses.md)
is what makes the test possible. Codex and OpenCode each expose a slot that takes
a whole prompt, and each exposes the text that slot would otherwise hold, so the
vendor prompt can be read out, rewritten in full, and put back.

## Key findings by sub-topic

### Three stages, in order

The first stage is the open one: rewrite the whole prompt under both authoring
skills, run real work against it, and watch what changes. It is exploratory
rather than controlled, and its output is a description of how the agent behaves
differently, including any way in which it behaves worse.

The second stage is a controlled before and after: the same prompt, the same
tasks, the vendor baseline against the rewritten version. That turns an
impression into a comparison.

The third stage is an ablation. The rewrite bundles several changes at once,
among them positive phrasing, pseudo-XML sectioning, reordering, and whatever
compression the rewrite introduces. Varying one at a time is what separates which
of them carries the effect, and it is also the design that can return the answer
that none of them do. That answer is worth having, and the programme should be
able to reach it.

### The apparatus already exists

On [Codex](../entities/openai-codex.md), the resolved base instructions are
readable per model straight from the installed build, so the baseline needs no
committed copy, and their named sections are what let a later ablation vary one
while holding the rest. That page carries the command, the cache that does not
hold the text, and the off-path binary any generator has to detect.

On [OpenCode](../entities/sst-opencode.md), the per-vendor prompts are sectioned
Markdown, and an agent `prompt` replaces them while the project rules,
environment block, and skills catalogue survive. There is no supported way to
read the resolved text, so the baseline comes from the public repository or from
the installed bundle, and the build it came from has to be recorded alongside any
result.

### Risks that have to be handled before the first run

A configured instructions file on Codex freezes across model switches, because
the provenance changes from generated to explicitly configured and the built-in
path is never consulted again. An experiment left installed therefore pins a
stale prompt silently when the model changes. Every run needs a teardown step,
and any deploy that merges a configuration key needs to capture the prior value
so removal restores rather than deletes. That capture now exists: the deploy
script records a first-write prior on its shared key-merge path and restores it
on uninstall, so an experiment that merges `model_instructions_file` inherits the
teardown rather than building it. See
[the deployment model](../concepts/deployment-model.md).

Section names are undocumented internal structure on both harnesses, so anything
that assembles a prompt from them fails loudly when an expected heading has
moved, rather than appending and hoping. A silently mis-assembled prompt would be
judged as if it were the intended one.

A whole-prompt replacement also drops whatever the vendor prose was carrying that
nobody noticed: scoping, editing constraints, verification habits. On Codex there
is no keep-the-original flag at all, so the rewritten document has to supply that
guidance itself or the comparison measures its absence rather than the rewrite.

### An evaluation harness

A local evaluation harness exists on some machines. It is currently uncommitted
because it grew organically, it is expensive to run, and it is open how it should
be used in future and to what extent.

## Open threads

Which harness to start on. Claude's style layer is the cheapest slot to swap and
the fastest to iterate on, but it displaces the style layer rather than the whole
prompt, so it tests a smaller claim. Codex is the better-instrumented of the two
whole-prompt targets.

Whether a result transfers between models. The base text differs in length and
structure per model, so the programme either repeats per model or states its
scope narrowly.

What a third arm should hold. A rewrite done badly on purpose would separate the
claim that these rules help from the weaker claim that any rewrite helps.

## Related pages

- [System prompt substitution across harnesses](../comparisons/system-prompt-substitution-across-harnesses.md)
  for the mechanism this depends on.
- [Skill family architecture](../concepts/skill-family-architecture.md) for the
  authoring skills under test.

## Derived from

- Session discussion in this repository, 8 August 2026, on whether harness
  research belongs in a shipped skill or a wiki, and what the whole-prompt slots
  make possible.
