---
description: Share record-bounded repeated-link disposition helpers in tests/lib, rewrite both graders onto them, unit-test and document the shared file, and re-grade affected evals.
scope: tests
created: 2026-10-08T18:10:50
updated: 2026-10-08T23:26:01
status: ready
reported-by: Andreas Hoffmann
---

# Share record-bounded repeated-link disposition helpers across the task_fix and task_auto_check graders; unit-test, document, and re-grade

## Goal

Move the helpers that read a run's `repeated-link` disposition lines into one shared file, `tests/lib/repeated_link_disposition.sh`, sourced by `tests/task_fix/evals/grade.sh` and `tests/task_auto_check/evals/grade.sh`, and make every disposition check in both graders read only its own finding's line. A disposition word, a surfaced reason, or the archived count then passes or fails on what that line says, never on prose that happens to follow it.

## Context

Both graders read the per-finding disposition line from a worker's `response.txt` through helpers each one defines for itself. Both carry `disposition_blocks`, which joins the response's hard wraps and keeps up to 400 characters after each `repeated-link:` lead-in, and `disposition_of`, which returns the first disposition word in a finding's block. The `task_fix` grader adds `disposition_line`, which accepts a disposition word anywhere in the block. The `task_auto_check` grader adds `disposition_reason`, which already bounds a surfaced reason to its own record and first sentence, and its `surfaced_reason_organizational` check reads keywords through it.

A 400-character block runs past its line into whatever prose follows, so a check that calls `disposition_line` or greps the block itself can match words outside its finding's line. On 2026-10-08, probes on staged fixtures confirmed four false passes:

- `reason_names_acceptance` in the `task_fix` `surfaced_acceptance_contract` arm passed the reason "each link helps the implementer find the sibling" once the next sentence named Goal and the Acceptance contract.
- `surfaced_line` in the same arm passed a line reading `regrouped` because the following prose said "surfaced".
- `disposition_line_regrouped` in the `task_auto_check` `regroup_via_reviewer` arm, which never names its finding, passed a target line reading surfaced because later prose said "regrouped".
- `archived_count_line` in the `task_fix` `regroup_live_skip_archived` arm passed a report with no count line because a later sentence said "archived".

`tests/lib/host_tasks_guard.sh` and `tests/lib/plugin_version.sh` are the precedent for shared grader shell helpers. Graders source them through a `# shellcheck source=` line, `tests/lib/test_host_tasks_guard.sh` unit-tests the first, and `tests/CLAUDE.md` documents the sourcing contract of the second. TESTING.md's **Anchor a structured match to its subject.** rule is the property these helpers enforce, and its Test Integrity section governs each check this task edits.

## Approach

These steps share one rationale (record-bounded disposition reads), one edit surface (`tests/lib/` plus the two graders), and one acceptance story, so they stay one task.

- **Shared file.** Create `tests/lib/repeated_link_disposition.sh` with four helpers. Each reads `$RESPONSE`, which the sourcing grader sets before sourcing the file, and returns non-zero when that file is missing or empty; a header comment states that contract.
  - `disposition_blocks` prints one block per `repeated-link:` lead-in, with its hard wraps joined, ending where its record ends or the next lead-in starts. A record ends at a blank line, a code fence, a heading, a table row, or a list marker, the boundaries the `task_auto_check` grader's `disposition_reason` already uses. This replaces the 400-character cap.
  - `disposition_of <needle>` prints the first disposition word (`regrouped`, `surfaced`, or `kept`) of the first block naming the needle.
  - `disposition_words <needle>` prints that word for every block naming the needle, one per line.
  - `disposition_reason <needle>` prints a surfaced block's reason, from `surfaced because` to its first sentence end or table cell boundary.
