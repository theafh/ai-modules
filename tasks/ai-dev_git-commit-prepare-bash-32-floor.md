---
description: Fix prepare_commit_context.sh under stock bash 3.2 (empty diff lists, masked abort status) and prove both git_commit scripts under /bin/bash in the script tests.
scope: plugins/ai_dev/skills/git_commit
created: 2026-10-09T22:18:42
updated: 2026-10-09T22:18:42
status: open
reported-by: Andreas Hoffmann
---

# Make git_commit's bundled scripts run and fail correctly under stock bash 3.2

## Goal

`prepare_commit_context.sh` runs to completion under macOS's stock `/bin/bash` 3.2 when its staged or its unstaged diff list is empty, and any run that aborts exits non-zero. The agent running the git_commit skill then always receives either the three stdout lines (the context file's path, its byte size, and the one-line consumption directive) or a non-zero exit that the skill's `<fallback_trigger>` reads as a failure. The task also audits `commit_with_message.sh` for the same hazard and adds script-test scenarios that run both scripts through an explicit `/bin/bash`, so the tests prove the floor on any machine whose `/bin/bash` is the stock build, whatever bash `PATH` resolves first. The work stays at the point-fix for git_commit's two bundled scripts.

## Context

**Failure.** Under `/bin/bash` 3.2.57 the script aborts whenever its staged or its unstaged diff list is empty after it stages untracked files, and it still exits 0 with empty stdout. This reproduction from 2026-10-09 runs from inside this repository:

```bash
repo=$(git rev-parse --show-toplevel)
d=$(mktemp -d) && cd "$d" && git init -q && git config user.email t@e && git config user.name t
echo a > seed.txt && git add . && git commit -qm seed && echo b > seed.txt
/bin/bash "$repo/plugins/ai_dev/skills/git_commit/scripts/prepare_commit_context.sh"; echo "rc=$?"
# stderr: prepare_commit_context.sh: line 76: buffer[@]: unbound variable
# stdout: empty; rc=0
```

The same command under a newer package-manager bash (5.3.9) prints the three stdout lines. Running the script on each working-tree shape the same day gave this result:

| Working tree | Empty diff list | `/bin/bash` 3.2.57 | bash 5.3.9 |
| --- | --- | --- | --- |
| Clean | both | aborts, exits 0 | runs |
| Modifications only | staged | aborts, exits 0 | runs |
| New untracked files only | unstaged | aborts, exits 0 | runs |
| Pre-staged modifications only | unstaged | aborts, exits 0 | runs |
| Modifications plus new files | neither | runs | runs |

**Cause.** `load_numstat` collects the numstat rows into `local -a buffer=()` and copies them out with `staged_numstat=("${buffer[@]}")` or `unstaged_numstat=("${buffer[@]}")`. Under `set -u`, bash before 4.4 treats `"${name[@]}"` on an empty array as an unbound variable, so the copy of an empty list aborts the script. The script's other array expansions already hold at the floor: `is_binary_diff` reads `"${staged_numstat[@]:-}"` and `"${unstaged_numstat[@]:-}"`, which turn an empty array into one empty element that its loop skips.

**Masked exit status.** The script installs `trap 'rm -rf "$tmp_dir"' EXIT` before `load_numstat` runs. When a `set -u` error aborts bash 3.2, `$?` reads 0 inside the EXIT trap and the shell exits with the trap's last status, so the abort reports success. Probes under `/bin/bash` 3.2.57 on 2026-10-09 showed four behaviours:

- The same abort exits 1 when no EXIT trap is installed.
- A trap of the form `trap 'rc=$?; rm -rf "$tmp_dir"; exit "$rc"' EXIT` still exits 0, because `rc` captures the masked 0.
- A trap that exits 1 unless a completion flag is set, with the flag initialized before the trap and set as the script's last statement, exits 1 on the abort and 0 on a clean run.
- An unbound scalar is masked the same way, so the masking covers every `set -u` abort, while a command that fails under `set -e` keeps its non-zero status on both bash versions.

**Caller impact.** The skill's `<fallback_trigger>` opens the manual fallback on a non-zero exit, so an exit 0 with empty stdout leaves the agent with neither a context path nor a failure to act on. On 2026-10-09, git_commit behavioural evals 4 (large changeset, modifications only) and 7 (ambiguous drift, one modified file) ran on Cursor workers whose shell resolved `/bin/bash`. Both fell back to the manual workflow and left hand-built `git_commit_context.*` files in `TMPDIR`, which failed `grade.sh`'s straggler check. The eval harness now restores the operator's `PATH` for Cursor workers, so the evals no longer meet the stock bash on a machine with a newer package-manager bash, but any user whose shell resolves bash 3.2, such as on macOS without a package-manager bash, still hits the bug.

