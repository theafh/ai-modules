---
description: "Make the git_auto_review ignored-file manifest path-only and its set comparisons linear, so a large ignored build tree no longer forces a folder relocation."
scope: plugins/ai_dev/skills/git_auto_review
created: 2026-11-03T10:23:25
updated: 2026-11-03T10:23:25
status: open
reported-by: Andreas Hoffmann
---

# Make the git_auto_review ignored-file manifest path-only and its set checks linear

## Goal

`git_auto_review`'s snapshot, round-diff, and restore steps need one thing from the ignored files in a repository: the set of ignored paths that existed before the fix, so restore can delete ignored paths the fixer added and leave pre-existing ones alone. Today the loop also computes a content hash for every ignored file that no consumer reads, and it compares the before and after sets with a linear scan of the whole list for every candidate path. This task makes the manifest a path-only list and each comparison a single set operation, so a repository with a large ignored build tree (for example a Rust `target/` directory) runs the loop without reading every ignored file and without the scan cost that made relocating the build directory necessary.

## Context

- The manifest is `pre-fix.ignored.manifest`, declared in the `git_auto_review` skill's `<snapshots>` block and written under the run's relay directory.
- `plugins/ai_dev/skills/git_auto_review/scripts/run_snapshot.sh` builds it: `list_ignored` enumerates the ignored paths, `file_hash` hashes each file with `shasum` or `sha256sum`, and `write_ignored_manifest` writes a path record followed by a hash record. The script's own comment on the hash says "no consumer reads it".
- `scripts/run_round_diff.sh` and `scripts/run_restore.sh` read the manifest and discard the hash, and they decide membership with a rescan of the whole NUL list for each candidate path.
- `tests/git_auto_review/script_tests/run.sh` covers these scripts, including a scenario that stages a dangling symlink to prove an ignored path still records when it cannot be hashed.

## Approach

1. Make the manifest path-only. In `run_snapshot.sh`, drop `file_hash` and the hash record from `write_ignored_manifest`, so `pre-fix.ignored.manifest` is a NUL-delimited list of paths only.
2. Update both readers to expect the path-only shape: `collect_manifest_paths` in `run_round_diff.sh` and `manifest_paths` in `run_restore.sh`.
3. Replace the per-path rescans with a single set operation. Replace `list_contains` and `append_unique` in `run_round_diff.sh` and `member_listed` in `run_restore.sh` with a sorted list compared through `comm` (or bash associative arrays), and apply that at the three comparison sites: `collect_paths` and the main loop in `run_round_diff.sh`, and the ignored-file deletion step in `run_restore.sh`.
4. Update the skill text. In `git_auto_review/SKILL.md`, rewrite the `<snapshots>` `pre-fix.ignored.manifest` bullet to describe a path-only list, and reconcile the `<concurrent_modification_guard>` sentence that says the ignored set "stays bounded to the files a fixer could actually stray into" with a full set that is now cheap to compare.
5. Update the tests. In `tests/git_auto_review/script_tests/run.sh`, change the manifest scenario to assert the path-only record shape, and add a scenario that stages a synthetic ignored set of a few thousand paths and asserts that snapshot, round diff, and restore each complete within a generous wall-clock bound that the per-path rescan cannot meet.

**Out of scope:** Excluding build-cache directories such as `target/` or `node_modules/` from the ignored set. A path-only list plus a single set operation keeps the full set cheap, so a directory exclusion list would add a second mechanism for no gain.

## Acceptance

- `run_snapshot.sh` writes `pre-fix.ignored.manifest` as path-only records: a manifest built from one ignored file holds exactly that path as one NUL-delimited record and no following hash record.
- `run_snapshot.sh` carries no `shasum`, `sha256sum`, or `file_hash` invocation, so it never reads ignored file contents.
- `run_round_diff.sh` and `run_restore.sh` carry no per-path rescan of the full ignored list: `list_contains` and `member_listed` are gone and each comparison uses `comm` or an associative array.
- The bundled script tests pass through `./tests/git_auto_review/run_all.sh`, including the updated manifest scenario and the new scaling scenario.
- The scaling scenario stages 3,000 synthetic ignored paths and completes snapshot, round diff, and restore within 60 seconds; if it exceeds that bound, the comparison still scans per path and the item fails.
