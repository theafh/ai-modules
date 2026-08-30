---
title: Verification surfaces for a shipped skill
created: 2026-08-10
updated: 2026-08-30
type: concept
tags: [skill, repo-structure, authoring, verification-gap]
sources: []
confidence: medium
---

# Verification surfaces for a shipped skill

## Definition

A skill in this repository is verified on two surfaces, because a skill is two
things at once. Its bundled scripts are ordinary programs with exact outputs, so a
deterministic shell test pins them. Its prose has no mechanical output at all:
what the skill does is what an agent does after reading it, which only a run
against a model can show. The first surface is a script test, the second is a
behavioral eval, and neither substitutes for the other.

The rule that follows is that "run the tests" means both surfaces unless someone
narrows the scope, and that reporting one as though it covered both is the
standing failure mode. A skill whose scripts all pass can still route a request
to the wrong sibling, and a skill that behaves well under eval can still ship a
script that breaks on a path with a space in it.

## Current state of knowledge

### The harnesses are committed but do not ship

Every harness lives under a repo-root `tests/` tree, one subdirectory per skill
under test. The authored harness is committed: the eval definitions, the fixtures
and their stagers, the run and grade scripts, and the per-harness READMEs. A clone
carries both the rules for verification, stated in the repo-root instruction
files, and the apparatus that performs it. `tests/.gitignore` keeps out only what
a run regenerates, which is the staged sandboxes, the per-iteration workspaces,
and the per-run logs. The Makefile lint targets prune those same subtrees, so
lint covers the committed harness and nothing else.

Committed is not the same as shipped. `make deploy` copies the skill directories
into vendor config dirs and never touches `tests/`, so no deployed installation
carries a test input it has no use for. The apparatus that verifies a component
travels to every clone and reaches no deployment. This is the shape
[the deployment model](deployment-model.md) notes from the other side, where the
one program every machine depends on is the one program that ships to nobody. The
earlier asymmetry is smaller for it. A second contributor who wants to re-run a
verification now has the harness in hand, though the behavioral evals still need a
model and spend tokens, so a run is reproducible in principle rather than for
free.

### Two harness patterns, one preferred

New harnesses follow the pattern aligned with Anthropic's own `skill-creator`
skill: evals in a canonical `evals.json` with per-eval fixture stagers, script
unit tests beside them in their own directory, and run output kept per iteration.
The evals are driven out of band by `skill-creator`'s own runner rather than by
the harness entry point, which drives only the script tests.

One older harness predates that alignment and keeps a home-grown two-layer shape,
retained until its next significant iteration rather than migrated on principle.
New harnesses are not brought up on it.

### The model under test is pinned, the meta level is not

The harnesses that run a skill as a subprocess pin that worker to one cheap,
stable model, and let only the level above it run on whatever model the host
session is using. The orchestrator, the grader, and the aggregation inherit; the
thing being measured does not.

The reason is that a result has to mean the same thing twice. A skill's behavior
measured on a model that changes between runs produces a number that moves for
reasons having nothing to do with the skill, and the harness cannot tell those
reasons apart from a real regression. Pinning the subject makes the measurement
comparable across runs, and leaving the meta level inherited keeps the grading as
capable as the session paying for it.

This practice is recorded in `tests/CLAUDE.md` and encoded in each runner's
default model. Both are committed now, so any clone can check the claim rather
than take it on one machine's reading.

### Trigger coverage is a third question, asked separately

Whether a skill fires at all on a realistic user message is a property of its
`description`, not of its body, and it is measured on its own rather than folded
into behavioral evals. That keeps a routing failure legible as a routing failure:
a skill can be well written and never load, and a skill can load reliably and
then do the wrong thing. The description's double duty as a routing surface, and
the cost that comes with it, are on
[skill family architecture](skill-family-architecture.md).

### A change ships with the tests that prove it

