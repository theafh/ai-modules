---
description: Make git_review's size profile count content lines only (numstat-equal in range and uncommitted), prove via a new range scenario plus s11/s22, and keep tests/README.md and tests/CLAUDE.md current.
scope: plugins/ai_dev/skills/git_review
created: 2026-10-06T13:09:42
updated: 2026-10-18T15:42:34
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Count only content lines in the git_review size profile, prove it in script tests, and keep harness docs current

## Goal

The `git_review` evidence collector writes `added_lines` and `removed_lines` to `size_profile.txt` as the number of added and removed content lines in the diff it collected, so both values equal the sums `git diff --numstat` reports for the same changes. That holds in range mode, including the per-path fallback that runs when one blob is unreadable, and in uncommitted mode, where the counted diff spans the staged, unstaged, and untracked lanes. The user-visible outcome is that the diff size a review report states matches git's own count, where today it runs one line high on each side for every file with a text hunk.

This task is the point-fix for the two line counts that `collect_size_profile` writes.

## Context

`collect_size_profile` in `plugins/ai_dev/skills/git_review/scripts/collect_review_evidence.sh` reads one diff file as `$source`: `full_diff.txt` in range mode, or `worktree_diff.txt` when that file is absent, which is the uncommitted mode. It derives `changed_files`, `binary_files`, and `generated_files` from the file's `diff --git` and binary markers, and it computes the two line counts with `count_matches '^\+'` and `count_matches '^-'`. Those patterns also match the header pair that opens each file's hunks (`--- a/<path>` or `--- /dev/null`, then `+++ b/<path>` or `+++ /dev/null`), so every file section that carries the pair adds one to each count. A pure rename, a mode-only change, and a binary file carry no header pair and add nothing. On a 20-file pull request the profile reported 576 added and 37 removed lines while `git diff --numstat` summed to 556 and 17, exactly 20 apart on each side.

Two producers write the counted file, and their shapes matter for the fix:

- **Range mode.** `collect_range` writes `full_diff.txt` with `git diff -M --find-renames "$BASE...$HEAD_REF"`. When that whole-range diff fails because a blob is missing, `collect_range_diffs_per_path` appends the diff of every readable path to the same file instead. A whole-range `git diff --numstat` fails in that case too, while the numstat of each readable path still succeeds, as the `unreadable_path` eval fixture shows.
- **Uncommitted mode.** `collect_uncommitted` writes `worktree_diff.txt` as three lanes under `### staged`, `### unstaged`, and `### untracked` marker lines. Each untracked file gets a synthesized `diff --git`, `--- /dev/null`, `+++ b/<path>` header followed by every line of the file prefixed with `+`, and no `@@` hunk header.

The skill's `<lead>` tag tells the report to state the diff size from `size_profile.txt`, and `references/report_template.md` renders it as "`<a>` added and `<r>` removed lines". The manual fallback in `references/manual_fallback.md`, under "The diff size and the binary and generated share:", already takes the size from `git diff --stat`, so it reports git's own counts and stays as it is. The eval grader's size check in `tests/git_review/evals/grade.sh`, labelled "the diff size or share is stated", matches a share or a changed-file count, so no eval reads the line counts.

The script tests live in `tests/git_review/script_tests/run.sh` and run through `./tests/git_review/run_all.sh`. Repository scenarios stage a sandbox under `script_tests/scratch/<id>/`, usually through `fresh_repo`, call the collector through `collect`, and are registered in the run block with `scenario <id> "<description>" <function>`. `s10_size_profile_counts_generated_files` asserts the file counts and the generated path but no line count, `s11_uncommitted_mode_reports_both_lanes` stages all three uncommitted lanes but reads nothing from `size_profile.txt`, and `s22_unreadable_path_records_unread_remainder` stages the `unreadable_path` fixture.

## Approach

Rewrite the `added_lines` and `removed_lines` computation in `collect_size_profile` so it counts the content lines of `$source` and skips each file's header pair. Count over the diff file the collector wrote, because that file already holds the per-path fallback's readable paths and the uncommitted mode's untracked lane, and a single `git diff --numstat` call reproduces neither. The counts then describe exactly the diff the review reads, in every mode, through one code path.

Treat a line that starts with `---` or `+++` as a header only between a file's `diff --git` line and its first content line. A filter that drops every line matching `'^--- '` or `'^\+\+\+ '` miscounts content, because removing the SQL comment `-- note` shows in the diff as `--- note`, and adding the line `++ x` shows as `+++ x`. One shape that settles both cases, including the untracked lane's hunk-less sections, is a POSIX awk pass over `$source`:

```awk
/^diff --git / { hdr = 1; next }
hdr && /^--- / { next }
hdr && /^\+\+\+ / { hdr = 0; next }
/^@@/ { hdr = 0; next }
/^\+/ { added++ }
/^-/ { removed++ }
```

Prove the counts in `tests/git_review/script_tests/run.sh` with three changes:

- **A new range-mode scenario**, registered under the next free `s<N>` id with its own sandbox. Its feature branch modifies, adds, and deletes text files, renames one file without changing it, modifies one binary file, removes a content line such as the SQL comment `-- note`, and adds a content line such as `++ x`.
- **An extension of `s11_uncommitted_mode_reports_both_lanes`** that reads `size_profile.txt` from the sandbox it already stages.
- **An extension of `s22_unreadable_path_records_unread_remainder`** that reads `size_profile.txt` from the per-path fallback run it already makes.

Each assertion computes its expected values in its own sandbox, so the test pins no count. Keep the `git_review/` entries in `tests/README.md` and `tests/CLAUDE.md` current with the added coverage, per the standing testing rules.

**Out of scope:** the added-line filter and the patterns in `collect_secret_scan`, which [ai-dev_git-review-secret-scan-gaps.md](ai-dev_git-review-secret-scan-gaps.md) owns.

## Acceptance

- A search of `collect_review_evidence.sh` for `count_matches '^\+'` and `count_matches '^-'` returns no match, and `collect_size_profile` computes `added_lines` and `removed_lines` from `$source` with a header-aware count.
- The new range-mode scenario passes and asserts that `added_lines` and `removed_lines` equal the added and removed sums of `git diff --numstat -M main...feature` in its sandbox, skipping the `-` rows that numstat prints for binary files. The sandbox feature branch used for that assertion includes the Approach-named text modify/add/delete, rename-without-content-change, and modified-binary edits.
- The same scenario asserts that its `full_diff.txt` holds the removed comment and the added line as hunk lines that start with `---` and `+++`, so its fixture keeps the power to fail both a header-inclusive count and a plain `grep -v` filter.
- The extended `s11` passes and asserts that the two counts equal the sums of `git diff --cached --numstat` and `git diff --numstat` plus the line count of each untracked file, all read in its sandbox.
- The extended `s22` passes and asserts that the two counts equal the numstat sums over the changed paths the collector read, which leaves out every path listed in `unread_paths.txt`.
- The `git_review/` entry in `tests/README.md` states a scenario count equal to the number of `scenario` registrations in `script_tests/run.sh`, and both that entry and the `git_review/` row in `tests/CLAUDE.md` name the size-profile line counts among the covered behaviours.