- **Source it.** In both graders, delete the local disposition helpers, `disposition_line` included, and source the shared file right after `RESPONSE` is set, through a `# shellcheck source=../../lib/repeated_link_disposition.sh` line.
- **Rewrite the checks.** Before rewriting, inventory both graders for three properties: every `disposition_line` call, every grep of `disposition_blocks` output, and every remaining local `disposition_*` helper definition. Point every inventoried site at the shared helpers. A disposition-word check compares `disposition_of` or `disposition_words` for its own finding, and a reason check, `reason_names_acceptance` included, matches its keywords against `disposition_reason` only. The `task_fix` grader's archived-count check matches the count line's own block from its lead-in, `repeated-link:` followed by a number of findings on archived tasks. When [the live-only body-checks task](task-family_live-only-body-checks.md) has already landed, that check asserts the count line's absence instead, anchored on the same lead-in, so keep it as that task wrote it and only move it onto the shared helpers.
- **Unit test.** Add `tests/lib/test_repeated_link_disposition.sh`, shaped like `tests/lib/test_host_tasks_guard.sh`. It writes hand-built responses to a temporary file and asserts that:
  - a block ends at its record, so a paragraph after a blank line stays out of it, while a hard-wrapped line yields one whole block;
  - a fenced block of two disposition lines yields two blocks, each keeping its own reason;
  - `disposition_of` returns a line's own disposition when the following prose names another, and nothing for a line without a disposition word;
  - `disposition_words` returns one word per line for a finding reported twice;
  - `disposition_reason` stops at the first sentence end and at a table cell boundary;
  - every helper returns non-zero when `RESPONSE` names a missing or empty file.
- **Document it.** Add a short passage to `tests/CLAUDE.md` that names the shared file, its `RESPONSE` contract, and the unit-test command.
- **Verify by re-grading.** Re-grade rather than re-run, as TESTING.md's Re-run Economy section directs when the grader changes and the behaviour does not. Copy the most recent recorded run of each affected eval from its harness's `workspace/` directory, which keeps `response.txt` beside `sandbox/`, and run that harness's `grade.sh` on the copy's `sandbox/proj`. An affected eval is one whose grader arm calls a helper the shared file defines. Run an affected eval on the Cursor worker only when no recorded run of it exists.

**Out of scope:**

- Moving `surfaced_channel_names_repeated_link`, which only the `task_auto_check` grader uses and which reads the surfaced-but-not-fixed channel rather than a disposition line.

## Acceptance

- `tests/lib/repeated_link_disposition.sh` defines `disposition_blocks`, `disposition_of`, `disposition_words`, and `disposition_reason`, and its header comment states that the sourcing grader sets `RESPONSE` first. Both graders source it through a `# shellcheck source=../../lib/repeated_link_disposition.sh` line that appears after `RESPONSE` is set, and `grep -nE '^disposition_[a-z]+\(\)' tests/task_fix/evals/grade.sh tests/task_auto_check/evals/grade.sh` prints nothing.
- In both graders, `grep -nE 'disposition_blocks[[:space:]]*\|' tests/task_fix/evals/grade.sh tests/task_auto_check/evals/grade.sh` prints nothing, and each `every_line_regrouped` check reads its finding's disposition words through `disposition_words`.
- `bash tests/lib/test_repeated_link_disposition.sh` exits 0 and asserts each case the **Unit test.** step lists.
- On a `surfaced_acceptance_contract` fixture staged with `bash tests/task_fix/evals/stage.sh`, a response whose line reads "surfaced because each link helps the implementer find the sibling", followed by a separate sentence naming Goal and the Acceptance contract, fails `the surfaced reason names the contract it protects`, while a response whose reason names the Acceptance contract passes it.
- On the same staged fixture, a response whose line reads `regrouped`, followed by prose that says "surfaced", fails `the report's line for this finding reads surfaced`.
- On a `regroup_via_reviewer` fixture staged with `bash tests/task_auto_check/evals/stage.sh`, a response whose line for `api_quota-retry-header` reads surfaced, followed by prose that says "regrouped", fails `the response carries the finding's disposition line as regrouped`.
- On a `regroup_live_skip_archived` fixture staged with `bash tests/task_fix/evals/stage.sh`, a response carrying the live finding's line and the sentence "The archived bodies were left exactly as archived." but no count line fails `the report carries the archived-count line`. When the live-only body-checks task has already made that check an absence check, the same response passes `the report carries no archived-count line` instead.
- Every affected eval, as the **Verify by re-grading.** step defines it, passes under the new graders.
- `tests/CLAUDE.md` names `tests/lib/repeated_link_disposition.sh`, its `RESPONSE` contract, and `bash tests/lib/test_repeated_link_disposition.sh`.
