---
description: Make git_review's size profile read diff --cc sections as files in every field, list binary and generated files by their git paths, and skip conflicted ---/+++ pairs, with script-test proof.
scope: plugins/ai_dev/skills/git_review
created: 2026-10-08T09:29:33
updated: 2026-10-17T13:50:32
status: open
reported-by: Andreas Hoffmann
---

# Read conflicted files as file sections in the git_review size profile and list every binary and generated file by its path

## Goal

The `git_review` evidence collector's size profile reads a `diff --cc` section as a file section in every field it writes to `size_profile.txt`. `git diff` writes such a section for each path whose content both sides of an unresolved merge changed (`UU`). After the change:

- `changed_files` counts each `diff --cc` section beside each `diff --git` section, so `binary_or_generated_share` divides by the full file count.
- `generated_files` and the `binary_or_generated_paths` listing match a conflicted file's path against the generated pattern exactly as they match an ordinary changed path.
- The listing names every binary and generated file by its path in the form `git diff --name-only` prints it, quoted where git quotes the name: a conflicted, an added, and a deleted binary alike.
- `added_lines` and `removed_lines` skip the `--- a/<path>` and `+++ b/<path>` header pair of each `diff --cc` section, as they already do for a `diff --git` section.
- Every ordinary `diff --git` section keeps counting and matching exactly as it does today, including a name with spaces and a name git quotes.

The user-visible outcome is that a review of a working tree with an unresolved merge conflict states a file count, a binary-or-generated share, a path listing, and line counts that include the conflicted files and leave out their header lines. A review in either mode also lists an added, deleted, or quoted binary under its own path.

## Context

`collect_size_profile` in `plugins/ai_dev/skills/git_review/scripts/collect_review_evidence.sh` reads one diff file as `$source`, `full_diff.txt` in range mode or `worktree_diff.txt` in uncommitted mode, and fills each field from it:

- `changed_files` counts the lines that match `^diff --git` followed by a space.
- `generated_files` counts the `diff --git` lines that match `GENERATED_PATTERN`.
- `binary_files` counts the lines that match `^Binary files |^GIT binary patch`.
- `binary_or_generated_share` divides the binary and generated sum by `changed_files`.
- `binary_or_generated_paths` takes each generated path from its `diff --git a/<path> b/...` line with `s/^diff --git a\///; s/ b\/.*$//`, and each binary path from its `Binary files` line with `s/^Binary files a\///; s/ and b\/.*$//`.
- `added_lines` and `removed_lines` come from one awk pass that treats a line starting with `---` or `+++` as a header only between a line starting with `diff --git` followed by a space and the file's first content line. [ai-dev_git-review-size-profile-overcount.md](archive/ai-dev_git-review-size-profile-overcount.md) introduced that pass and the script tests that prove it.

In uncommitted mode, `collect_uncommitted` writes the staged lane from `git diff --cached` and the unstaged lane from plain `git diff`. Every unmerged path shows in the staged lane only as `* Unmerged path <path>`. For a `UU` path, the unstaged lane holds a combined diff that opens with `diff --cc <path>`, a path with no `a/` or `b/` prefix. A conflicted text file follows with an `index` line, the `--- a/<path>` and `+++ b/<path>` pair, and hunks under `@@@` headers, while a conflicted binary follows with a bare `Binary files differ` line. A modify/delete conflict (`UD` or `DU`) shows as `* Unmerged path <path>` in the unstaged lane too, with no section and no lines. A file the merge applied cleanly lands in the staged lane as an ordinary `diff --git` section. Range mode diffs `"$BASE...$HEAD_REF"`, which never yields a combined diff.

Git quotes a name with non-ASCII characters in every opener and header form: `diff --git "a/\303\266.bin" "b/\303\266.bin"`, `diff --cc "vendor/\303\244.txt"`, `--- "a/<path>"`, and `Binary files "a/\303\266.bin" and /dev/null differ`. A name with spaces stays unquoted, as in `diff --git a/my file.bin b/my file.bin`. Today's `^diff --git` (space) count includes quoted openers and spaced names alike.

Four defects follow, all in `collect_size_profile`:

