---
name: git_refresh
description: "Refresh a local git repo back to a clean current default branch: fetch/prune, detect the remote HEAD, fast-forward main/master by --ff-only, delete merged local branches, and offer gated cleanup for upstream-gone, squash-merged, stale, or force-delete branch pruning. Use when the user asks to clean up branches, refresh main, refresh master, delete merged branches, get back to a clean main, prune stale local branches, or tidy local branches after merged PRs. Invoke only on that explicit request in the current turn; noticing stale or merged branches during other work leaves the cleanup to the user."
version: 1.0.1
author: Andreas F. Hoffmann
license: MIT
---
# git_refresh

<git_refresh_skill>
  <objective>Refresh the current repository to its remote default branch and remove only branch refs whose deletion is provably safe by default.</objective>
  <command_intent>fetch and prune, switch to the detected default branch, fast-forward only, delete cleanly merged local branches, and report gated branch cleanup candidates</command_intent>
  <path_resolution>
    Bundled scripts live in `scripts/` next to this `SKILL.md`. Resolve the helper path by combining the directory of this `SKILL.md` with `scripts/refresh_repo.sh` and invoke the absolute path. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed. Open `references/manual_fallback.md` only after the script exits non-zero after that retry.
  </path_resolution>
  <primary_workflow>
    <default_run>Invoke `scripts/refresh_repo.sh` with no arguments. The helper performs the safe default run without per-action prompts: `git fetch --prune`, remote-HEAD default branch detection, clean-worktree switch to the default branch, fast-forward-only update, and `git branch -d` cleanup for branches already merged into the default branch.</default_run>
    <consume_report>Read the helper output as the action log. Report the fetch/prune, detected default branch, switch result, fast-forward result, each deleted branch, and each skipped action exactly enough for the user to know what changed.</consume_report>
    <closing_question>When the helper prints a follow-up question with upstream-gone candidates, ask the user whether to run the gated cleanup and name the exact branches in the offer. When the helper reports that nothing further remains, close with that state and ask no extra cleanup question.</closing_question>
  </primary_workflow>
  <safe_default_policy>
    <default_branch_detection>Resolve the default branch from the remote HEAD; never hardcode `main`. The helper uses `refs/remotes/origin/HEAD` first and `git remote show origin` as fallback, so repositories whose default branch is `master` or another name refresh correctly.</default_branch_detection>
    <fast_forward_only>Update the default branch only by fast-forward. When local and upstream histories have diverged, report the divergence and leave the branch untouched; use no merge commit and no rebase.</fast_forward_only>
    <clean_delete_only>Delete local branches in the default run only with `git branch -d` after the branch is already merged into the default branch. Keep every branch that could contain unmerged or unpushed work.</clean_delete_only>
    <protected_branches>Keep the current branch and the detected default branch out of deletion candidates.</protected_branches>
    <dirty_worktree>When uncommitted changes would block switching or fast-forwarding, report `git status --short` and skip the blocked actions. Use no stash, reset, checkout-discard, or other command that hides or discards user changes.</dirty_worktree>
    <default_boundary>The default run never runs `git branch -D` and never deletes upstream-gone branches. It only reports those candidates for an explicit follow-up.</default_boundary>
  </safe_default_policy>
  <gated_extensions>
    <upstream_gone_pruning>
      Run this only after the user opts in. Invoke `scripts/refresh_repo.sh --prune-gone` to process all upstream-gone branches, or append branch names to narrow the scope. The helper lists candidates with `git for-each-ref --format '%(refname:short) %(upstream:track)' refs/heads`, checks commits absent from the default branch with `git log --oneline <default>..<branch>`, deletes branches with no absent commits via `git branch -d`, and shows absent commits for every branch that requires force-delete confirmation. This covers stale upstream-gone and squash-merged PR cleanup while preserving branches that still carry unique work.
    </upstream_gone_pruning>
    <force_delete>
      Run this only after the user explicitly confirms the exact branch. Invoke `scripts/refresh_repo.sh --force-delete <branch> --confirm-force-delete <branch>`. The helper prints `git log --oneline <default>..<branch>` before deletion and then runs `git branch -D` only when the confirmation argument exactly matches the branch.
    </force_delete>
  </gated_extensions>
  <fallback_on_script_failure>
    <reference>Open `references/manual_fallback.md` after `scripts/refresh_repo.sh` exits non-zero and one re-resolved retry also fails.</reference>
    <return>Recover only the failed action manually, then return to the primary workflow for any remaining reporting or gated follow-up.</return>
  </fallback_on_script_failure>
  <output_contract>
    <default_report>Report the concrete actions taken and skipped: fetch/prune, detected default branch, switch, fast-forward extent or divergence, and each deleted branch.</default_report>
    <gated_offer>When riskier candidates exist, surface each upstream-gone or squash-merged branch, marking branches with no absent commits as safe for `git branch -d` after opt-in and branches with absent commits as requiring explicit force-delete confirmation with those commits shown.</gated_offer>
    <nothing_remaining>When no gated candidates exist, state that nothing further remains.</nothing_remaining>
  </output_contract>
</git_refresh_skill>
