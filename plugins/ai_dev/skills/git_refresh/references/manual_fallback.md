# git_refresh - manual fallback

Trigger: `scripts/refresh_repo.sh` exited with a non-zero status during the
current `/git_refresh` run. Re-resolve the script path once and retry before
using this fallback. Use only the section that replaces the failed action, then
return to `SKILL.md` for the remaining workflow.

## Default Refresh

Goal: refresh the repository's detected default branch and clean only branches
Git proves are already merged.

1. Resolve the repository root and switch there:

   ```bash
   repo_root="$(git rev-parse --show-toplevel)"
   cd "$repo_root"
   ```

2. Fetch and prune remote-tracking refs:

   ```bash
   git fetch --prune origin
   ```

3. Resolve the default branch from the remote HEAD:

   ```bash
   git symbolic-ref --quiet --short refs/remotes/origin/HEAD
   git remote show origin
   ```

   Use the symbolic-ref result first, stripping the `origin/` prefix. Use
   `git remote show origin` only when the symbolic ref is absent, reading its
   `HEAD branch:` field.

4. Check for uncommitted changes:

   ```bash
   git status --short
   ```

   When those changes would block switching or fast-forwarding, report the
   status and skip the blocked actions. Keep the worktree exactly as it is; use
   no stash, checkout discard, reset, or cleanup command.

5. Switch to the detected default branch:

   ```bash
   git checkout <default-branch>
   ```

6. Fast-forward only:

   ```bash
   git merge --ff-only origin/<default-branch>
   ```

   When the local and remote branches have diverged, report the divergence and
   leave the branch unchanged. Use no merge commit and no rebase.

7. Delete cleanly merged local branches only:

   ```bash
   git for-each-ref --format '%(refname:short)' refs/heads
   git branch -d <branch>
   ```

   Skip the current branch and the default branch. Use `git branch -d`, which
   refuses unmerged branches; keep every branch it refuses.

8. Report every action: fetch/prune, detected default branch, switch,
   fast-forward result, and each deleted branch.

9. List gated follow-up candidates with:

   ```bash
   git for-each-ref --format '%(refname:short) %(upstream:track)' refs/heads
   git log --oneline <default-branch>..<branch>
   ```

   Offer to prune upstream-gone branches only after the default run completes.
   When there are no candidates, state that nothing further remains.

## Gated Upstream-Gone Pruning

Goal: after the user opts in, remove upstream-gone branches that have no commits
absent from the default branch, and surface the branches that need explicit
force-delete confirmation.

1. Refresh refs and resolve the default branch as in the default refresh.
2. List upstream-gone branches:

   ```bash
   git for-each-ref --format '%(refname:short) %(upstream:track)' refs/heads
   ```

3. For each candidate, inspect commits absent from the default branch:

   ```bash
   git log --oneline <default-branch>..<branch>
   ```

4. Delete a branch with no absent commits via:

   ```bash
   git branch -d <branch>
   ```

5. For a branch with absent commits, show those commits and ask for explicit
   confirmation before running any force-delete command.

## Gated Force-Delete

Goal: after the user explicitly names a branch and confirms force deletion,
show the commits that would be lost and then remove exactly that branch.

1. Show the commits that would be lost:

   ```bash
   git log --oneline <default-branch>..<branch>
   ```

2. Confirm the user asked to force-delete that exact branch.
3. Delete it:

   ```bash
   git branch -D <branch>
   ```

4. Report the deleted branch.
