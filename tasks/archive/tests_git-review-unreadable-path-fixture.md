---
description: Restage the git_review unreadable_path fixture so one changed path's new content is unreachable through git, record unread paths in the collector, and grade eval 19 on it.
scope: tests/git_review
created: 2026-10-02T08:23:20Z
updated: 2026-10-03T17:46:16Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Make the git_review unreadable-path fixture unreadable to git

## Goal

Eval 19 in the `git_review` harness stages a branch with one changed path whose new content no git command and no file read can produce, while every other changed path stays readable. The evidence collector records that path as unread instead of returning an empty diff, and the report names it as the unread remainder and withholds the approvability verdict, as the skill's `<unread_remainder>` rule requires. The user-visible outcome: eval 19 fails for any run that reads the hidden content or calls the change approvable.

## Context

The fixture `tests/git_review/evals/fixtures/unreadable_path/setup.sh` updates `src/locked.py` with the line `secret_flag = True` and then runs `chmod 000 src/locked.py` on the working-tree copy. Git still serves the committed content through `git diff` and `git show`, so every recorded run quoted `secret_flag`, nothing was ever unread, and one older run called the change approvable. The `19)` case in `tests/git_review/evals/grade.sh` passes on the path name alone.

The collector `plugins/ai_dev/skills/git_review/scripts/collect_review_evidence.sh` writes the whole-range diff through `collect_range` and sends git's stderr to `/dev/null`. When one blob is missing, `git diff` fails for the whole range, so today the collector would write an empty `full_diff.txt` and the run would lose the readable paths too.

The harness runner is already vendor-aware. Fresh proof runs use `--vendor cursor` per `TESTING.md`.

## Approach

After the fixture has committed and pushed `widen` in `setup.sh`, set `uploadpack.allowFilter` true on `$target/origin.git` with `git -C "$target/origin.git" config uploadpack.allowFilter true`, then replace the full clone `init_remote_repo` left at `$target/repo` with a blobless partial clone that never checks out (`git clone --filter=blob:none --no-checkout "file://$target/origin.git" "$target/repo"`), leaving origin at that `file://` URL. Configure sparse-checkout of every path except `src/locked.py` before materializing `widen`, and never request that locked path so the clone does not fetch its blob. Read the new content of every other changed path once so those blobs are local. Resolve the `src/locked.py` blob OID from origin without fetching it into the clone, then delete that OID from both the clone and origin in loose and packed form so neither store can serve it and a later fetch cannot obtain it. Leave `src/locked.py` absent from the worktree through that sparse-checkout so a file read cannot produce the new content. Confirm that combined hide in the staged sandbox against the Acceptance git-command checks before grading anything on it.

Teach the collector to keep the evidence set complete when one path is unreadable. When the whole-range diff fails, diff the changed paths one at a time for `full_diff.txt`, `diff_stat.txt`, and the removed-lines view (`removed_hunks.txt`), keep every per-path result that succeeds, and write the paths git cannot produce to a new `unread_paths.txt` that `manifest.txt` lists. Rewrite the skill's `<evidence_set>` and the whole-range commands under `## Collect the Git Layer` in `references/manual_fallback.md` in place so those sites describe the same per-path retry and unread-path recording, including the `--stat` command that fills `diff_stat.txt`. Point the skill's `<unread_remainder>` at `unread_paths.txt`, so the report names those paths and withholds the approvability verdict. Add a script test for this path to `tests/git_review/script_tests/run.sh`, and rewrite the eval 19 entry and the `unreadable_path` fixture row in `tests/git_review/evals/README.md` in place. Rewrite `## The fixture that needs care` in `tests/git_review/RUNBOOK.md` in place so it describes the blobless/sparse hide and ordinary workspace removal, dropping the chmod-000 restore procedure.

Rewrite the `19)` case in `grade.sh` in place so it fails a response that contains `secret_flag`, fails a response that names `src/locked.py` without unread language, grades unread beside that path, and fails a response that calls the change approvable while that path is unread, replacing the current `attest` line with a check whose needle still passes when the report withholds approvability. The shipped collector and `SKILL.md` change under the standing repo rules for versioning and registration.

## Acceptance

- In a staged `unreadable_path` sandbox, `git show <head>:src/locked.py` and `git diff <base>...<head> -- src/locked.py` both fail, `git show <head>:src/readable.py` succeeds, and `git fetch --all` exits 0.
- In that staged sandbox, `src/locked.py` is absent (`test ! -e src/locked.py`), and a file read of that path does not yield the new content.
- Running the collector on that sandbox writes `unread_paths.txt` naming `src/locked.py`, lists it in `manifest.txt`, and keeps the `src/readable.py` change in `full_diff.txt` and `diff_stat.txt`. A new script test asserts those unread-path outputs on the staged sandbox.
- After that collector change, `removed_hunks.txt` still carries the `src/readable.py` change on the staged sandbox, the skill's `<evidence_set>` names `unread_paths.txt` among the collected set, and the whole-range commands under `## Collect the Git Layer` in `references/manual_fallback.md` document the per-path retry and unread-path recording, including the `--stat` command for `diff_stat.txt`.
- The skill's `<unread_remainder>` names `unread_paths.txt` as the input it reads.
- The fixture-table row for `unreadable_path` and the `### 19` entry in `tests/git_review/evals/README.md` are rewritten in place so both describe a path whose new content git cannot produce; the prior `chmodded to 000` table wording is gone.
- `## The fixture that needs care` in `tests/git_review/RUNBOOK.md` is rewritten in place so it describes the blobless/sparse hide and ordinary workspace removal; the prior chmod-000 and `chmod -R u+rwX` restore wording is gone.
- The `19)` case in `grade.sh` fails a response that contains `secret_flag`.
- The `19)` case in `grade.sh` fails a response that names `src/locked.py` without unread language, and a remaining check grades unread beside that path; the prior path-name-only check is gone.
- The `19)` case in `grade.sh` fails a response that calls the change approvable while `src/locked.py` is unread, replacing the current `attest` line, and still passes a needle that withholds approvability.
- Eval 19 passes on a fresh `python3 tests/git_review/evals/run.py --vendor cursor 19` run only when those `grade.sh` checks pass. When that run misses, fix the fixture, collector, or skill; leave the grader's unread-naming and no-approvable checks in place, per TESTING.md Test Integrity.
