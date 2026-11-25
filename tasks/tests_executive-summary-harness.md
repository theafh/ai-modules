---
description: "Add a Pattern A behavioural harness for executive_summary: staged source documents, a deterministic length and shape grader, and a refute-biased fidelity judge."
scope: tests
created: 2026-11-25T06:13:24Z
updated: 2026-11-25T06:13:24Z
status: open
reported-by: Andreas Hoffmann
---

# Add a behavioural harness for executive_summary

## Goal

Give `executive_summary` a running behavioural harness under `tests/executive_summary/`, so its output contract is proven by a graded run instead of left to the worker's judgement. The harness grades the length target and the prose-only shape deterministically, and judges how faithfully the summary preserves the source's reasoning and order.

## Context

`tests/README.md` `## Coverage decisions` records this skill's disposition as coverage owed, filed here because a full harness is unbounded backfill beyond the coverage-gap task `tests_skill-test-coverage-gaps.md`. The output contract lives in `plugins/ai_dev/skills/executive_summary/SKILL.md` under `<executive_summary>`: `<length>` targets 10 to 15% of the input, `<prose_only>` forbids bullet points and numbered lists, and `<scope_boundary>` forbids content that is not in the input.

`tests/git_commit/` is the Pattern A reference, and `tests/README.md` `## Convention` gives the layout. Build on `tests/lib/eval_runner`, `tests/lib/vendor.py`, and `tests/lib/micro_deploy.py` the way the other Pattern A harnesses do.

## Approach

Create `tests/executive_summary/` with `evals/evals.json`, one fixture per eval that stages a source document of recorded length, `evals/run.py`, and `evals/grade.sh`. Grade the word-count ratio against the fixture's source length, the absence of list markers, and the absence of content that the source does not carry; add a refute-biased judge for fidelity and ordering. Add `script_tests/run.sh` proving the grader's own PASS and FAIL directions, add `run_all.sh`, and add the harness to both inventories (`tests/README.md` `## Current harnesses` and `tests/CLAUDE.md` `## What's here`).

Run the recorded measurement on the default vendor per `TESTING.md`, and name the harness prefix in `ALLOWED_ISOLATION_PREFIXES` in `tests/lib/test_worker_isolation.py`.

## Acceptance

- `tests/executive_summary/` follows Pattern A, and `bash tests/run_all.sh --surface executive_summary` passes.
- `script_tests/run.sh` proves the grader's PASS direction and at least one FAIL direction for each deterministic check: the length ratio, the list markers, and out-of-source content.
- The harness appears in both inventories, and `tests/README.md` `## Coverage decisions` moves `executive_summary` from coverage owed to covered.
- A recorded run on the default vendor shows every eval graded, with the verdicts recorded in the harness's results.
