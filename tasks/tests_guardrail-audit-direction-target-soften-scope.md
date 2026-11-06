---
description: Scope the guardrail_audit direction_target softening check to sentences about the Direction target so an unrelated doc-vs-code option stops failing it.
scope: tests/guardrail_audit/evals
created: 2026-11-06T10:48:40
updated: 2026-11-06T10:48:40
status: open
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

Scope the softening/deletion marker to its subject. Require the matched sentence
to also name the target — `target`, `direction`, `## Direction`,
`StreamPipeline`, `streaming pipeline`, or `pipeline.py` — so an unrelated
doc-vs-code reconcile option no longer matches. Keep the existing
`soften(ing)? the (target|direction|statement|doc)` and deletion alternatives
matching when they name the target, and keep the negated-line stripping that
lets a response say softening is not offered.

Add a grader-response script test beside the existing static tests, modelled on
`tests/task_fix/script_tests/run.sh`, with two chosen responses against a staged
`direction_target` sandbox:

- the recorded shape, where `bring the doc back to the code` appears only for an
  unrelated header-casing finding and the Direction paragraph refuses
  softening, passes the check;
- a response that offers `soften the target` or `delete the ## Direction
  section` still fails it.

Re-run `python3 tests/guardrail_audit/evals/run.py --force direction_target` on
the default Cursor vendor and record the graded result under
`tests/guardrail_audit/results/`.

**Out of scope:** Changing the `guardrail_audit` skill or its fixtures. The
`doc_vs_code` arm's own `bring the doc back to the code` marker, which correctly
targets the finding under test there.

## Acceptance

- The guardrail_audit script tests run a chosen response through `grade.sh` and
  assert both directions: the recorded shape passes `response offers no softening
  or deletion of the target` (fails today), and a response that offers `soften
  the target` or `delete the ## Direction section` fails it.
- `python3 tests/guardrail_audit/evals/run.py --force direction_target` on the
  default vendor prints `direction_target: PASS`.
- The prior marker in `tests/guardrail_audit/evals/grade.sh` is superseded in
  place, leaving one canonical subject-scoped softening check for
  `direction_target`.
- `make lint` passes.
