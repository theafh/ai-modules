---
description: "Make git_auto_review restore and report any file its fixer writes outside the approved fixes and the run's .git_auto_review folder, and resolve the loose reproduction scripts in tests/."
scope: plugins/ai_dev/skills/git_auto_review
created: 2026-10-31T21:57:38
updated: 2026-10-31T23:09:55
status: open
reported-by: Andreas Hoffmann
---

# Catch stray fixer files in git_auto_review mechanically

## Goal

After a `git_auto_review` run, the working tree holds the change under review, the fixes the run approved, and the run's own ignored `.git_auto_review/` folder. Every other file the fixer writes shows up in the round's delta audit, the loop restores it together with any folder it created, and the run's records name it. A bundled script, script tests, and a behavioral eval carry that guarantee. The loose reproduction scripts under this repository's `tests/` tree become harness scenarios or are deleted.

## Context

Each round, `auto_fixer_git` writes a reproduction: a small script that fails before its fix and passes after it. The run keeps these scripts directly in its own folder, `.git_auto_review/<run-stem>/` (the skill calls that folder the relay), as `reproduction-r<round>-finding-<id>.<ext>` files beside `gate-r<round>.txt` and `ledger.txt`. That folder carries its own `.gitignore` with the single line `*`, and each new run clears it. The `<relay>` paragraph beginning "`reproduction-r<round>-finding-<id>.<ext>` holds the file reproduction" in `plugins/ai_dev/skills/git_auto_review/SKILL.md` states the rule.

The naming rule covers reproductions. Four parts of the loop decide whether any other fixer file gets caught, and each one is prose or a partial check today:

- **The round diff is orchestrator prose.** The `<relay>` paragraph beginning "`round-r<round>.diff.txt` holds the round's fixer-write diff" asks the orchestrator to diff "the round's pre-fix snapshot against the current working tree" with `diff -U0` and leaves the method to each run. Whether a new untracked file appears in that diff therefore depends on the run, and `auto_verifier_git`'s delta mode marks `unmapped` exactly what appears there.
- **Restore removes files and keeps their folders.** `scripts/run_restore.sh` deletes "the untracked files the fixer added that the copy does not contain" with `rm -f`, so a folder the fixer created stays on disk, empty, after a restore.
- **The unmapped-hunk evals stage a verifier verdict.** `retries_once_on_unmapped_hunk` and `stops_on_second_unmapped_hunk` in `tests/git_auto_review/evals/evals.json` tell the verifier through an environment note to mark one hunk `unmapped`, and their `grade.sh` arms check the delta mapping, the stop line, and `HEAD`. `tests/git_auto_review/evals/grade.sh` already reads one stage-time record (`.index.before`, through `index_unchanged`), which is the shape a stage-time list of untracked files can follow.
- **Loose reproduction scripts sit under `tests/`.** `git ls-files 'tests/*/script_tests/repro*'` lists reproduction scripts that earlier runs left in this repository, and each one runs only when someone calls it by hand.

`task_auto_check`'s `stray_hunk_reverted` eval in `tests/task_auto_check/evals/evals.json` is the in-repo precedent for planting a stray writer edit through an environment note and grading that the loop reverted it.

[The inert-worker grader task](tests_eval-graders-bite-on-inert-worker.md) also edits `tests/git_auto_review/evals/grade.sh` and adds a scenario to `tests/git_auto_review/script_tests/run.sh`. The two tasks add separate arms and scenarios, so whichever lands second adds its own beside the other's.

## Approach