The scope rule is that a skill change lands together with the tight scenarios and
fixtures proving its own new behavior, and with the existing suite re-run to show
nothing regressed. Where a task's acceptance names an eval, that eval is part of
the change rather than a follow-up. What belongs in its own session is unbounded
growth beyond the change: backfilling coverage of behavior that was already
untested, adding scenarios well past what the change needs, or restructuring a
harness. The boundary is scope rather than timing, which is what keeps an
unrelated coverage sweep from consuming the session that was meant to prove one
edit.

### A grader that tests surface form reports working behaviour as broken

A behavioral eval is only as honest as its grader, and a grader written against
the surface form of a correct answer rather than its substance reports working
behaviour as a regression. This showed up as the dominant failure mode while
building one skill's evals, where grader defects outnumbered defects in the skill
under test. The recurring shape was a check that fixed on one phrasing, one
placement, or one shape of a correct answer and rejected every other valid one: a
verdict demanded on a named side of a two-sided repair, a full enumeration
required where the repo's own conventions prefer a selector, a match anchored to a
name that also appears inside a neighbouring record's prose, a multi-word phrase
matched line by line against hard-wrapped text so a wrap mid-phrase hid it. Every
one of these passed the thing under test and failed the check, which reads as a
regression in the skill and is not.

The rule that follows is to assert the property that must hold and accept every
phrasing and placement that satisfies it. Where a rubric permits two repair
shapes, the check accepts both; where a report field is structured, the check
anchors to the record whose subject is the item under test; where the text is
prose, the check reads it with wraps collapsed. A grader that hard-codes one
surface form is testing its author's guess about the answer, not the behaviour.

### A long conjunction hides which behaviour broke

An eval that asserts many independent behaviours behind one pass or fail obscures
which behaviour broke and turns model-sampling noise into a near-certain failure.
When each of many checks passes on most runs but not all, the conjunction of them
fails most runs, and a different check fails each time, which reads as instability
in the skill when it is arithmetic. The signature is a run that fails on a
different single item each time it is run. The fix is to report a result per
asserted behaviour rather than one verdict over the whole set, so a slip
localizes to the behaviour that slipped and the rest stay legible as holding.

### The auditor checks that verification exists, not that it passes

A skill check reads for the presence of the applicable surface: a script test
surface where the skill bundles scripts, and eval coverage or a documented reason
for its absence where the skill is prose only. It reports which checks it could
not run rather than treating an unrun check as a pass. What it cannot do is
substitute for either surface, since presence is a cheaper question than
correctness.

## Open questions

The weight a behavioral eval should carry is open. A result drawn from a
model is a distribution rather than a value, and nothing here records how many
passes make a verdict, or what a partial pass rate should block. The
per-behaviour reporting rule above sharpens the framing without settling it:
reading a distribution behind a single conjoined bit is the wrong measurement, so
a verdict has to be read per behaviour across runs, but how many passing runs
make one behaviour's verdict stays unrecorded.

## Related concepts

- [Skill family architecture](skill-family-architecture.md), for the description
  as a routing surface and for the auditor that checks it.
- [The ai-modules repository](../summaries/ai-modules-repository.md), for where
  the test tree sits among the other document sets.
- [The deployment model](deployment-model.md), for the other substantial program
  here that every machine depends on and no machine receives.
- [Instruction-defect classes](instruction-defect-classes.md), for the defect
  taxonomy that grader measurement surfaced, and for why review and execution
  test different things.
- [Agent-delegated automation](agent-delegated-automation.md), for the run-time
  verification the autonomous families do, as a counterpart to the test-time
  surfaces here.

## Derived from

- The repo-root instruction files, sections on regression test harnesses and on
  shipping the tests a change needs.
- The repository's `tests/.gitignore` and `Makefile` lint targets for what is
  committed versus regenerated.
- The `tests/` tree, read 10 August 2026 for the two patterns and the model
  policy, and committed since 30 August 2026 so a clone can re-read it.
