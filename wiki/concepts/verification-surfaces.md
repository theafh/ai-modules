---
title: Verification surfaces for a shipped skill
created: 2026-08-10
updated: 2026-10-09
type: concept
tags: [skill, repo-structure, authoring, claude, cursor, verification-gap]
sources: [raw/notes/eval-worker-dependency-skill-reads-2026-10-08.md, raw/notes/micro-deployed-worker-home-probes-2026-10-08.md]
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

### The model under test is pinned by vendor, the meta level inherits or stays model-free

The harnesses that run a skill as a subprocess pick a vendor through
`--vendor claude|cursor` (`tests/lib/vendor.py`). Claude workers use the latest
`sonnet` alias; Cursor workers use `auto`. Deterministic graders stay model-free.
When a judge LLM exists, Claude inherits the session/CLI default and Cursor uses
`auto`. Dated pins such as `claude-sonnet-4-6` are avoided so the harness does
not drift stale as new Sonnet releases land.

The reason the worker is pinned at all is that a result has to mean the same
thing twice. A skill's behavior measured on a model that changes between runs
produces a number that moves for reasons having nothing to do with the skill,
and the harness cannot tell those reasons apart from a real regression. The
vendor defaults keep the subject comparable across runs; leaving the meta level
inherited (or model-free) keeps grading as capable as the session paying for it.

Evals run on the default vendor, Cursor, in the runners and in practice,
because its runs are cheaper and faster. Development therefore iterates on
Cursor results, which stand without a matching Claude run. A test that
exercises a Claude-specific feature names that feature and runs on Claude as
part of ordinary verification. Its command carries `--vendor claude` even on a
Claude-only harness whose default is already Claude, so every Claude run is
visible in its command, and the flag is how a test, or a task's acceptance,
says it needs Claude. Any other Claude run, such as a whole suite run as a
compatibility sample, is an occasional check that waits for the operator's
explicit request, and an agent never starts one on its own initiative or in the
background.

This practice is recorded in the repo rules, `TESTING.md`, `tests/CLAUDE.md`,
and `tests/AGENTS.md`, and encoded in `tests/lib/vendor.py`. Claude-only
surfaces (`trigger_evals`, output-style deploy tests, `natural_language`)
default to Claude instead and stop with an error on an explicit
`--vendor cursor` until a Cursor equivalent exists, so they run on Claude
wherever a change needs them.

### A worker inherits the host's instructions unless it is isolated

A behavioural eval runs its subject as a `claude -p` worker, and that worker
reads more than the harness hands it: the user-level settings, a deployed output
style among them, and every `CLAUDE.md` its ancestor walk reaches, which takes
in the user-level file when the working directory sits under the home directory
([Anthropic Claude Code](../entities/anthropic-claude-code.md)). A sandbox staged
inside this repository therefore runs its worker under the repository's and the
user's standing instructions and under the user's style, which confounds any eval
whose subject is prose. A sandbox outside the home directory and any repository,
with the worker started under `--setting-sources project,local`, keeps those out
while a style staged in the sandbox still loads
([Claude output style selection](claude-output-style-selection.md)). The user's
deployed roles and skills also reach a sandboxed worker. A worker given a
scratch configuration directory listed only the built-in ones
([Anthropic Claude Code](../entities/anthropic-claude-code.md)). A malformed
sandbox settings file fails silently, so a run that depends on a staged style
proves the style loaded before it measures anything. The `language_humanizer`
and `natural_language` harnesses run this way, through the shared isolation
helper under `tests/lib/`. On Cursor, a deployed skill can also take the place of
the copy under test: a print-mode worker read the deployed copy rather than a
staged copy outside its workspace, and a project copy did not displace the
deployed one unless the prompt named its path ([Cursor](../entities/cursor.md)).
A scratch home on Cursor and a scratch configuration directory on Claude each take
the deployed copies out of view, and a skill deployed into that scratch location
was the copy loaded by name on both vendors
([micro-home probes](../raw/notes/micro-deployed-worker-home-probes-2026-10-08.md)). A skill the harness did not
stage, such as the hub or base skill the skill under test reaches by name,
resolved on both vendors to the deployed copy, or to the repository checkout when
the sandbox sat inside it
([dependency reads](../raw/notes/eval-worker-dependency-skill-reads-2026-10-08.md)).
The eval runners therefore deploy each pass's declared skills, agents, and styles
through the repository's own deploy script into such a scratch home, plus the
sandbox project for the types a vendor loads only at project scope, and every pass
checks its worker's reads: a skill, agent, or style file read from anywhere else,
the user's home and the checkout's own sources included, fails the pass
(`tests/lib/micro_deploy.py`). A helper the worker spawns counts as the worker.
Claude's stream carries a helper's tool calls
([Claude Code delegation surfaces](claude-delegation-surfaces.md)), but Cursor's
leaves them out, so on Cursor the check also reads each chat transcript the CLI
writes under the scratch home ([Cursor](../entities/cursor.md)). Cursor's
scratch home also carries login profiles that put back the worker's launch
`PATH`. The print-mode CLI builds each shell command's environment from a login
shell under that home, and without the operator's profile a bundled script got
the stock bash 3.2 rather than the build the operator's `PATH` names
([Cursor](../entities/cursor.md),
[Interpreter and tool-path portability](interpreter-and-tool-path-portability.md)).
A Claude worker's scratch configuration directory
moves discovery but leaves `HOME` at the real home, so its shell can still reach
the deployed copies, and the check expands shell paths against the worker's own
environment to catch that.

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

How far the host's instructions and style moved the results the prose harness
has already recorded is unmeasured.

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
- Marker probes of Claude Code build 2.1.226 on one machine on 2 October 2026,
  for what a headless worker inherits from its host.
