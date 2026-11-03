---
description: "Make the git_auto_review ignored-file manifest path-only and its set comparisons linear, so a large ignored build tree no longer forces a folder relocation."
scope: plugins/ai_dev/skills/git_auto_review
created: 2026-11-03T10:23:25
updated: 2026-11-03T14:41:43
status: ready
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
3. Replace the per-path rescans with a single set operation built in Python 3 over the NUL-delimited records, because `comm`, `join`, and `grep -z` have no NUL mode on this host and `declare -A` sits above the bash 3.2 floor these scripts hold. Python 3 is the charter's accepted standing dependency, and `run_round_diff.sh` already requires it. Replace `list_contains` in `run_round_diff.sh` and `member_listed` in `run_restore.sh` with a Python `set` built once per list, and replace `append_unique` in `collect_paths` with a raw append followed by one `sort -z -u` dedupe after collection. Apply the set comparison at all four comparison sites: the main loop in `run_round_diff.sh`, the untracked-deletion test that calls `member_listed "$members" "$current"` in `run_restore.sh`, and the ignored-file deletion loop's two tests that call `member_listed "$manifest_members" "$ignored"` and `member_listed "$members" "$ignored"`. Add the `command -v python3` startup check `run_round_diff.sh` already carries to `run_restore.sh`; `run_snapshot.sh` compares nothing and needs no check.
4. Update every passage that states the old path-plus-hash shape, rewriting each one in place so no copy of the old shape survives beside the new statement. In `git_auto_review/SKILL.md`, rewrite the `<snapshots>` `pre-fix.ignored.manifest` bullet to describe a path-only list, keeping its exclusion sentences verbatim because that bullet is the one statement of the harness run-output trees, and rewrite the relay listing's `pre-fix.ignored.manifest` line that reads "path plus hash". In `scripts/run_snapshot.sh`, rewrite the header comment that reads "as NUL-delimited path-plus-content-hash records", the `--help` text, and the `write_ignored_manifest` comment from "path-plus-content-hash records" to the path-only shape. In `scripts/run_restore.sh`, rewrite the `manifest_paths` comment that reads "The manifest alternates a path record with its content-hash record" to describe the path-only list. Leave the `<concurrent_modification_guard>` sentence that says the ignored set "stays bounded to the files a fixer could actually stray into" unchanged, because this task changes comparison cost and neither membership nor exclusion, so the claim stays true.
5. Update the tests. In `tests/git_auto_review/script_tests/run.sh`, change the manifest scenario to assert the path-only record shape, add a scaling scenario over the fixed 3,000 synthetic ignored paths that asserts each step's bound, and record the pre-change and post-change timings those bounds read in `tests/git_auto_review/RUNBOOK.md`, as `## Acceptance` item 5 specifies.

**Out of scope:** Excluding build-cache directories such as `target/` or `node_modules/` from the ignored set. A path-only list plus a single set operation keeps the full set cheap, so a directory exclusion list would add a second mechanism for no gain.

## Acceptance

- `run_snapshot.sh` writes `pre-fix.ignored.manifest` as path-only records: a manifest built from one ignored file holds exactly that path as one NUL-delimited record and no following hash record.
- `run_snapshot.sh` carries no `shasum`, `sha256sum`, or `file_hash` invocation, so it never reads ignored file contents.
- `run_round_diff.sh` and `run_restore.sh` carry no per-path rescan of the full ignored list: a grep for `list_contains`, `append_unique`, and `member_listed` across both scripts returns no match, and each of the four comparison sites Approach item 3 names — the main loop in `run_round_diff.sh`, the step-4 untracked-deletion test, and both step-5 ignored-file tests in `run_restore.sh` — is one Python 3 `set` operation over the NUL-delimited records, while `collect_paths` dedupes once through `sort -z -u`. `run_restore.sh` carries the `command -v python3` startup check that `run_round_diff.sh` already has.
- The bundled script tests pass through `./tests/git_auto_review/run_all.sh`, including the updated manifest scenario and the new scaling scenario.
- The scaling scenario stages a fixed 3,000 synthetic ignored paths. Before any script change, `tests/git_auto_review/RUNBOOK.md` records three timed runs of each unmodified step (snapshot, round diff, restore) at that denominator, one timing of the existing per-path membership scan at 3,000 paths against 3,000 candidates, and three timed runs of each step after the change, every row carrying its date and the host's `bash --version`. Each step carries its own bound, set above that step's recorded post-change median by a stated margin and below the recorded single-scan timing, and the section states the median, the margin, and the chosen bound together. The snapshot bound proves the hash removal, and the round-diff and restore bounds prove the set operation. A step whose recorded median misses its bound fails the item and names the comparison site that still scans per path; a bound at or above the single-scan timing fails the item as non-discriminating however fast the runs measured.
- A grep for the old path-plus-hash wording returns no match in `SKILL.md`, `scripts/run_snapshot.sh`, `scripts/run_round_diff.sh`, and `scripts/run_restore.sh`: the phrases `path-plus-content-hash`, `path plus hash`, `content-hash record`, and `followed by its content hash` each return nothing.
