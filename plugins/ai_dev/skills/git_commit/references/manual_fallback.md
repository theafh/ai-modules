# git_commit — manual fallback

Trigger: a primary `git_commit` script (`scripts/prepare_commit_context.sh` or
`scripts/commit_with_message.sh`) exited with a non-zero status during the
current run. This is the only authorized trigger. If neither script has been
invoked yet, return to `SKILL.md` and run the primary workflow first.

The sections below replace the failing script step-for-step. Run only the
section that corresponds to the script that failed; return to the primary
workflow for any remaining steps.

## Replacement for `prepare_commit_context.sh`

Goal: produce the same evidence the script would have written to its context
file — staged untracked files, full status, recent commits, per-file staged
diffs, per-file unstaged diffs, and a generic note for binary files. Write
the captured evidence to `${TMPDIR:-/tmp}/git_commit_context.txt` so the rest
of the workflow can consume it the same way as the scripted path; consume it
with `Read`, paginated `Read` if it overflows, or sequential `grep`/`awk`
slicing only as a last resort.

1. Stage every untracked, non-ignored file:

   ```bash
   git ls-files --others --exclude-standard -z \
     | xargs -0 -I{} git add -- "{}"
   ```

2. Inspect status: `git status --short --untracked-files=all`.
3. Inspect recent commits: `git --no-pager log --oneline -8`.
4. List staged new files: `git diff --cached --name-only --diff-filter=A`.
5. List every staged path: `git diff --cached --name-only`.
6. List every unstaged path: `git diff --name-only`.
7. For each staged path, capture the diff:
   `git --no-pager diff --no-ext-diff --cached -- "<path>"`.
8. For each unstaged path, capture the diff:
   `git --no-pager diff --no-ext-diff -- "<path>"`.
9. Read the full content of any new text file you cannot summarize from its
   diff alone.
10. Treat binary diffs as a generic file-level commit line; do not try to
    summarize their bytes.

## Replacement for `commit_with_message.sh`

Goal: stage the full repo state and commit from the prepared message file
without altering its line breaks.

1. Confirm the message file exists and is non-empty.
2. Stage everything: `git add -A`.
3. Commit from the file: `git commit -F MESSAGE_FILE`.
4. Print final status: `git status --short --untracked-files=all`.
5. On successful commit, delete the context file written in the previous
   step: `rm -f "${TMPDIR:-/tmp}/git_commit_context.txt"`. Skip this step if
   the commit failed so the context survives for a retry.

## After recovery

Resume the primary workflow in `SKILL.md`. Do not re-run the fallback once
the failing step has been replaced.