- Every field keyed on `diff --git` skips a conflicted file. The line counts read its header pair as one removed and one added content line, unless the section before it left the header window open, as a binary section does, in which case the pair is skipped by accident.
- `GENERATED_PATTERN`'s directory entries (`/vendor/`, `/node_modules/`, `/dist/`) find a top-level directory through the slash that the `a/` prefix puts before it, so a `diff --cc vendor/lib.txt` line matches none of them.
- The binary-path sed handles only the modified form `Binary files a/<path> and b/<path> differ`. It lists `Binary files differ` for a conflicted binary, `Binary files /dev/null` for an added one (`Binary files /dev/null and b/<path> differ`), `<path> and /dev/null differ` for a deleted one (`Binary files a/<path> and /dev/null differ`), and the whole `Binary files` line for a quoted name. The range diff and the staged lane write the same `Binary files` forms, so the listing fails the same way in both modes.
- The generated-path sed lists a quoted generated path as its whole `diff --git` line.

As an illustration, a merge that applies one text file cleanly and leaves a text file, a top-level `vendor/` text file, and a binary unmerged produces `changed_files: 1`, `generated_files: 0`, a 100% share, 11 added and 2 removed lines where `git diff --numstat HEAD` sums to 9 and 0, and `Binary files differ` as a listed path.

Each line of a combined hunk carries one prefix column per parent, and the line counter reads only the first column, which compares against `HEAD`. `--cc` also drops every hunk where the merge took one side unchanged. So the corrected count for a conflicted text file equals `git diff --numstat HEAD -- <path>` exactly when its `diff --cc` section drops no hunk, as with a file whose only change is one conflict hunk.

[ai-dev_git-review-secret-scan-gaps.md](ai-dev_git-review-secret-scan-gaps.md) plans to move the line counter's header rule into one helper that `collect_size_profile` and `collect_secret_scan` share, and it owns the extraction and patterns in `collect_secret_scan`.

The script tests live in `tests/git_review/script_tests/run.sh` and run through `./tests/git_review/run_all.sh`. Repository scenarios stage a sandbox under `script_tests/scratch/<id>/`, call the collector through `collect`, and are registered with `scenario <id> "<description>" <function>`. The helpers `profile_value` and `sum_numstat_text` read a `size_profile.txt` value and sum a numstat listing while skipping binary rows. `s11_uncommitted_mode_reports_both_lanes` covers the three uncommitted lanes on a tree without a conflict, and `s24_size_profile_line_counts_match_numstat` covers the range-mode line counts with one modified binary.

## Approach

Rewrite `collect_size_profile` so every field reads one normalised copy of `$source`:

- **Normalised copy.** Write `$source` to a dot-file under `$OUT` with each `diff --cc` opener rewritten into the `diff --git` form and every other line unchanged, and remove the copy before the function returns, as `collect_secret_scan` does with `$OUT/.added_lines`. A quoted path keeps git's quotes. One shape is this sed:

  ```bash
  sed -E -e 's#^diff --cc "(.*)"$#diff --git "a/\1" "b/\1"#' -e 't' \
      -e 's#^diff --cc (.*)$#diff --git a/\1 b/\1#'
  ```

  The existing `changed_files`, `generated_files`, `binary_files`, and line-count computations then cover conflicted sections unchanged, and the share follows from the corrected counts. When the shared header helper from the secret-scan task already exists, pass it the normalised copy. The collector runs `git diff` without `-c`, so `diff --combined` never appears and the rewrite leaves it out.
- **Listed paths.** Derive both listings from the opener lines. Take each generated path, and each binary path, from the opener of the section it belongs to, which replaces both listing seds and the parsing of the `Binary files` line. Every opener sets the current path, so no section inherits the previous one's. The extraction keeps a quoted name in git's quoted form, strips the `a/` prefix from an unquoted name, and cuts it at the space-prefixed `b/` or space-and-quote-prefixed `"b/` that starts the second path, which keeps a name with spaces whole. One shape is an awk pass over the normalised copy, run with the pattern in the environment so awk applies no escape processing to it:

  ```awk
  /^diff --git / {
      path = $0
      sub(/^diff --git /, "", path)
      if (path ~ /^"a\//) { sub(/^"a\//, "\"", path); sub(/" .*$/, "\"", path) }
      else { sub(/^a\//, "", path); sub(/ "?b\/.*$/, "", path) }
      if ($0 ~ ENVIRON["GENERATED_PATTERN"]) print path
  }
  /^Binary files / { print path }
  ```

