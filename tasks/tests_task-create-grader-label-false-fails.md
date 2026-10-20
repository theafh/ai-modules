---
description: "Make task_create eval verdicts match what conformant runs do: fix four grader checks, give every fixture a git identity, and pin the grader fixes with script tests built from recorded forms."
scope: tests/task_create/evals
created: 2026-10-20T12:13:15
updated: 2026-10-20T12:36:00
status: open
reported-by: Andreas Hoffmann
---

# Make task_create eval verdicts match what conformant runs do

## Goal

The `task_create` grader at `tests/task_create/evals/grade.sh` gives the same verdict a reader gives on substance for every label form recorded draws have produced, so a Decide-or-label measurement no longer needs a manual reread of each draw to separate grader misses from real failures. Four checks change: the one-label count counts only label lead-ins, the why-open check accepts a clause that states the guardrail-bound ground, the guardrail-bound both-paths check accepts a non-`rich` path described without the words "ANSI" or "escape", and the one-file check reports zero files as zero. Each grader fix is pinned by a script test, so the forms stay covered after the workspace runs that showed them are gone. Every `task_create` fixture also gives its sandbox a git identity, so a worker's reply carries only the decision under test.

## Context

This task extends [the grader-authoring discipline task](archive/tests_grader-authoring-discipline.md), whose Acceptance entry beginning "Each label-structure check in `tests/task_create/evals/grade.sh`" made the label checks match a qualified lead-in, an evidence-phrased why-open clause, and several option-enumeration forms. Draws recorded on 2026-10-15, 2026-10-16, and 2026-10-20 show four forms that entry did not reach. The guardrail-bound fork task's findings record two of them.

- **Label count.** `open_decision_count` counts every line matching `OPEN_DECISION_LEAD_IN_PLAIN`, case-insensitively and anywhere in a line, and `label_lines` starts its window on the same unanchored pattern. A body with one real label and a later pointer to it, such as the Acceptance line "The tree matches the path chosen in the open decision: either …" or a Context bullet naming the Approach label, counts two and fails "exactly one labeled open-decision lead-in in the body". Across every recorded `task_create` sandbox task file, each real label starts a line after optional list markers and emphasis, and each mid-line match is a pointer such as "the settled presentation path from the open decision is the one in use:".
- **Why-open clause.** `why_open_clause` matches a fixed alternation of fork, decision, evidence, and user's-call phrasings. A label whose reason reads "(guardrail-bound: every path crosses a boundary or rewrites a guardrail doc)" matches none of them and fails "the label carries a guardrail-bound why-open clause", although it states the ground the base **Decide or label** rule names.
- **Both crossing paths.** In the `guardrail-bound-surface` arm, `names_both_paths` requires `rich` and `ANSI|escape` in the label window. Labels naming the second path as "CSI `33m` around the warning label" or as "stdlib or in-repo presentation only … and rewrite `ARCHITECTURE.md` `## Presentation`" fail "the label names both crossing paths (rich / ANSI)".
- **Empty sandbox.** The universal block builds `open_files=( "$TASKS"/*.md )` without `nullglob`, so a sandbox with no task file keeps the unexpanded pattern as one element and prints "exactly one task file created under tasks/ (got 1)". The verdict is right, but the count misleads anyone reading a failure.
- **Fixture identity.** The `labeled-why-open` and `guardrail-bound-surface` fixtures call `new_project "$target"` without `--git`, so `git config user.name` is empty in the sandbox. In every recorded draw of those two evals since 2026-10-14, the worker asked the user which name to record as `reported-by` and wrote `default_user`. The `reconcile-recorded` fixture already uses `new_project "$target" --git` and `git_commit_all` from `tests/task_create/evals/fixtures/_common.sh`, which sets the identity `Evals`.

`tests/task_create/` has no `script_tests/` today. `tests/task_fix/script_tests/run.sh` checks its `evals/grade.sh` on staged fixtures and chosen responses, and serves as the model. [The prior-art related-precedent task](task-family_prior-art-related-precedent-is-novel.md) adds a new eval's checks to the same `grade.sh`, and the live `tests_task-create-parallel-evals` task edits its host-guard marker checks, so whichever lands second rebases on the other.

## Approach

Rewrite each check in place in `tests/task_create/evals/grade.sh`. Author every change under the standing repo rules for grader design.

- **Label count.** Anchor the lead-in pattern to a block start: the start of a line after optional list markers and emphasis, so `**Open decision (guardrail-bound):**`, `- **Open decision:**`, and a paragraph opening `Open decision:` still count, while a mid-sentence mention does not. Use the same anchored pattern for `open_decision_count` and `label_lines`, so the window starts at the real label.
- **Why-open clause.** Add the guardrail-bound ground's own phrasing to the subject-anchored alternation: a clause naming `guardrail-bound` together with every or each path or option crossing a boundary, rewriting a guardrail document, or routing around one. A label whose only reason-like text is the suggested default explaining itself still fails.
- **Both crossing paths.** Accept the non-`rich` path by its substance: raw ANSI, escape codes, CSI or SGR sequences, `\033` or `\x1b`, stdlib or stock-interpreter styling, or a rewrite of the architecture document's Presentation rule. A label naming only the `rich` path still fails.
- **Empty sandbox.** Build the file list so zero files report as zero, for example with `nullglob` scoped to that expansion, and leave the check's verdict unchanged.

Switch the `labeled-why-open` and `guardrail-bound-surface` fixtures to `new_project "$target" --git` and finish each with `git_commit_all`, the way `reconcile-recorded` does, and update each eval's `expected_output` in `tests/task_create/evals/evals.json` where it describes the sandbox.

Add `tests/task_create/script_tests/run.sh`, modelled on the `task_fix` script tests, which stages minimal sandboxes with the bodies Acceptance names, runs `grade.sh` on each, and asserts the PASS or FAIL line of the check under test. Update every harness doc that describes the `task_create` layout (such as the `task_create` row in the `## What's here` table of `tests/CLAUDE.md`, `tests/task_create/README.md`, and `tests/task_create/RUNBOOK.md`) to name the script tests and how to run them.

## Acceptance

- `bash tests/task_create/script_tests/run.sh` exits 0, and it asserts each case below on `grade.sh` output. Each case marked "fails today" fails against the current grader.
  - A body with one real label and the Acceptance pointer "the path chosen in the open decision: either" passes the one-label check (fails today).
  - A body with two real labels fails the one-label check.
  - A label whose why-open reason reads "(guardrail-bound: every path crosses a boundary or rewrites a guardrail doc)" passes the why-open check (fails today).
  - A label whose only reason-like text is a suggested default explaining itself fails the why-open check.
  - A label naming `rich` and a CSI `33m` path, and a label naming `rich` and a stdlib path that rewrites the Presentation rule, each pass the both-paths check (fails today).
  - A label naming only the `rich` path fails the both-paths check.
  - A sandbox with no task file fails the one-file check and reports "(got 0)" (fails today).
- After `bash tests/task_create/evals/stage.sh <id> <dir>` for `labeled-why-open` and for `guardrail-bound-surface`, `git -C <dir>/proj config user.name` prints `Evals`.
- One `--no-cache` run each of `labeled-why-open` and `guardrail-bound-surface` on the default vendor writes `reported-by: Evals`, and its `response.txt` asks for no name.
- Every harness doc that describes the `task_create` layout names `script_tests/run.sh`.
