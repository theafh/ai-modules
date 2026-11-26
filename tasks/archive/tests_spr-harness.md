---
description: "Add a Pattern A behavioural harness for spr: staged source documents, a deterministic bullet-per-paragraph and shape grader, and a refute-biased reconstructability judge."
scope: tests
created: 2026-11-25T06:13:24Z
updated: 2026-11-26T22:43:00Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Add a behavioural harness for spr

## Goal

Give `spr` a running behavioural harness under `tests/spr/`, so its output contract is proven by a graded run instead of left to the worker's judgement. The harness grades the bullet-per-paragraph floor, the bullet shape, and the reconstructability rating deterministically, and judges how much of the source an unprimed reader can reconstruct.

## Context

`tests/README.md` `## Coverage decisions` records this skill's disposition as coverage owed, filed here because a full harness is unbounded backfill beyond the coverage-gap task `tasks/archive/tests_skill-test-coverage-gaps.md`. The output contract lives in `plugins/knowledge_management/skills/spr/SKILL.md` under `<output_contract>`: markdown bullets, no numbered lists, no trailing punctuation on a bullet, at least one bullet per source paragraph, and a final integer rating from 1 to 10.

`tests/git_commit/` is the Pattern A reference, and `tests/README.md` `## Convention` gives the layout. Build on `tests/lib/eval_runner`, `tests/lib/vendor.py`, and `tests/lib/micro_deploy.py` the way the other Pattern A harnesses do.

## Approach

Create `tests/spr/` with `evals/evals.json`, one fixture per eval that stages a source document with a recorded paragraph count, `evals/run.py`, and `evals/grade.sh`. Grade the bullet count against the fixture's paragraph count, the absence of numbered lists and trailing punctuation, and the presence of a final integer rating between 1 and 10; add a refute-biased judge for non-overlap and reconstructability. Add `script_tests/run.sh` proving the grader's own PASS and FAIL directions, add `run_all.sh`, and add the harness to both inventories (`tests/README.md` `## Current harnesses` and `tests/CLAUDE.md` `## What's here`).

Run the recorded measurement on the default vendor per `TESTING.md`, and name the harness prefix in `ALLOWED_ISOLATION_PREFIXES` in `tests/lib/test_worker_isolation.py`.

## Acceptance

- `tests/spr/` follows Pattern A, and `bash tests/run_all.sh --surface spr` passes.
- `script_tests/run.sh` proves the grader's PASS direction and at least one FAIL direction for each deterministic check: the bullet-per-paragraph floor, the numbered-list and trailing-punctuation rules, and the rating range.
- The harness appears in both inventories, and `tests/README.md` `## Coverage decisions` moves `spr` from coverage owed to covered.
- A recorded run on the default vendor shows every eval graded, with the verdicts recorded in the harness's results.
