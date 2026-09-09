---
description: Give git_commit a git-standard subject/blank/body: rewrite <message_policy> and prepare-context instruction, add status-4 blank-line refusal, rewire consumers, update evals.
scope: plugins/ai_dev/skills
created: 2026-09-09T13:17:22
updated: 2026-09-09T19:16:49
status: ready
reported-by: Andreas Hoffmann
---

# Give git_commit's message policy a git-standard subject and blank line, with prepare-context, status-4 backstop, consumers, and evals

## Goal

A body-bearing commit written through `git_commit` produces a message with git's standard structure named by the Approach's `<multi_file>` form: one subject line, a blank line, then the body; a `<single_file>` commit stays the subject-only one-line message the Approach already names. Today the skill's `<multi_file>` rules place the first body line directly under the subject with no blank line, so git and standard git tooling read the whole message as a single subject line. That makes `git log --oneline`, `git shortlog`, and `git format-patch` show the entire message as the title and leaves the commit with no body. After this change, the message rules prescribe the blank-line separation for body-bearing forms, and a message composed from them parses as subject plus body.

## Context

`plugins/ai_dev/skills/git_commit/SKILL.md` holds the message rules in the `<message_policy>` block. Its `<multi_file>` form says to "write one concise sentence summarizing what all changes are about, then list one line per changed file in the format `file name -> concrete change`", and it never names a blank line between the sentence and the list. Followed literally and correctly, the model emits the subject on the first line and the first `file name -> concrete change` on the second line. That second-line-non-blank shape is exactly what git treats as a continuation of the subject rather than the start of a body.

The script reproduces the defect faithfully and should not be the thing that hides it: `scripts/commit_with_message.sh` commits with `git commit -F -`, and its documented behavior is to "preserve line breaks exactly", so it commits whatever structure the model composed. The defect lives in the rules the model follows, not in the script's faithful reproduction of them.

The skill is already internally inconsistent about this. Its own `references/manual_fallback.md` shows the correct shape in the heredoc template it hands the model for a failed-script run: a `<subject line>`, a blank line, then `<body lines>`. So the fallback path already prescribes git's structure while the primary `<message_policy>` does not, and this task brings `<message_policy>` into line with the template the same skill already ships.

Git's own convention is the authority: the first line is the subject, the second line is blank, and the rest is the body. The common commit-message linter gitlint encodes the same rule as its `B4` check, "second line is not empty", so a message missing the blank line also fails a standard message-lint gate wherever one runs.

The archived [drift guard in the script](archive/ai-dev_git-commit-drift-guard-in-script.md) is the precedent behind putting the enforcement in the script: it deliberately moved the foreign-drift guarantee out of a prose-only step into `commit_with_message.sh` so the guarantee "no longer depends on the running model following a prose instruction".

## Approach

Rewrite the `<message_policy>` block in `plugins/ai_dev/skills/git_commit/SKILL.md` so its forms prescribe git's standard structure in place of the sentence-then-list run-on:

- The `<multi_file>` form: a subject line that summarizes the change, then a blank line, then one `file name -> concrete change` line per changed file as the body. Name the blank line explicitly as the separator between subject and body.
- The subject line itself: a short standalone summary rather than a full summarizing sentence, and no trailing period, so it reads as a git subject line rather than a prose sentence.
- The `<single_file>` form: one `file name -> concrete change` line stands as the whole message with no body, which is already valid; state that this line is the subject so the no-trailing-period guidance covers it too.

Match the shape the skill's own `references/manual_fallback.md` heredoc template already shows (`<subject line>`, blank line, `<body lines>`), so the primary and fallback paths describe one structure. Frame each edit as rewriting the affected passage in place to its target form, so one canonical statement of the message structure remains rather than a new rule sitting beside the old conflating one.

Rewrite the `<commit_message_instruction>` printed by `scripts/prepare_commit_context.sh` so the multi-file instruction matches that same subject-then-blank-line-then-per-file-body form in place of "one concise summary sentence followed by one line per changed file", keeping the single instruction as the canonical statement the context blob hands the model.

Enforce the same structure mechanically in `scripts/commit_with_message.sh` so the guarantee holds whatever model composed the message. Before it commits, have the script reject a piped message whose second line is non-empty, exiting with status `4` and a stderr message naming the problem and committing nothing — the same refusal shape as its status-`3` drift exit, on a dedicated status so consumers can tell the two refusals apart. Document status `4` in the script's usage Exit status banner beside the existing `0`–`3` entries, and rewrite the Behavior section so it names the second-line-non-empty refusal the same way it already names the exit-`1`/`2`/`3` refusals. A refusal never rewrites the message, so it keeps the script's preserve-exact-line-breaks property intact while blocking a subject with no blank line. This follows the archived drift-guard precedent that a guarantee worth having should not depend on the running model following prose; a refusing check rather than a rewriting one is what keeps the preserve-exact property.

Rewrite every consumer that today treats "any non-zero exit other than status `3`" as script failure or opens the manual fallback, so status `4` stays a structure refusal rather than a fallback or a drift confirmation: in `plugins/ai_dev/skills/git_commit/SKILL.md`, rewrite `<execute_commit>` so a status-`4` exit surfaces the problem and has the model recompose a subject-blank-body message and retry: keep `--accept-drift` when the failed invocation already carried it, do not newly add `--accept-drift`, and do not open `<fallback_on_script_failure>`; rewrite `<fallback_trigger>` and `<fallback_on_script_failure>` so status `4` is excluded from the fallback path the same way status `3` already is; and rewrite the trigger paragraph of `references/manual_fallback.md` so a status-`4` exit does not open the manual path. Mirror the second-line-non-empty refusal itself in `references/manual_fallback.md`'s manual commit steps so a fallback run applies the same check by hand.

