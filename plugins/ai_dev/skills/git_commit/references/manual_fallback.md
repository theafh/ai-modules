# git_commit — manual fallback

Trigger: a primary `git_commit` script (`scripts/prepare_commit_context.sh` or
`scripts/commit_with_message.sh`) failed during the current run — a non-zero
exit other than status `3`. A `commit_with_message.sh` exit of `3` is an
intentional foreign-drift refusal, not a failure, and does not open this manual
path; handle it in `SKILL.md`'s `<execute_commit>` by surfacing the printed
paths, asking the user, and re-invoking with `--accept-drift`. A genuine script
failure is the only authorized trigger here. If neither script has been invoked
yet, return to `SKILL.md` and run the primary workflow first.

The sections below replace the failing script step-for-step. Run only the
section that corresponds to the script that failed; return to the primary
workflow for any remaining steps.

## Pre-flight ordering before context capture

Preserve the primary workflow's `<prepare_worktree>` → `<gather_context>`
ordering on the manual path. Before capturing context, discover every
agent-directed rule that bears on the commit from all rule sources the current
harness provides, decide each discovered obligation with the relevance test
below, satisfy the ones it selects, and confirm each obligation it chose to run
is settled. Discovery stays broad: finding a rule records that it exists, and
the relevance test decides which candidates this commit runs. A qualifying rule
is a standing instruction addressed to the agent that only the agent invokes;
repository and user standing instructions, agent memory, prompts, and further
harness-provided sources are open-ended examples rather than an exhaustive
source list.

The relevance test is domain intersection, and it governs tree-mutating and
check-only obligations alike. Read the obligation to determine the subject
matter it governs — the paths, file types, or artifacts it checks or rewrites —
and compare that against the paths this commit changes, obtained here for path
names alone by running `git status --short --untracked-files=all` once before
either context path. Run the obligation when the two intersect and skip it when
they do not, so a markdown lint over a documentation-only change still runs
while a language- or asset-specific gate over that same change does not. Run an
obligation whose governed subject matter you cannot determine, following the
same no-miss-over-no-sweep tiebreaker the drift guard applies. State each skip
as it happens, naming the obligation, the subject matter it governs, and the
changed paths that miss it, so a wrong skip is correctable in the moment.

The tree-mutating against check-only split governs ordering alone: a selected
tree-mutating obligation clears this gate before either context path runs,
while a selected check-only obligation may run on either side of that seam.
Weigh where a check-only obligation runs on both counts — running it here
exposes a failing gate before context work begins, and commit time spent on a
check that exercises nothing this commit touched is the cost the relevance test
exists to spare. Leave command-triggered mechanical hooks, including git hooks
and harness commit hooks, to the commit command that fires them so their logic
runs once. This ordering honors the agent-directed obligations this commit
implicates, lets context be built and read once, and places the model's own
pre-commit edits inside the reviewed-set baseline used by both drift-guard
layers.

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

2. Inspect status: `git status --short --untracked-files=all`. This snapshot
   is the reviewed-set baseline the drift check below compares against, exactly
   as the script's `<status_after_staging_new_files>` block serves the scripted
   path.
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

## Drift check before staging

This is the same model-side `<detect_drift>` step the primary `SKILL.md`
workflow runs at the seam before committing — not a per-script fallback
section, so it runs once here whether the context came from the script or the
manual replacement above. `commit_with_message.sh` enforces the same guard as a
mechanical backstop, refusing with exit status `3`; this manual re-check and
that scripted backstop stay in agreement. Run it after the context is in hand
and the message composed, and before the `git add -A` in the commit step below.

Re-run `git status --short --untracked-files=all` and compare its paths to the
reviewed-set baseline captured in the status step above, on equal footing.

1. **No drift — commit all.** The re-check surfaces no path outside the
   baseline — the path set matches. Proceed to the commit step with no prompt.
   This is the common case, a clean single-session tree included.
2. **Foreign drift — pause and ask.** One or more paths appear that were
   outside the reviewed-set baseline and entered commit-time status after it was
   captured (a new file, or a path that was clean or absent from the baseline
   and is now changed). Pause, list those paths to the user, and ask whether
   they belong in this commit before staging them. On the scripted path a commit
   the user confirms passes `--accept-drift` to `commit_with_message.sh`; in this
   manual replacement, proceed to `git add -A` once the user confirms.
3. **In doubt — commit all.** A concurrent session's edit to a path already in
   the baseline adds no path outside it, so this path-level comparison cannot
   separate that further edit from your own — such a same-path change stays on
   the commit-all path rather than pausing. The tiebreaker favors no-miss over
   no-sweep.

## Replacement for `commit_with_message.sh`

Goal: stage the full repo state and commit from the composed message via
stdin without altering its line breaks, and clean up the context file on
success. There is no intermediate message file.

1. Confirm the composed message is non-empty.
2. Confirm the drift check above has cleared — no drift, or the user confirmed
   the drifted paths belong.
3. Stage everything: `git add -A`.
4. Commit from stdin via a single-quoted heredoc so no shell expansion runs
   inside the message:

   ```bash
   git commit -F - <<'COMMIT_MSG_END'
   <subject line>

   <body lines>
   COMMIT_MSG_END
   ```

5. Print final status: `git status --short --untracked-files=all`.
6. On successful commit, delete the context file from the previous step:
   `rm -f "$ctx_file"` (using the `mktemp` path you kept). Skip this step
   if the commit failed so the context survives for a retry.

## After recovery

Resume the primary workflow in `SKILL.md`. Do not re-run the fallback once
the failing step has been replaced.
