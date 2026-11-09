---
description: Restage the git_review deep_file_defect fixture as a whole-file diff with an unannounced tail defect, so eval 18 passes only for a run that reads the entire changed file.
scope: tests/git_review
created: 2026-10-02T08:23:20Z
updated: 2026-10-03T16:45:09Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Make the git_review long-file eval prove a whole-file read

## Goal

Eval 18 in the `git_review` harness passes only for a run that reads the whole changed file, which is what the parent task's long-file acceptance item claims it proves. The fixture's diff spans a file several thousand lines long, the only defect sits in the last hunk, and nothing in the file announces it. The run then takes the large-diff branch of the skill's `<scale_the_reading>` rule, "read the whole file, sample nothing, and trust no comment or docstring", and a run that samples the diff misses the defect.

## Context

The parent long-file acceptance item Goal refers to is in `tasks/archive/ai-dev_git-review-skill.md` and begins `On a fixture whose diff includes a defect near the end of a file several thousand lines long`.

The fixture `tests/git_review/evals/fixtures/deep_file_defect/setup.sh` writes the same helper block on the base and the branch through `plant_long_file` in `tests/git_review/evals/fixtures/_common.sh`, then appends a `summarize()` function whose body carries `# Defect: an empty list divides by zero here rather than returning 0.`. The resulting diff is about ten lines, so finding the defect proves the diff was read, not the file, and the comment names the defect outright. The `18)` case in `tests/git_review/evals/grade.sh` checks for `summarize`, a zero or empty mention, and `closing_answer_is yes`.

`tests/git_review/RUNBOOK.md` already notes under its timeouts heading that this fixture is long by design and that the runner's default per-eval timeout is 600 seconds. The runner is vendor-aware; fresh proof and timing runs use `--vendor cursor` per `TESTING.md`.

## Approach

Rewrite the branch side of the fixture so every helper changes, for example by renaming each `helper_N` or changing each body's arithmetic. The diff then spans the whole file, and the skill's large-diff branch applies. Put the only defect in the final hunk as a `summarize()` that divides by `len(values)` without an empty-input guard, and give it no comment or docstring that names the defect. Keep that function named `summarize` so the existing eval-18 grader needle and `evals.json` expectation stay valid without editing `grade.sh` or expectations. Keep every other changed helper correct, so the defect is the one finding a whole read surfaces. Rewrite the branch commit message in place so it no longer under-claims the change as `src/helpers.py -> add a summarize helper at the end of the module`.

Size the file so a fresh Cursor run finishes well inside the default timeout. When a run comes close, lower the helper count while keeping the file several thousand lines long. Record the measured duration in the RUNBOOK timeout note, rewriting that note in place. Rewrite in place eval 18's `expected_output` in `tests/git_review/evals/evals.json` so it states the whole-file-diff, unannounced-tail-defect proof with a count-stable several-thousand-line size claim and no fixed line count such as 4800, and rewrite the eval 18 entry and the `deep_file_defect` fixture row in `tests/git_review/evals/README.md` to match.

## Acceptance

- In a staged `deep_file_defect` sandbox, the three-dot diff stat for `src/helpers.py` shows several thousand changed lines, and the defect sits in the last hunk.
- On the staged branch's `src/helpers.py`, a mechanical scan shows the only empty-list division hazard is inside `summarize()`; every other changed helper body contains no such hazard.
- A case-insensitive search of the staged branch's `src/helpers.py` for `defect`, `bug`, and `divides by zero` returns no match.
- Eval 18 passes on a fresh `python3 tests/git_review/evals/run.py --vendor cursor 18` run, and that run's `timing.json` duration stays under the runner's default timeout. When that run times out, resize the fixture per Approach. When that run grades as a miss, fix the fixture or the skill rather than loosen the check, per `TESTING.md` **Test Integrity**.
- The RUNBOOK timeout note states the measured duration for the rewritten fixture in place of the prior 4800-line description.
- Eval 18's `expected_output` in `tests/git_review/evals/evals.json` states the whole-file-diff, unannounced-tail-defect proof with a several-thousand-line size claim and contains no fixed line count such as 4800.
- The `deep_file_defect` fixture table row in `tests/git_review/evals/README.md` describes a whole-file diff spanning several thousand lines with the only defect in the final hunk, and no longer describes a ~4800-line file whose defect lives only in a short appended tail.
- The `### 18: deep_file_defect` entry in `tests/git_review/evals/README.md` states that the eval proves a whole-file read of an unannounced tail defect under a large whole-file diff, and no longer claims a short appended-tail defect on an otherwise unchanged long file.
- The branch commit message in `tests/git_review/evals/fixtures/deep_file_defect/setup.sh` no longer reads `src/helpers.py -> add a summarize helper at the end of the module` and instead describes the whole-file helper rewrite.