Prove the change in `tests/git_review/script_tests/run.sh` with a new uncommitted-mode scenario, registered under the next free `s<N>` id with its own sandbox. Its fixture runs `git merge` between two branches so that one text file merges cleanly while three paths stay unmerged, then stages one added binary and the deletion of one more binary:

- **A conflicted text file** with exactly one conflict hunk and no other change, so its `diff --cc` section drops no hunk.
- **A conflicted text file with a non-ASCII name under a top-level `vendor/` directory**, shaped the same way. Git quotes its `diff --cc` opener, so it fails a rewrite that drops the quotes or a generated match that skips the `a/` prefix.
- **A conflicted binary with a space in its name**, which fails an extraction that splits the name at the space.
- **The staged added binary, and the staged deletion of a binary with a non-ASCII name.** They carry the two `Binary files` forms with `/dev/null`, and the quoted deletion fails a count or an extraction that drops quoted names.

The fixture leaves no untracked file and gives no path both a staged and an unstaged change, so each changed path forms exactly one section. Each assertion computes its expected value in the sandbox wherever git can supply it, so the test pins no line count.

Extend `s24_size_profile_line_counts_match_numstat` so its feature branch also adds one binary file and deletes another. The range diff then carries all three `Binary files` forms, and the scenario's `binary_files: 1` check becomes `binary_files: 3` because its fixture grows, not because any property weakens.

Keep the `git_review/` entries in `tests/README.md` and `tests/CLAUDE.md` current with the added coverage, per the standing testing rules.

**Out of scope:**

- Modify/delete conflicts (`UD`, `DU`), which carry no section to read; counting them would mean de-duplicating `* Unmerged path` lines across the two lanes.
- Equality with `git diff --numstat HEAD` for a conflicted file whose `diff --cc` section drops cleanly merged hunks, since the counts describe the diff the collector wrote.
- Counting a path once when it carries both a staged and an unstaged change, since `changed_files` keeps counting sections.

## Acceptance

- Every size-profile field in `collect_size_profile` reads a copy of `$source` in which each `diff --cc` opener is rewritten into the `diff --git` form and every other line is unchanged, and both listings take each path from its section's opener.
- The new scenario passes and asserts that `changed_files` equals the number of paths `git status --porcelain` lists in its sandbox.
- The new scenario asserts that `added_lines` and `removed_lines` equal the added and removed sums of `git diff --numstat HEAD` in its sandbox, skipping the `-` rows that numstat prints for binary files.
- The new scenario asserts `generated_files: 1` and `binary_files: 3`, the counts its one top-level `vendor/` path and its three binary paths fix by construction.
- The new scenario asserts that `binary_or_generated_share` equals `(binary_files + generated_files) * 100 / changed_files`, computed from the profile's own values.
- The new scenario asserts that `binary_or_generated_paths` holds exactly the `vendor/` file and the three binary files, each in the form `git diff --name-only` prints it in the sandbox, and no entry that starts with `Binary files` or ends in `differ`.
- The new scenario asserts that `worktree_diff.txt` holds a `diff --cc` line for each path `git diff --name-only --diff-filter=U` lists in its sandbox, each conflicted text file's `---` and `+++` header lines, and the bare `Binary files differ` line, and that the evidence directory holds no dot-file once the collector returns.
- Run against the collector as committed before this task, the new scenario fails its `changed_files`, line-count, `generated_files`, share, and listing assertions.
- The extended `s24` passes, asserts `binary_files: 3` in place of its `binary_files: 1` check, and asserts that `binary_or_generated_paths` names its three binary files as `git diff --name-only main...feature` prints them, with no entry that starts with `Binary files` or ends in `differ`. Its listing assertion fails against the collector as committed before this task.
- The `git_review/` entry in `tests/README.md` states a scenario count equal to the number of `scenario` registrations in `script_tests/run.sh`, and both that entry and the `git_review/` row in `tests/CLAUDE.md` name conflicted files and the binary-path listing among the size-profile coverage.
