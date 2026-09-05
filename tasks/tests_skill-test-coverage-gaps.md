---
description: Add the skill-test coverage the skill_doctor sweep found missing: a script-test surface for ai_instruction_formatting's linter, and a recorded coverage disposition for the behaviour-only skills.
scope: "local test harnesses"
created: 2026-09-05T09:47:15
updated: 2026-09-05T09:47:15
status: open
reported-by: Andreas Hoffmann
---

# Backfill the skill-test coverage gaps the skill_doctor sweep surfaced

## Goal

Close the two skill-test coverage gaps a repo-wide skill_doctor sweep found, so every skill the standing repo rules require to carry test coverage either carries it or records why it does not.

First deliverable: `ai_instruction_formatting` gains a bundled-script test surface. Its linter `plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py` is real parsing logic the skill instructs users to run, yet nothing under `tests/` exercises it. After this task, a Pattern A `script_tests/` harness runs the linter over fixtures and asserts its verdicts, so a change to the linter is regression-checked instead of taken on trust.

Second deliverable: each behaviour-only skill that ships no bundled scripts and today carries neither eval nor trigger coverage leaves this task with a recorded disposition, either coverage added or a documented reason it has none. The skills in that set today are `format_markdown`, `format_python`, `harness_portability`, `executive_summary`, and `spr`.

## Context

The standing repo rules on regression harnesses require a script-bundling skill to have a script-test surface somewhere in the repo, and a behaviour-only skill to have eval or trigger coverage or a documented reason it has none. A skill_doctor sweep on 2026-09-05 checked all thirty skills; the deterministic layers came back clean, and these coverage gaps were the concrete test-side findings.

`ai_instruction_formatting` is the only script-bundling skill with no test surface: the git-family skills, `skill_doctor`, `task`, `update_changelog`, and `wiki` each already have one. The linter recognises four host-file shapes, stated in the skill body at the verbatim passage "Four document shapes are valid", and emits errors, warnings, and non-blocking hints, so the harness has a defined output contract to assert against.

The behaviour-only set is derived, not fixed: it is the skills with no `scripts/` directory and no coverage under `tests/<skill>/` or the shared `tests/trigger_evals/`. The task family already routes its members' coverage through `tests/task/` evals, and the `wiki_*` and `task_explain` triggers live in `tests/trigger_evals/`, so those are already covered; the five named above are what remains.

The Pattern A shape and where each surface lives are set by the standing repo rules and by the tests-tree operating guide; `tests/git_commit/` is the named reference implementation, and the eval schema is skill-creator's.

`git_refresh` also has behavioural evals with no runner, but a separate open task already owns adding that runner, so this task leaves it there and defers to it under Approach.

## Approach

Build the `ai_instruction_formatting` script-test surface first, as a new `tests/ai_instruction_formatting/` harness following the Pattern A layout the repo convention mandates and the tests-tree operating guide documents. Take `tests/git_commit/script_tests/` as the shape reference. Add a `script_tests/run.sh` that drives `lint_pseudo_xml.py` over small fixtures covering each of the four recognised document shapes plus a file that trips an error, a file that trips a warning, and a clean file, asserting the exit status and the reported issue counts for each. Register the new harness in the tests-tree operating-guide inventory and in `tests/README.md`, and change the Makefile `EXCLUDE` list and `tests/.gitignore` together if the harness generates run output, per the standing rule that keeps those two lists in step.

Then take the behaviour-only set one skill at a time. For each, decide against the standing rule whether to add trigger coverage (a `tests/trigger_evals/<skill>.json` entry driven by the existing runner), add a behavioural eval harness, or record a documented reason the skill needs none. Record each disposition where the tests-tree operating guide keeps coverage decisions, so a later skill_doctor run reads the reason instead of re-flagging the gap. Where a decision is to add coverage and that coverage would grow into a full behavioural harness, split that skill's harness into its own sibling task rather than expanding this one past the 300-line ceiling.

Derive the behaviour-only set at implementation time by re-running the skill_doctor sweep, or by listing skills with no `scripts/` directory and no `tests/<skill>/` or `tests/trigger_evals/<skill>.json` coverage, rather than trusting the five names frozen here, since a skill added since could join the set.

**Out of scope:** Adding a runner for the `git_refresh` behavioural evals, which [the git eval-runner parity task](tests_git-eval-runner-parity.md) owns. Adding behavioural evals beyond what closes a named gap, which the standing repo rule on harness growth keeps to its own session.

## Acceptance

- `tests/ai_instruction_formatting/script_tests/run.sh` exists and, run from a clean checkout, drives `lint_pseudo_xml.py` over fixtures for all four recognised document shapes and asserts the exit status and issue counts for a clean file, an error file, and a warning file; it exits non-zero when any assertion fails.
- Running the new harness through the repo's standard script-test entry point reaches it, so it appears in the run and reports pass or fail rather than sitting as an orphan file.
- The tests-tree operating-guide inventory and `tests/README.md` both list the new `ai_instruction_formatting` harness, and neither still implies that skill is untested.
- Each of `format_markdown`, `format_python`, `harness_portability`, `executive_summary`, and `spr` has, in the tree, either added coverage (a trigger entry or eval harness that runs) or a documented reason for having none, recorded where the operating guide keeps coverage decisions; a fresh skill_doctor test-coverage check names none of them as an undocumented gap.
- `make lint` passes.
