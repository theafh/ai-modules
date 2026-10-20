#!/usr/bin/env bash
# grade.sh — programmatic grader for the git_refresh behavioral evals.
#
# Usage:
#   grade.sh <eval_id> <sandbox_repo>
#
# Asserts the post-run repository state each eval's expectations name in
# evals.json: the branch HEAD ends on, the default-branch tip after the
# fast-forward, which local branches survive the run or are gone after it, and
# uncommitted content the run must keep. Each check compares against the
# snapshots stage.sh took under <target>/.eval/ before the run. Eval 3 also
# reads <target>/script_calls.log, where run.py's logging shim records each
# refresh_repo.sh call in order: the default run deletes gone-merged before any
# opt-in, so only that log can show the gated --prune-gone call followed the
# default run. Prints PASS or FAIL per check and exits 0 only when every check
# passed.
#
# Expectations that speak only about the worker's response are printed as
# "response" lines for the operator to confirm from response.txt, and so is
# the helper invocation in evals 1, 2, and 4; response lines never decide the
# exit code.

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

branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1"
}

branch_absent() {
  ! branch_exists "$1"
}

# The tip a bare remote carried for a branch when stage.sh ran.
remote_tip() {
  awk -v r="$1" -v b="$2" '$1 == r && $2 == b { print $3 }' "$snap/remote_heads"
}

# The tip a local branch had when stage.sh ran.
staged_tip() {
  awk -v b="$1" '$1 == b { print $2 }' "$snap/branches_before"
}

tip_unchanged() {
  local want
  want="$(staged_tip "$1")"
  [[ -n "$want" && "$(git rev-parse --verify --quiet "refs/heads/$1")" == "$want" ]]
}

head_unchanged() {
  [[ "$(git rev-parse HEAD)" == "$(cat "$snap/head_before")" ]]
}

contains_remote_tip() {
  local want
  want="$(remote_tip "$2" "$3")"
  [[ -n "$want" ]] && git merge-base --is-ancestor "$want" "refs/heads/$1"
}

tip_matches_remote() {
  local want
  want="$(remote_tip "$2" "$3")"
  [[ -n "$want" && "$(git rev-parse --verify --quiet "refs/heads/$1")" == "$want" ]]
}

worktree_as_found() {
  diff <(git status --porcelain=v1 --untracked-files=all) "$snap/status_before"
}

file_content_is() {
  [[ -f "$1" && "$(cat "$1")" == "$2" ]]
}

untracked() {
  ! git ls-files --error-unmatch "$1"
}

no_stash() {
  ! git rev-parse --verify --quiet refs/stash
}

# --- Helper-call predicates --------------------------------------------------

# run.py's logging shim appends "refresh_repo.sh <args>" per call, in call
# order, so a line with no arguments is a default run.
script_log="$target/script_calls.log"

# The line number of the first default run, empty when the log holds none.
first_default_run() {
  [[ -s "$script_log" ]] || return 0
  awk '$1 == "refresh_repo.sh" && NF == 1 { print NR; exit }' "$script_log"
}

default_run_called() {
  [[ -n "$(first_default_run)" ]]
}

prune_gone_after_default_run() {
  local default
  default="$(first_default_run)"
  [[ -n "$default" ]] || return 1
  awk -v after="$default" '
    NR > after && $1 == "refresh_repo.sh" && $2 == "--prune-gone" { found = 1 }
    END { exit !found }
  ' "$script_log"
}

# --- Per-eval checks ---------------------------------------------------------

case "$eval_id" in
  1)
    check "repository ends on the default branch master" on_branch master
    check "master contains the upstream commit origin carries" \
      contains_remote_tip master origin master
    check "master reached that commit by fast-forward: its tip is origin's tip" \
      tip_matches_remote master origin master
    check "the cleanly merged branch merged-topic is deleted" branch_absent merged-topic
    note_response "invoked scripts/refresh_repo.sh rather than hand-running the default git sequence"
    note_response "reported fetch/prune, the detected default branch master, the switch, the fast-forward, and the deleted branch"
    ;;
  2)
    check "the merged branch merged-topic is gone" branch_absent merged-topic
    check "the upstream-gone branch gone-unique still exists" branch_exists gone-unique
    check "gone-unique still carries its unique commit at its staged tip" \
      tip_unchanged gone-unique
    note_response "invoked scripts/refresh_repo.sh with no arguments for the default run"
    note_response "asked a follow-up question before any upstream-gone pruning"
    note_response "listed gone-unique's unique commit before offering force-delete cleanup"
    ;;
  3)
    check "the upstream-gone branch with no commits absent from main, gone-merged, is deleted" \
      branch_absent gone-merged
    check "the upstream-gone branch with a unique commit, gone-unique, still exists" \
      branch_exists gone-unique
    check "no force-delete touched gone-unique: it still points at its staged tip" \
      tip_unchanged gone-unique
    check "the helper log records a default run of refresh_repo.sh with no arguments" \
      default_run_called
    check "the helper log records a refresh_repo.sh --prune-gone call after that default run" \
      prune_gone_after_default_run
    note_response "reported gone-unique as a branch requiring force-delete confirmation"
    ;;
  4)
    check "the current branch work-in-progress is unchanged" on_branch work-in-progress
    check "HEAD still points at its staged commit" head_unchanged
    check "dirty.txt still holds its uncommitted content" file_content_is dirty.txt "dirty"
    check "dirty.txt is still untracked and uncommitted" untracked dirty.txt
    check "worktree left as found" worktree_as_found
    check "no stash entry was created" no_stash
    note_response "invoked scripts/refresh_repo.sh"
    note_response "reported the dirty worktree and the skipped switch or fast-forward steps"
    note_response "ran no reset, checkout-discard, or other command that hides the uncommitted change"
    ;;
  *)
    echo "unknown eval id: $eval_id (valid: 1..4)" >&2
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
