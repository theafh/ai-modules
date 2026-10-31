---
description: "Make git_auto_review catch any fixer write outside the approved fix paths and the relay: a scripted round diff, restore that clears emptied dirs, a stray-path eval, and orphan repro cleanup."
scope: plugins/ai_dev/skills/git_auto_review
created: 2026-10-31T21:57:38
updated: 2026-10-31T21:57:38
status: open
reported-by: Andreas Hoffmann
---

# Catch stray fixer paths in git_auto_review mechanically

## Goal

A `git_auto_review` run leaves the user's tree holding only the change under review, the fixes the run approved, and the ignored `.git_auto_review/` relay. Any other path the fixer creates or edits reaches the round's delta audit as a hunk, is restored away together with any directory it created, and is named in the run's records, so a run never again leaves a stray directory such as a repository-root `repro/` behind. That guarantee rests on a bundled script, script tests, and a behavioral eval rather than on agent prose alone, and the orphan reproductions earlier runs committed into this repository are resolved.

## Context

Earlier runs left reproduction scripts wherever each run chose: a repository-root `repro/auto-review-r<round>/` directory in one project, and harness `script_tests/` directories in this repository, where a full-tree commit swept them into history. The cause was a fixer rule that asked for "a path of its own" without naming one. That location is now settled: `auto_fixer_git` writes every file reproduction into the stem's `repro/` directory, `scripts/run_relay.sh` creates that directory at init, and the paragraph beginning "`repro/` holds every file reproduction" in the `<relay>` block of `plugins/ai_dev/skills/git_auto_review/SKILL.md` documents it.

The catch for any other stray write still rests on prose or is missing:

- **The round diff is orchestrator prose.** The `<relay>` paragraph beginning "`round-r<round>.diff.txt` holds the round's fixer-write diff" asks the orchestrator to diff "the round's pre-fix snapshot against the current working tree" with `diff -U0`, but no script builds that diff. Whether a new untracked file shows up as a hunk therefore depends on how each run's orchestrator materializes the snapshot, and `auto_verifier_git`'s delta mode can mark `unmapped` only what reaches the diff.
- **Restore leaves emptied directories.** `scripts/run_restore.sh` removes "the untracked files the fixer added that the copy does not contain" with `rm -f`, so a directory the fixer created stays on disk, empty, after a restore.
- **No eval stages a stray path.** `retries_once_on_unmapped_hunk` and `stops_on_second_unmapped_hunk` in `tests/git_auto_review/evals/evals.json` stage an unmapped hunk through an environment note without any new untracked path, and no grader checks a run's tree for untracked paths beyond the fixture's own change. `tests/git_auto_review/evals/grade.sh` already reads a stage-time record for the index (`.index.before`, read by `index_unchanged`), which is the shape a pre-run untracked record follows.
- **Orphan reproductions are tracked here.** `git ls-files 'tests/*/script_tests/repro*'` lists the reproduction scripts earlier runs left in this repository, and no runner, Makefile target, or doc invokes any of them.

`task_auto_check`'s `stray_hunk_reverted` eval in `tests/task_auto_check/evals/evals.json` is the in-repo precedent for staging a stray writer edit through an environment note and grading that the loop reverted it.

[The inert-worker grader task](tests_eval-graders-bite-on-inert-worker.md) also edits `tests/git_auto_review/evals/grade.sh` and appends a scenario to `tests/git_auto_review/script_tests/run.sh`; both tasks add independent arms and scenarios, so whichever lands second appends its own beside the other's.

## Approach

