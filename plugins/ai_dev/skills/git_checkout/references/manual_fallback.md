# git_checkout - manual fallback

Trigger: `scripts/checkout_branch.sh` could not run during the current
`/git_checkout` run, because the file was missing or the environment refused it.
Re-resolve the script path once and retry before using this fallback. The
helper's own outcome codes are results rather than failures: 3 is the ambiguity
hold, 4 is a reported miss, and 5 is a switch git refused. Use only the section
that replaces the step that failed, then return to `SKILL.md` for the remaining
reporting.

## Resolve the Argument

Goal: reduce the branch argument to a local branch name plus, when the user
named one, a single selected remote.

1. List the configured remotes:

   ```bash
   git remote
   ```

2. Split the argument on its first `/`. When the leading segment matches a
   configured remote, that remote is selected and the rest is the branch name.
   When it matches no remote, keep every segment as the branch name, so
   `feature/login` stays one branch name.
3. A selected remote narrows the whole run: resolve against that remote alone,
   skip the ambiguity hold, and report a miss for that remote rather than
   falling through to another remote carrying the name.
4. Keep the local branch name as the checkout target. Checking out
   `<remote>/<branch>` directly lands in detached `HEAD`, where later commits
   attach to no branch.

## Fetch Without Pruning

Goal: make a branch pushed since the last fetch visible on every remote, while
removing no ref.

```bash
git fetch --all --no-prune
```

Keep `--no-prune` even in a repository configured with `fetch.prune = true`.
Pruning remote-tracking refs belongs to the `git_refresh` skill; a switch
removes no ref. When the fetch exits non-zero because a remote is unreachable,
report that and continue resolving from the refs already present.

## Enumerate the Candidates

Goal: know which case applies before acting.

```bash
git for-each-ref --format '%(refname:short)' refs/heads refs/remotes
```

The branch exists locally when `refs/heads/<branch>` is in the list. A remote
carries it when `<remote>/<branch>` is in the list for that remote's name.

## Switch to an Existing Local Branch

Goal: move onto a branch this clone already has.

```bash
git switch <branch>
```

Use `git checkout <branch>` on a git older than 2.23, which predates
`git switch`. Report the branch as already present and that no tracking branch
was created, and read its upstream with:

```bash
git rev-parse --abbrev-ref --symbolic-full-name <branch>@{upstream}
```

## Create a Tracking Branch From One Remote

Goal: create a local branch with an explicit upstream when exactly one remote
carries the name.

```bash
git switch --create <branch> --track <remote>/<branch>
```

Use `git checkout -b <branch> --track <remote>/<branch>` on a git older than
2.23. Set the upstream explicitly rather than relying on git's DWIM shortcut,
so the result is the same under any `push.default` or DWIM configuration.

## Hold on Several Remotes

Goal: let the user choose the remote when a bare name resolves on more than one.

1. List every candidate as `<remote>/<branch>`.
2. Ask which remote the local branch should track. Make no default pick.
3. Create nothing and switch nowhere on this pass.
4. Re-enter with the remote-qualified form for the remote the user chose, which
   resolves without a further hold.

## Report the Cause of a Miss

Goal: separate a branch that does not exist from one a narrow fetch refspec
never delivered.

1. Ask each remote directly whether it advertises the branch:

   ```bash
   git ls-remote --heads <remote> refs/heads/<branch>
   ```

2. When no remote advertises it, report the branch as nonexistent and create
   nothing.
3. When a remote advertises it and no remote-tracking ref arrived, the fetch
   refspec is the cause. Show it and offer the widening remedy:

   ```bash
   git config --get-all remote.<remote>.fetch
   git remote set-branches --add <remote> <branch>
   git fetch <remote>
   ```

4. Report the cause rather than relaying git's `pathspec did not match`
   message, which points nowhere near a restricted refspec or a single-branch
   clone.

## Handle a Refused Switch

Goal: keep a dirty worktree intact when git refuses the switch.

1. Read the paths git named in its error; they are the blocking paths.
2. Report them, confirm the original branch is still checked out, and stop.
3. Use no stash, reset, checkout-discard, or cleanup command. Compatible local
   changes carry across the switch on their own, so a refusal means the user
   decides what happens to those paths.
