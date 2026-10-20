#!/usr/bin/env bash
# grade.sh — programmatic grader for the git_checkout behavioral evals.
#
# Usage:
#   grade.sh <eval_id> <sandbox_repo>
#
# Asserts the post-run repository state each eval's expectations name in
# evals.json: the branch HEAD ends on, the upstream it tracks, that HEAD stays
# a symbolic ref, which local branches exist, whether the worktree was left
# as found, and uncommitted content the run must keep. Each check compares
# against the snapshots stage.sh took under <target>/.eval/ before the run.
# Prints PASS or FAIL per check and exits 0 only when every check passed.
#
# Expectations that speak only about the worker's response or about which
# helper it invoked are printed as "response" lines for the operator to
# confirm from response.txt; they never decide the exit code.

set -uo pipefail

eval_id="${1:?eval id required}"
repo="${2:?sandbox repo path required}"

if [[ ! -d "$repo/.git" ]]; then
  echo "FAIL: $repo is not a git repo" >&2
  exit 1
fi

target="$(cd "$repo/.." && pwd -P)"
snap="$target/.eval"
if [[ ! -s "$snap/head_before" ]]; then
  echo "FAIL: $snap/head_before is missing or empty (did stage.sh run?)" >&2
  exit 1
fi

pass=0
fail=0
failures=()

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass+1))
    printf '  PASS  %s\n' "$label"
  else
    fail=$((fail+1))
    printf '  FAIL  %s\n' "$label"
    failures+=("$label")
  fi
}

note_response() {
  printf '  -     response  %s\n' "$1"
}

cd "$repo" || { echo "FAIL: cannot cd into $repo" >&2; exit 1; }

# --- Repository-state predicates -------------------------------------------

on_branch() {
  [[ "$(git symbolic-ref --quiet --short HEAD)" == "$1" ]]
}

head_is_symbolic() {
  git symbolic-ref --quiet HEAD
}

branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1"
}

branch_absent() {
  ! branch_exists "$1"
}

upstream_is() {
  [[ "$(git rev-parse --abbrev-ref --symbolic-full-name "$1@{upstream}")" == "$2" ]]
}

has_no_upstream() {
  ! git rev-parse --abbrev-ref --symbolic-full-name "$1@{upstream}"
}

# The tip a bare remote carried for a branch when stage.sh ran.
remote_tip() {
  awk -v r="$1" -v b="$2" '$1 == r && $2 == b { print $3 }' "$snap/remote_heads"
}

# The tip a local branch had when stage.sh ran.
staged_tip() {
  awk -v b="$1" '$1 == b { print $2 }' "$snap/branches_before"
}

tip_matches_remote() {
  local want
  want="$(remote_tip "$2" "$3")"
  [[ -n "$want" && "$(git rev-parse --verify --quiet "refs/heads/$1")" == "$want" ]]
}

tip_unchanged() {
  local want
  want="$(staged_tip "$1")"
  [[ -n "$want" && "$(git rev-parse --verify --quiet "refs/heads/$1")" == "$want" ]]
}

local_branches_as_found() {
  diff <(git for-each-ref --format='%(refname:short) %(objectname)' refs/heads) \
    "$snap/branches_before"
}

worktree_as_found() {
  diff <(git status --porcelain=v1 --untracked-files=all) "$snap/status_before"
}