1. **Script the round diff.** Add `scripts/run_round_diff.sh` beside the other bundled scripts. It takes `--stem`, `--round`, and `--root` like its siblings and uses their exit codes (`0` written, `1` usage error, `2` environment error). It rebuilds the round's pre-fix state from `pre-fix.patch` and `pre-fix.untracked.tar`, the same way the **Stop rule.**'s "Materialize and diff." case rebuilds the baseline. It then compares that state with the working tree over the paths `git status --porcelain --untracked-files=all` lists, the same non-ignored path set the snapshot, the concurrent-modification guard, and Restore read. It writes `round-r<round>.diff.txt` into the run's folder as a `diff -U0`, in which a file the fixer added appears as one whole-file addition and a file it deleted as one whole-file removal. Git ignores the run's `.git_auto_review/` folder, so the diff covers the working tree around it.
2. **Point the skill at the script.** Rewrite the `<relay>` paragraph beginning "`round-r<round>.diff.txt` holds the round's fixer-write diff" so the orchestrator writes that file by running `scripts/run_round_diff.sh`. Add the script to the signal list of `<agent_failure_policy>`'s `helper-script` class beside `scripts/run_snapshot.sh`. `<audit_delta>` keeps its restore-and-retry as it stands: a stray file now reaches delta mode as its own hunk, the verifier marks that hunk `unmapped`, and the existing retry and stop apply.
3. **Remove the folders Restore empties.** Extend the step in `scripts/run_restore.sh` that deletes fixer-added untracked files. After deleting each file, it also removes every parent folder the deletion left empty, up to and including the top-level folder under the repository root. Update the script's header comment and `--help` text, and the **Restore.** paragraph in `<snapshots>`, to say so.
4. **Plant a stray file in an eval.** Add `restores_stray_fixer_path` to `tests/git_auto_review/evals/evals.json`, with a fixture under `evals/fixtures/` and an arm in `grade.sh`, modelled on `stray_hunk_reverted` and on the pre-seeded shape of `retries_once_on_unmapped_hunk`. Its environment note makes round 1's fixer also write one extra file inside a new folder at the repository root, outside every approved `Fix:` path, and makes the retry write only the approved fix. Because the eval runs a restore-and-retry, add its id to `SERIAL_NESTED_LOOP_IDS` in `tests/git_auto_review/evals/run.py` and to the `git_auto_review` serial nested-loop list that `tests/CLAUDE.md` and `tests/AGENTS.md` both carry.
5. **Grade that the tree is clean after a run.** Have `evals/stage.sh` record the fixture's untracked, non-ignored files at stage time beside `.index.before`. Add a `grade.sh` helper that passes only when every untracked, non-ignored file after the run is in that record, is written by the eval's approved fix, or lies under a path the per-pass micro-deployment in `tests/lib/micro_deploy.py` writes into the sandbox project (on Cursor, the `auto_*_git` agent copies under `.cursor/agents/`), because those files land after stage time. Call the helper from every arm that calls `reproductions_in_relay` and from the new arm.
6. **Resolve the loose reproduction scripts.** For each file `git ls-files 'tests/*/script_tests/repro*'` lists, compare what it checks with its harness's `script_tests/run.sh` scenarios and eval grader arms. Turn a script whose check is that harness's only coverage of the behaviour into a scenario in that harness's `script_tests/run.sh`, then delete every listed file, so the command's output is empty.

**Out of scope:** Writes into paths the repository already ignores, since the round diff, the guard, and Restore all read the same non-ignored path list. A folder that was already completely empty before the round, which git and the snapshot both leave unrecorded.

## Acceptance

1. `bash tests/git_auto_review/run_all.sh` passes and includes a new scenario that stages a round whose fixer added an untracked file inside a new folder, edited a tracked file, and wrote a file into the run's `.git_auto_review/` folder. The scenario runs `scripts/run_round_diff.sh` and asserts that the diff's paths are exactly the added file, as one whole-file addition, and the tracked file, as its own hunk.
2. The same run includes a `scripts/run_restore.sh` scenario that stages a fixer-added file two folders deep under a new folder, restores, and asserts that both new folders are gone while a pre-fix untracked folder with content survives with that content.
3. `grep -n "run_round_diff.sh" plugins/ai_dev/skills/git_auto_review/SKILL.md` matches in the `<relay>` paragraph about `round-r<round>.diff.txt` and in `<agent_failure_policy>`, and that `<relay>` paragraph's one instruction for writing the file is to run the script.
4. `python3 tests/git_auto_review/evals/run.py restores_stray_fixer_path` grades PASS on the default vendor: the extra file and its folder are gone after the run, `verifier-r1.txt` records an `unmapped` mapping for a hunk on that path, the approved fix has landed, and `HEAD` is unchanged. An incomplete run is inconclusive under the standing repo rules, and a graded FAIL sends the work back to Approach step 1 or 2.
5. `grep -n "reproductions_in_relay" tests/git_auto_review/evals/grade.sh` lists arms that each also call the cleanliness helper, and running `tests/git_auto_review/evals/run.py` over those arms' eval ids grades every one PASS on the default vendor.
6. Grading the `fixes_in_scope_bug` fixture by hand after adding an untracked file at a new path at the repository root reports FAIL on the cleanliness line, which proves the helper catches a stray file.
7. `git ls-files 'tests/*/script_tests/repro*'` returns an empty list, and every harness's `script_tests/run.sh` that gained a scenario under Approach step 6 passes.
