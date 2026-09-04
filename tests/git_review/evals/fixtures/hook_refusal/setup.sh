#!/usr/bin/env bash
# A repository policy hook refuses to leave the main worktree on the target
# branch: it prints its refusal and puts the branch back. A linked worktree is
# outside the guard, which is the shape a policy hook usually takes, so the
# review can still run from a detached scratch worktree.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
printf 'base\n' > app.txt
git add app.txt
git commit --quiet -m "seed app"
git push --quiet origin main

git checkout --quiet -b guarded
printf 'base\nguarded change\n' > app.txt
git add app.txt
git commit --quiet -m "app.txt -> add the guarded change"
git push --quiet -u origin guarded
git checkout --quiet main

# git runs post-checkout after the switch and reports its exit status as the
# checkout's own, so a policy hook that refuses also restores the branch it
# refused to leave. The main-worktree test keeps linked worktrees outside the
# guard, which is how such hooks are usually written.
cat > .git/hooks/post-checkout <<'HOOK'
#!/usr/bin/env bash
set -uo pipefail

# Linked worktrees have a .git file rather than a directory, so this guard
# applies to the main worktree alone.
[[ -d "$(git rev-parse --git-dir)" ]] || exit 0
[[ "$(git rev-parse --git-dir)" == "$(git rev-parse --git-common-dir)" ]] || exit 0

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ "$branch" == "guarded" ]]; then
    echo "policy: this clone refuses to sit on 'guarded'; restoring main" >&2
    git symbolic-ref HEAD refs/heads/main
    git reset --quiet --hard main
    exit 1
fi
exit 0
HOOK
chmod +x .git/hooks/post-checkout
printf '%s\n' "$repo"
