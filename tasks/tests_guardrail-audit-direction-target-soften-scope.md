---
description: Scope the guardrail_audit direction_target softening check to sentences about the Direction target so an unrelated doc-vs-code option stops failing it.
scope: tests/guardrail_audit/evals
created: 2026-11-06T09:48:40Z
updated: 2026-11-09T14:23:24Z
status: ready
reported-by: Andreas Hoffmann
---

# Scope the direction_target softening check to the Direction target

## Goal

The `direction_target` arm of `tests/guardrail_audit/evals/grade.sh` fails its
`response offers no softening or deletion of the target` check only when the
response actually offers to soften or delete the `## Direction` target. A
response that offers `bring the doc back to the code` as a doc-vs-code reconcile
option for an unrelated finding passes, so a conformant draw grades PASS on
substance instead of needing a manual reread.

## Context

- The check lives in `tests/guardrail_audit/evals/grade.sh` under the
  `direction_target)` arm, titled `response offers no softening or deletion of
  the target`, and runs `lacks_unnegated` over a marker that includes
  `bring the (doc|ARCHITECTURE\.md) back to the (code|repositor)`.
- The 2026-11-05 default run recorded in
  `tests/guardrail_audit/results/parallel-workers-windows.md` graded 5/6, with
  `direction_target` the only failure. In that draw the response's closing
  question asks `- For finding 1 (header casing): move the code to match the
  doc, or bring the doc back to the code?`, while its Direction paragraph says
  `Softening or deleting the target to match today's code is not offered`. The
  check matches the unrelated first sentence because the marker names no
  subject.
- This is the same defect class the archived
  [grader-authoring discipline task](archive/tests_grader-authoring-discipline.md)
  names as "Anchor a structured match to its subject", and the archived
  [task_create grader false-fails task](archive/tests_task-create-grader-label-false-fails.md)
  fixed in that grader by pinning each accepted and rejected form with script
  tests.
- `tests/guardrail_audit/script_tests/run.sh` covers the static contract and the
  stage guard but runs no chosen response through `grade.sh`.
  `tests/task_fix/script_tests/run.sh` is the model for a grader-response test:
  stage the fixture, write a chosen response, run `grade.sh`, and assert the
  named check's PASS or FAIL line.

## Approach

Scope the marker's `bring the (doc|ARCHITECTURE\.md) back to the (code|repositor)`
branch to its subject: require that branch's matched sentence to also name the
target — `target`, `direction`, `## Direction`, `StreamPipeline`, `streaming
pipeline`, or `pipeline.py` — so an unrelated doc-vs-code reconcile option no
longer matches. Leave the `soften(ing)? the (target|direction|statement|doc)`
alternative whole and unqualified, so `soften the doc` keeps matching, and widen
the deletion alternative to accept a `##`-prefixed heading —
`(delete|deleting|remove|removing|drop|dropping) the (unbuilt |unreached )?(## )?(target|Direction section)`
— so the Acceptance's `delete the ## Direction section` fails the check. Keep
the negated-line stripping that lets a response say softening is not offered.
The subject requirement sits on one alternative rather than a whole-marker
conjunct because POSIX `grep -E` has no lookahead.

Add a grader-response script test beside the existing static tests, modelled on
`tests/task_fix/script_tests/run.sh`, with five chosen responses against a staged
`direction_target` sandbox:

- the recorded shape, where `bring the doc back to the code` appears only for an
  unrelated header-casing finding and the Direction paragraph refuses
  softening, passes the check;
- a response that offers `soften the target` still fails it;
- a response that offers `delete the ## Direction section` still fails it;
- a response that offers `soften the doc to match the code` still fails it,
  because the fixture's `## Direction` lives in `ARCHITECTURE.md`.
- a response that offers `For the streaming pipeline target, bring the doc back
  to the code.` still fails it, because the sentence names the target and the
  subject-scoped branch must keep catching it.

Re-run `python3 tests/guardrail_audit/evals/run.py --force direction_target` on
the default Cursor vendor and record the graded result, check by check, in
`tests/guardrail_audit/results/direction-target-softening.md`.

**Out of scope:** Changing the `guardrail_audit` skill or its fixtures. The
`doc_vs_code` arm's own `bring the doc back to the code` marker, which correctly
targets the finding under test there.

## Acceptance

- The guardrail_audit script tests run a chosen response through `grade.sh` and
  assert every direction: the recorded shape passes `response offers no softening
  or deletion of the target` (fails today), and a response that offers `soften
  the target`, `delete the ## Direction section`, `soften the doc to match the
  code`, or `For the streaming pipeline target, bring the doc back to the code`
  fails it.
- `python3 tests/guardrail_audit/evals/run.py --force direction_target` on the
  default vendor is run once and recorded. The deterministic script test above
  is the proof that the check is scoped correctly, so this evaluation draw is
  recorded corroboration, not a gate: a `FAIL` draw keeps the item satisfied
  when its output is recorded and reported as that run's measurement rather
  than rerun until green.
- `tests/guardrail_audit/results/direction-target-softening.md` records the
  default-vendor `python3 tests/guardrail_audit/evals/run.py --force
  direction_target` draw: the command, the vendor, the run dir, and the graded
  per-check lines.
- The prior marker in `tests/guardrail_audit/evals/grade.sh` is superseded in
  place, leaving one canonical subject-scoped softening check for
  `direction_target`.
- `make lint` passes.
