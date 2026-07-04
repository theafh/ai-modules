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
diffs, per-file unstaged diffs, and a generic note for binary files. Pick a
unique context path with `ctx_file=$(mktemp "${TMPDIR:-/tmp}/git_commit_context.XXXXXX")`
(pass the full template — `mktemp -t prefix` leaves the literal `XXXXXX` in
the filename on BSD/macOS)
and write the captured evidence there so the rest of the workflow can consume
it the same way as the scripted path, by the same size-driven contract
`SKILL.md`'s `<consume_context>` defines: read the whole blob in one call when
it fits under your reader's per-read cap; when it exceeds the cap, cover every
byte with sequential non-overlapping pages, halving the span on overflow; and
when even paginated reading cannot cover it, or where this agent has no Read
tool, read ordered non-overlapping shell slices (`wc -l` for the line count,
then consecutive `sed -n` spans) that cover every byte in order — never
sampling by filename. Keep the `ctx_file` value — you will pass it to the
commit step so it gets cleaned up on success.

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

Goal: stage the full repo state and commit from the composed message via
stdin without altering its line breaks, and clean up the context file on
success. There is no intermediate message file.

1. Confirm the composed message is non-empty.
2. Stage everything: `git add -A`.
3. Commit from stdin via a single-quoted heredoc so no shell expansion runs
   inside the message:

   ```bash
   git commit -F - <<'COMMIT_MSG_END'
   <subject line>

   <body lines>
   COMMIT_MSG_END
   ```

4. Print final status: `git status --short --untracked-files=all`.
5. On successful commit, delete the context file from the previous step:
   `rm -f "$ctx_file"` (using the `mktemp` path you kept). Skip this step
   if the commit failed so the context survives for a retry.

## After recovery

Resume the primary workflow in `SKILL.md`. Do not re-run the fallback once
the failing step has been replaced.