Rewrite the eval harness passages that still encode the old run-on message shape so they expect the subject-blank-body form in place: in `tests/git_commit/evals/evals.json`, rewrite eval 2's `expected_output` and the expectation that names a summary sentence as the HEAD subject without separating a per-file body, and rewrite eval 4's expectation that names "one summary line followed by 'file -> change' lines", each to the subject-then-blank-line-then-per-file-body shape; in `tests/git_commit/README.md`, rewrite the eval-2 table cell that cites "Summary sentence + N \`file -> change\` lines" so it describes that same subject-plus-body form; in `tests/git_commit/evals/README.md`, rewrite the message-shape grading row that cites a "summary sentence" so it describes that same subject-plus-body form.

**Out of scope:**

- Wrapping or shortening the `file name -> concrete change` body lines to any column limit. Those lines are one per file by design and can be long; a body line-length policy is a per-repository linter choice rather than a git-format requirement, and this task changes only the subject-and-body structure.
- The staging, drift, context-consumption, and pre-flight behavior owned by the existing `ai-dev_git-commit-*` tasks; this task touches only message composition.

## Acceptance

- The `<message_policy>` block in `plugins/ai_dev/skills/git_commit/SKILL.md` names a blank line as the separator between the subject and the per-file body in its `<multi_file>` form: a grep for the separator wording returns it, where it returns nothing today.
- The old conflating wording is superseded: `grep -c "then list one line per changed file" plugins/ai_dev/skills/git_commit/SKILL.md` returns 0 after the rewrite, where it returns 1 today, and the block carries the subject-then-blank-line-then-body form instead.
- The prepare-context instruction is superseded: `grep -c "one concise summary sentence followed by one line per changed file" plugins/ai_dev/skills/git_commit/scripts/prepare_commit_context.sh` returns 0 after the rewrite, where it returns 1 today, and the `<commit_message_instruction>` carries the subject-then-blank-line-then-body form instead.
- The `<message_policy>` block instructs a subject line that is a short standalone summary with no trailing period, confirmed by reading the block.
- The `<single_file>` form in `<message_policy>` names its one `file name -> concrete change` line as the subject and keeps the message subject-only (no blank line, no body), confirmed by reading the block.
- The `<message_policy>` structure matches the `references/manual_fallback.md` heredoc template's `<subject line>` / blank line / `<body lines>` shape, confirmed by reading both.
- A message composed to the rewritten rules parses as subject plus body: build a two-file example message in the `<multi_file>` form, pipe it into `git commit -F -` in a throwaway scratch repository outside the tree, and confirm `git log -1 --format=%s` returns the subject alone and `git log -1 --format=%b` returns the per-file list. Record both outputs.
- `scripts/commit_with_message.sh` exits with status `4`, prints a stderr message naming the structure failure, commits nothing, stages nothing, and leaves the `CONTEXT_FILE` in place on a piped message whose second line is non-empty (the no-commit and `CONTEXT_FILE` retention match what `c9_foreign_drift_blocks` asserts for status `3`; stages-nothing is grounded by placing the status-`4` check ahead of `git add -A`, the same placement the script already uses for the status-`3` drift refusal); exits 0 on a message with a blank second line and on a one-line subject-only message; lists status `4` in its usage Exit status banner; and names the second-line-non-empty refusal in its Behavior section beside the existing exit-`1`/`2`/`3` refusals; a case added to `tests/git_commit/script_tests/run.sh` asserts the refuse path (exit `4`, stderr names the structure failure, no commit, no staging, `CONTEXT_FILE` retained) and both accept paths and passes under `tests/git_commit/run_all.sh`. Record the run output.
- `<execute_commit>` in `plugins/ai_dev/skills/git_commit/SKILL.md` treats status `4` as a message-structure refusal per the Approach's status-`4` recompose-and-retry flag rule (keep `--accept-drift` when already carried; never newly add it; never open `<fallback_on_script_failure>`), while status `3` remains the drift signal; confirmed by reading the block.
- `<fallback_trigger>` excludes status `4` (alongside status `3`) from the exits that open the fallback, confirmed by reading the block.
- `<fallback_on_script_failure>` excludes status `4` (alongside status `3`) as a non-failure refusal, confirmed by reading the block.
- `references/manual_fallback.md` trigger excludes status `4` (alongside status `3`) from opening the manual path, and the manual commit steps name the same second-line-non-empty refusal, confirmed by reading the file.
- Eval 2's old run-on wording is superseded: `grep -c "concise summary sentence on line 1, then one" tests/git_commit/evals/evals.json` returns 0 after the rewrite, where it returns 1 today, and the eval's `expected_output` / subject expectation carry the subject-then-blank-line-then-body form instead.
- Eval 4's old run-on wording is superseded: `grep -c "one summary line followed by 'file -> change' lines" tests/git_commit/evals/evals.json` returns 0 after the rewrite, where it returns 1 today, and the expectation carries the subject-then-blank-line-then-body form instead.
- The harness README eval-2 table cell is superseded: `grep -c "Summary sentence + N" tests/git_commit/README.md` returns 0 after the rewrite, where it returns 1 today, and the cell describes subject-plus-body grading instead.
- The eval README message-shape grading row is superseded: `grep -c "summary sentence" tests/git_commit/evals/README.md` returns 0 after the rewrite, where it returns 1 today, and the row describes subject-plus-body grading instead.