1. **Script the round diff.** Add `scripts/run_round_diff.sh` beside the other bundled scripts, taking `--stem`, `--round`, and `--root` the way its siblings do and following their exit-code convention (`0` written, `1` usage, `2` environment). It materializes the round's pre-fix state from `pre-fix.patch` and `pre-fix.untracked.tar` the way the **Stop rule.**'s "Materialize and diff." case materializes the baseline, compares it with the working tree over the non-ignored path set that `git status --porcelain --untracked-files=all` enumerates (the set the snapshot, the concurrent-modification guard, and Restore already share), and writes `round-r<round>.diff.txt` under the stem as a `diff -U0` in which a fixer-added file is one whole-file addition and a fixer-deleted file is one whole-file removal. The relay stays out of the diff because the relay's own `.gitignore` keeps it out of that path set.
2. **Point the skill at the script.** Rewrite the `<relay>` paragraph beginning "`round-r<round>.diff.txt` holds the round's fixer-write diff" so the orchestrator writes that file by running `scripts/run_round_diff.sh`, and add the script to the signal list of `<agent_failure_policy>`'s `helper-script` class beside `scripts/run_snapshot.sh`. `<audit_delta>` keeps its restore-and-retry unchanged: a stray path now reaches delta mode as a hunk that maps to no approved finding id, so the verifier marks it `unmapped` and the existing retry and stop apply.
3. **Remove the directories Restore empties.** Extend the step in `scripts/run_restore.sh` that deletes fixer-added untracked files so that, after deleting each file, it removes every ancestor directory the deletion left empty, stopping below the repository root. Update the script's header comment and `--help` text, and the **Restore.** paragraph in `<snapshots>`, to say so.
4. **Stage a stray path in an eval.** Add `restores_stray_fixer_path` to `tests/git_auto_review/evals/evals.json` with a fixture under `evals/fixtures/` and an arm in `grade.sh`, modelled on `stray_hunk_reverted` and on the pre-seeded shape of `retries_once_on_unmapped_hunk`. Its environment note makes round 1's fixer also write one extra file inside a new repository-root directory outside every approved `Fix:` path, and makes the retry write only the approved fix. Because the eval runs a restore-and-retry, add its id to `SERIAL_NESTED_LOOP_IDS` in `tests/git_auto_review/evals/run.py` and to the `git_auto_review` serial nested-loop list that `tests/CLAUDE.md` and `tests/AGENTS.md` both carry.
5. **Grade post-run cleanliness.** Have `evals/stage.sh` record the fixture's untracked non-ignored paths at stage time beside `.index.before`, and add a `grade.sh` helper that passes only when every untracked non-ignored path after the run appears in that record, is a path the eval's approved fix writes, or sits under a path the per-pass micro-deployment in `tests/lib/micro_deploy.py` writes into the sandbox project (on Cursor, the `auto_*_git` agent copies under `.cursor/agents/`), because those land after stage time. Call it from every arm that calls `reproductions_in_relay` and from the new arm.
6. **Resolve the orphan reproductions.** For each file `git ls-files 'tests/*/script_tests/repro*'` lists, compare the behaviour it reproduces with that harness's `script_tests/run.sh` scenarios and eval grader arms. Turn a reproduction whose behaviour nothing else pins into a scenario in that harness's `script_tests/run.sh`, and delete every listed file, so the selector lists nothing afterwards.

**Out of scope:** Detecting writes into paths the repository already ignores, since the round diff, the guard, and Restore all read the same non-ignored path set. Preserving a directory that was completely empty before the round, which neither git nor the snapshot records. Removing stray reproduction directories that earlier runs left in other repositories, which each repository's owner deletes.

## Acceptance

1. `bash tests/git_auto_review/run_all.sh` passes, and it includes a new scenario that stages a round whose fixer added an untracked file inside a new directory, edited a tracked file, and wrote a relay file, runs `scripts/run_round_diff.sh`, and asserts the diff carries the added file as one whole-file addition and the tracked edit as its own hunk, and carries no `.git_auto_review/` path.
2. The same run includes a `scripts/run_restore.sh` scenario that stages a fixer-added file two directories deep under a new directory, restores, and asserts that both new directories are gone while a pre-fix untracked directory with content survives with its content.
3. `grep -n "run_round_diff.sh" plugins/ai_dev/skills/git_auto_review/SKILL.md` matches in the `<relay>` paragraph about `round-r<round>.diff.txt` and in `<agent_failure_policy>`, and that `<relay>` paragraph no longer tells the orchestrator to compose the diff itself.
4. `python3 tests/git_auto_review/evals/run.py restores_stray_fixer_path` grades PASS on the default vendor: the extra file and its directory are absent after the run, `verifier-r1.txt` records an `unmapped` mapping for a hunk on that path, the approved fix is landed, and `HEAD` is unchanged. An incomplete run is inconclusive under the standing repo rules, and a graded FAIL sends the work back to Approach step 1 or 2.
5. `grep -n "reproductions_in_relay" tests/git_auto_review/evals/grade.sh` lists arms that each also call the cleanliness helper, and running `tests/git_auto_review/evals/run.py` over the eval ids of those arms grades every one PASS on the default vendor.
6. Grading the `fixes_in_scope_bug` fixture by hand after adding an untracked file at a new repository-root path reports FAIL on the cleanliness line, which proves the helper bites.
7. `git ls-files 'tests/*/script_tests/repro*'` prints nothing, and every harness's `script_tests/run.sh` that gained a scenario under Approach step 6 passes.
