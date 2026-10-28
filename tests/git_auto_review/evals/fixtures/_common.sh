#!/usr/bin/env bash
# Shared helpers for git_auto_review behavioral fixtures.
#
# A fixture stages one git repository and, when the eval drives a canned gate
# result, one marked pre-seeded gate-return pair under the run's relay. Every
# fixture stages its own sandbox, so no eval touches the host repository.

set -euo pipefail

# init_repo <target>
#
# Creates <target>/repo as a git repository at the stub-remote shape the
# default-branch walk needs: a `main` branch, an `origin` remote, a
# `refs/remotes/origin/HEAD` symref, and one base commit.
init_repo() {
  local target=$1
  rm -rf "$target/repo"
  mkdir -p "$target/repo"
  (
    cd "$target/repo"
    git init --quiet --initial-branch=main
    git config user.name "Harness"
    git config user.email "harness@example.test"
    git remote add origin "$target/repo"
    git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  )
}

# commit_repo <target> <message>
commit_repo() {
  local target=$1 message=${2:-"fixture base"}
  (
    cd "$target/repo"
    git add -A
    git commit --quiet -m "$message"
    git update-ref refs/remotes/origin/main HEAD
  )
}

# seed_in_scope_change <target>
#
# Adds one tracked file with an in-scope uncommitted change on the working-tree
# lane: a wrong result the review can flag and the fixer can repair. The file
# is committed so the change is a working-tree edit, not a new untracked file.
seed_in_scope_change() {
  local target=$1
  (
    cd "$target/repo"
    cat > report.py <<'EOF'
def total(items):
    """Sum the item values."""
    return sum(items) - 1
EOF
  )
  commit_repo "$target" "fixture base"
  (
    cd "$target/repo"
    cat > report.py <<'EOF'
def total(items):
    """Sum the item values."""
    return sum(items) - 2
EOF
    printf 'unrelated pre-existing defect\n' > legacy.py
  )
  commit_repo "$target" "seed an unrelated file"
  (
    cd "$target/repo"
    cat > report.py <<'EOF'
def total(items):
    """Sum the item values."""
    return sum(items) + 10
EOF
  )
}

# stem_for <task_relpath>
# The relay stem the skill derives from an optional task file path.
stem_for() {
  local base="${1##*/}"
  printf '%s' "${base%.*}"
}

# relay_dir <target> <stem>
relay_dir() {
  printf '%s/repo/.git_auto_review/%s' "$1" "${2:-default}"
}

# preseed_gate <target> <stem> <round> <gate-body-file>
#
# Stages one marked pre-seeded gate-return pair: `gate-r<round>.txt` plus the
# empty `gate-r<round>.preseed` marker beside it. The runner's init preserves
# the pair, and the loop consumes it in place of a gate invocation.
preseed_gate() {
  local target=$1 stem=$2 round=$3 body=$4
  local dir
  dir="$(relay_dir "$target" "$stem")"
  mkdir -p "$dir"
  cp "$body" "$dir/gate-r$round.txt"
  : > "$dir/gate-r$round.preseed"
}

# record_index <target>
# Writes the staged index state to <target>/.index.before for a byte check.
record_index() {
  local target=$1
  (cd "$target/repo" && git ls-files -s) > "$target/.index.before"
}

# record_head <target>
record_head() {
  local target=$1
  (cd "$target/repo" && git rev-parse HEAD) > "$target/.head.before"
}

# seed_task_file <target> <relpath> [goal]
#
# Writes the task file a fixture's prompt names into the sandbox repository, so
# the worker resolves the path it was given inside its own working directory
# instead of searching the host checkout for it. The pre-seeded gate return
# carries the findings. Its Goal and Acceptance must therefore admit every
# module those returns cite — each seeded helper's returned value — because a
# narrower anchor makes `auto_verifier_git` triage refuse the whole set as a
# scope extension and the run stops on "the approved set is empty" before it
# reaches the ledger, unmapped-hunk, or self-written path the eval proves.
# Fixtures whose findings a narrower or wider anchor must admit pass that Goal
# text as the optional third argument; the default covers the plain "each
# helper returns its documented value" shape every other fixture uses.
seed_task_file() {
  local target=$1 rel=$2 goal=${3:-}
  if [[ -z "$goal" ]]; then
    goal="Keep each seeded helper's returned value correct without changing the
shipped interface."
  fi
  mkdir -p "$target/repo/$(dirname "$rel")"
  cat > "$target/repo/$rel" <<TASK
---
description: "Fixture task anchoring the scope of this run"
status: ready
---

# Fixture run anchor

## Goal

$goal

## Acceptance

1. Each seeded helper returns the value its docstring documents.
TASK
  (
    cd "$target/repo"
    git add "$rel"
    git commit --quiet -m "seed the anchoring task file"
    git update-ref refs/remotes/origin/main HEAD
  )
}