**The commit script.** `commit_with_message.sh` declares no arrays and installs no EXIT trap. On 2026-10-09 it passed `/bin/bash -n`, and under `/bin/bash` it committed a modifications-only tree without a context file and a mixed tree with one.

**Script tests.** `tests/git_commit/script_tests/run.sh` invokes both scripts through their `#!/usr/bin/env bash` shebang, as `"$PREPARE"` inside `run_prepare` and `run_prepare_content` and as `"$COMMIT"` inside `run_commit`. The scripts therefore run under whichever bash `PATH` resolves first, which on a machine with a newer bash ahead of the stock one is never bash 3.2. The deployment script tests already pin the floor: `tests/deployment/script_tests/run.sh` sets `DEPLOY_BASH="/bin/bash"` and runs `"$DEPLOY_BASH" "$DEPLOY_SCRIPT"`.

**Standing rules.** harness_portability's rule beginning "Target bash 3.2 as the interpreter floor" governs both scripts. The wiki page `wiki/concepts/interpreter-and-tool-path-portability.md` records verified bash 3.2.57 behaviour under `### Constructs above the floor`, and the empty-array abort and the masked exit status are still missing from it.

## Approach

**Guard both copies.** Rewrite the two copies in `load_numstat` so an empty buffer copies as an empty array at the floor, for example `staged_numstat=(${buffer[@]+"${buffer[@]}"})`. Under `/bin/bash` 3.2.57 that form yields an empty array for an empty buffer and keeps an element containing spaces intact, and shellcheck 0.11.0 reports nothing on it (both verified 2026-10-09).

**Exit non-zero on any abort.** Rewrite the EXIT trap so it ends the run with a non-zero status whenever the run stopped before its last statement, using the completion flag the probes verified: initialize the flag before installing the trap, set it as the script's final statement after the three stdout lines, and have the trap exit non-zero whenever the flag is still unset. The `--help` exit 0, the unknown-argument exit 2, and the `git rev-parse` failure outside a repository all happen before the trap is installed, so they keep their statuses. The skill's `<fallback_trigger>` already reads a non-zero exit from this script as a genuine failure, so the fix needs no change to `SKILL.md` or `references/manual_fallback.md`.

**Audit the commit script.** Check `commit_with_message.sh` for unguarded array expansions and any other `set -u` hazard at the floor, and change it only where the audit finds one. The scenarios below run it under `/bin/bash` either way.

**Prove both scripts at the floor.** In `tests/git_commit/script_tests/run.sh`, add an interpreter variable pinned to `/bin/bash`, modeled on the deployment tests' `DEPLOY_BASH`, and have the new scenarios run both scripts through it. Each new scenario logs the first line of `/bin/bash --version`, so the run log shows which bash it proved. Add three scenarios:

- **Modifications-only tree**, which empties the staged list: run the prepare script, then pipe a commit message into `commit_with_message.sh` with the printed context path.
- **New-files-only tree**, which empties the unstaged list: run both scripts the same way.
- **Injected abort**: copy the prepare script into the scenario's scratch directory with one unbound-variable reference inserted after the EXIT trap is installed, and run the copy in a fresh repository.

**Versioning.** The skill and plugin version bumps follow the standing repo versioning rules at commit time, so this task carries no bump step.

## Acceptance

- Under `bash tests/git_commit/run_all.sh`, the modifications-only scenario passes under `/bin/bash`: the prepare script exits 0 and prints the three stdout lines, the printed path names an existing context file that carries `<file_change mode="unstaged" path="seed.txt">`, and `commit_with_message.sh` then exits 0, `HEAD` advances to a commit carrying the piped message, and the context file is gone.
- Under `bash tests/git_commit/run_all.sh`, the new-files-only scenario passes under `/bin/bash`: the prepare script exits 0 and prints the three stdout lines, the context file's `<staged_new_files>` block lists the new file, and `commit_with_message.sh` then exits 0 with the new file committed in `HEAD` and the context file gone.
- Under `bash tests/git_commit/run_all.sh`, the injected-abort scenario passes: the injected copy exits non-zero with empty stdout under `/bin/bash`. On a host whose `/bin/bash` is 3.2, the same injection applied to the script as committed before this task (`git show HEAD:plugins/ai_dev/skills/git_commit/scripts/prepare_commit_context.sh`) exits 0, which shows the scenario detects the masked status.
- The run log `tests/git_commit/results/layer1.log` shows the `/bin/bash --version` line for each of the three new scenarios.
- Neither `staged_numstat=("${buffer[@]}")` nor `unstaged_numstat=("${buffer[@]}")` remains in `prepare_commit_context.sh`, and the script installs exactly one EXIT trap.
