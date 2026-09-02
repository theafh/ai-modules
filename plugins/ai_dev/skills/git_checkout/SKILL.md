---
name: git_checkout
description: "Put the repository onto an existing branch wherever it lives: fetch every remote without pruning, switch when the branch is already local, create a local branch with an explicit upstream when one remote carries the name, ask which remote to track when several do, and separate a nonexistent branch from one hidden by a narrow fetch refspec. Use when the user asks to check out or switch to a branch, get onto a branch somebody just pushed, track a remote branch locally, or diagnose a pathspec-did-not-match error on a branch that exists. Invoke only on that explicit request in the current turn. Every path ends on a named local branch, so restoring files from the index or a commit, creating a branch that exists on no ref, and detaching HEAD onto a commit or tag stay out, as do pruning refs and deleting branches, which git_refresh owns."
version: 1.0.0
author: Andreas F. Hoffmann
license: MIT
---
# git_checkout

<git_checkout_skill>
  <objective>Leave the repository checked out on a named local branch for the branch the user asked for, creating a tracking branch when the branch lives only on a remote, and holding for the user's choice when the name is ambiguous.</objective>
  <command_intent>normalize the branch argument, fetch every remote without pruning, enumerate the matching refs, then switch, create a tracking branch, ask which remote to track, or report why the name resolves nowhere</command_intent>
  <path_resolution>
    Bundled scripts live in `scripts/` next to this `SKILL.md`. Resolve the helper path by combining the directory of this `SKILL.md` with `scripts/checkout_branch.sh` and invoke the absolute path. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed. Open `references/manual_fallback.md` only after the script exits non-zero for a missing-file or environment reason after that retry; the helper's own outcome codes 3, 4, and 5 are reported results rather than script failures.
  </path_resolution>
  <primary_workflow>
    <single_run>Invoke `scripts/checkout_branch.sh <branch>` with the branch name the user gave, passing the remote-qualified form `<remote>/<branch>` verbatim when the user named a remote. The helper performs the whole resolution in one run: argument normalization, `git fetch --all --no-prune`, ref enumeration, and the one action the resolved case calls for.</single_run>
    <consume_report>Read the helper output as the action log. Report the branch now checked out, whether it already existed or the run created it, the upstream it tracks, and the previous branch left behind.</consume_report>
    <closing_question>When the helper exits 3 with candidate remote branches, ask the user which remote the local branch should track and name every candidate in the offer. Re-enter by invoking the helper again with the remote-qualified form for the remote the user chose.</closing_question>
    <miss_and_block>When the helper exits 4, report the cause it named rather than a generic failure, and state that the run created nothing and switched nowhere. When it exits 5, report the blocking paths and leave the worktree untouched.</miss_and_block>
  </primary_workflow>
  <resolution_order>
    <normalize_argument>Accept a bare name and the remote-qualified form `origin/<name>`, and reduce the qualified form to the local branch name plus its named remote. A remote-qualified argument selects that remote: the run skips the ambiguity hold, resolves against that remote alone, and on a miss for that remote reports the miss without falling through to another remote carrying the name. A slashed name whose first segment is no configured remote, such as `feature/login`, keeps every segment as the branch name.</normalize_argument>
    <fetch_without_pruning>Fetch with `git fetch --all --no-prune` so a branch pushed since the last fetch resolves and every configured remote is covered before resolution. Pruning remote-tracking refs belongs to `git_refresh`, whose default run already owns it, and `--no-prune` holds that line even in a repository configured with `fetch.prune = true`, so this skill removes no ref as a side effect of a switch.</fetch_without_pruning>
    <enumerate_candidates>List the local branches and the remote-tracking refs with `git for-each-ref --format '%(refname:short)' refs/heads refs/remotes`, so the resolved case is known from the refs before any action runs.</enumerate_candidates>
    <already_local>Switch with `git switch <name>` when the branch already exists locally, and report the branch as already present with no tracking branch created. The helper falls back to `git checkout <name>` on a git older than 2.23, which predates `git switch`.</already_local>
    <single_remote>Create the local branch with an explicit upstream from that remote's branch when the name resolves on exactly one remote, rather than relying on git's DWIM shortcut, so the result is the same under any `push.default` or DWIM configuration.</single_remote>
    <several_remotes>List each candidate remote branch and ask which to track when a bare name resolves on several remotes, creating nothing and switching nowhere on that pass. The choice belongs to the user, so make no default pick. A remote-qualified argument resolves without this hold.</several_remotes>
    <resolves_nowhere>Separate a branch that genuinely does not exist from one hidden by a restricted `fetch` refspec or a single-branch clone. The helper asks each remote directly with `git ls-remote --heads`, and reports the narrow refspec together with the widening remedy when a remote advertises the branch that never reached `refs/remotes/`, so the run names the cause instead of relaying git's `pathspec did not match` message unexplained.</resolves_nowhere>
    <named_local_branch>End every successful path on a named local branch. Resolve a remote-qualified argument to the local branch name rather than checking out the remote-tracking ref, which would leave `HEAD` detached and attach later commits to no branch.</named_local_branch>
  </resolution_order>
  <safe_default_policy>
    <dirty_worktree>Let git decide whether local changes survive the switch: it carries compatible changes across and refuses when they would be overwritten. On refusal, surface the blocking paths git named and stop with the original branch still checked out. Use no stash, reset, checkout-discard, or other command that hides or discards user changes to make the switch proceed.</dirty_worktree>
    <no_ref_removal>Remove no branch ref and no remote-tracking ref on any path.</no_ref_removal>
    <create_nothing_on_hold>Create no branch and switch nowhere on the ambiguity hold and on every miss.</create_nothing_on_hold>
  </safe_default_policy>
  <boundary>
    <moves_head_only>This skill moves `HEAD` onto a named local branch and creates tracking branches. Restoring files from the index or from a commit, which is what a path-form checkout and `git restore` do, stays outside it; route such a request to those commands directly.</moves_head_only>
    <existing_branches_only>Create no branch that exists on no remote and no local ref. Report the name as nonexistent and let the user decide whether to create it.</existing_branches_only>
    <no_detached_head>Check out no bare commit or tag, since every path here ends on a named local branch.</no_detached_head>
    <sibling_owns_deletion>Leave pruning remote-tracking refs and deleting local branches to the `git_refresh` sibling.</sibling_owns_deletion>
  </boundary>
  <fallback_on_script_failure>
    <reference>Open `references/manual_fallback.md` after `scripts/checkout_branch.sh` fails for a missing-file or environment reason and one re-resolved retry also fails.</reference>
    <return>Recover only the failed step manually, then return to the primary workflow for the remaining reporting or the re-entry after an ambiguity hold.</return>
  </fallback_on_script_failure>
  <output_contract>
    <switch_report>Report the branch now checked out, whether it already existed or this run created it, the upstream it tracks, and the previous branch left behind.</switch_report>
    <ambiguity_report>List every candidate remote branch, ask which remote the local branch should track, and state that the run created nothing and switched nowhere.</ambiguity_report>
    <miss_report>Name the cause for the miss, either a branch that exists nowhere or a remote-tracking ref a narrow refspec never delivered, and state that the run created nothing and switched nowhere.</miss_report>
    <block_report>Name the blocking paths, confirm the worktree is unchanged and no stash ran, and name the branch still checked out.</block_report>
  </output_contract>
</git_checkout_skill>