absent_on_every_remote() {
  local bare
  for bare in "$target"/*.git; do
    [[ -d "$bare" ]] || continue
    if git --git-dir="$bare" show-ref --verify --quiet "refs/heads/$1"; then
      return 1
    fi
  done
  return 0
}

file_content_is() {
  [[ -f "$1" && "$(cat "$1")" == "$2" ]]
}

tracked_and_modified() {
  git ls-files --error-unmatch "$1" && ! git diff --quiet HEAD -- "$1"
}

no_stash() {
  ! git rev-parse --verify --quiet refs/stash
}

# --- Per-eval checks ---------------------------------------------------------

case "$eval_id" in
  1)
    check "repository ends on local branch feature/search" on_branch feature/search
    check "feature/search tracks origin/feature/search" \
      upstream_is feature/search origin/feature/search
    check "feature/search points at the tip origin carries" \
      tip_matches_remote feature/search origin feature/search
    check "HEAD is a symbolic ref, so the run left no detached HEAD" head_is_symbolic
    check "worktree left as found" worktree_as_found
    note_response "invoked scripts/checkout_branch.sh rather than a hand-run git switch sequence"
    note_response "reported feature/search as created by this run, named its upstream, and named the previous branch main"
    ;;
  2)
    check "repository ends on local-notes" on_branch local-notes
    check "local-notes still points at its staged tip" tip_unchanged local-notes
    check "no second branch was created: local branches as found" local_branches_as_found
    check "local-notes still has no upstream: no tracking branch was set up" \
      has_no_upstream local-notes
    check "worktree left as found" worktree_as_found
    note_response "invoked scripts/checkout_branch.sh"
    note_response "reported local-notes as already present rather than created by this run"
    note_response "stated that no tracking branch was created"
    ;;
  3)
    check "repository is still on main" on_branch main
    check "main still points at its staged tip" tip_unchanged main
    check "no local release-prep branch exists" branch_absent release-prep
    check "nothing was created: local branches as found" local_branches_as_found
    check "worktree left as found" worktree_as_found
    note_response "invoked scripts/checkout_branch.sh with the bare name release-prep"
    note_response "listed origin/release-prep and fork/release-prep as candidates"
    note_response "asked which remote the local branch should track and picked no default"
    note_response "stated that nothing was created and nowhere was switched to"
    ;;
  4)
    check "repository ends on local branch release-prep" on_branch release-prep
    check "release-prep tracks fork/release-prep" \
      upstream_is release-prep fork/release-prep
    check "release-prep points at the tip fork carries" \
      tip_matches_remote release-prep fork release-prep
    check "HEAD is a symbolic ref, so naming the remote did not detach HEAD" \
      head_is_symbolic
    check "worktree left as found" worktree_as_found
    note_response "invoked scripts/checkout_branch.sh with the remote-qualified argument fork/release-prep"
    note_response "asked no question about which remote to track"
    ;;
  5)
    check "repository is still on main" on_branch main
    check "main still points at its staged tip" tip_unchanged main
    check "no local hotfix/tls branch was created" branch_absent hotfix/tls
    check "nothing was created: local branches as found" local_branches_as_found
    check "worktree left as found" worktree_as_found
    note_response "invoked scripts/checkout_branch.sh"
    note_response "named the restricted fetch refspec or single-branch clone as the cause"
    note_response "showed the configured fetch refspec for origin"
    note_response "offered the refspec-widening remedy"
    ;;
  6)
    check "repository is still on main" on_branch main
    check "main still points at its staged tip" tip_unchanged main
    check "no local ship-it branch was created" branch_absent ship-it
    check "no remote gained a ship-it branch" absent_on_every_remote ship-it
    check "nothing was created: local branches as found" local_branches_as_found
    check "worktree left as found" worktree_as_found
    note_response "invoked scripts/checkout_branch.sh"
    note_response "reported that ship-it exists neither locally nor on any remote"
    note_response "kept that miss distinct from a branch hidden by a fetch refspec"
    ;;
  7)
    check "repository is still on main" on_branch main
    check "main still points at its staged tip" tip_unchanged main
    check "no local rework branch exists" branch_absent rework
    check "seed.txt still holds the uncommitted local edit" \
      file_content_is seed.txt "uncommitted local edit"
    check "seed.txt is still modified against HEAD and uncommitted" \
      tracked_and_modified seed.txt
    check "worktree left as found" worktree_as_found
    check "no stash entry was created" no_stash
    note_response "invoked scripts/checkout_branch.sh"
    note_response "named seed.txt as the blocking path"
    note_response "ran no reset or checkout-discard to make the switch proceed"
    ;;
  *)
    echo "unknown eval id: $eval_id (valid: 1..7)" >&2
    exit 2
    ;;
esac

# --- Summary -----------------------------------------------------------------

echo "---"
printf 'eval-%s: %s pass, %s fail\n' "$eval_id" "$pass" "$fail"
if (( fail > 0 )); then
  printf 'failed checks:\n'
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
exit 0
