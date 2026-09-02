#!/usr/bin/env bash

set -euo pipefail

setup_identity() {
    git config user.email "harness@example.com"
    git config user.name "Harness"
}

# Seed a bare repository with one commit on its default branch, so later clones
# never see an empty repository.
seed_bare() {
    local bare=$1
    local branch=$2
    local work

    git init --quiet --bare --initial-branch="$branch" "$bare"
    work="$(mktemp -d)"
    git clone --quiet "$bare" "$work/seed" 2>/dev/null
    (
        cd "$work/seed"
        setup_identity
        printf 'seed\n' > seed.txt
        git add seed.txt
        git commit --quiet -m "seed"
        git push --quiet -u origin "$branch"
    )
    rm -rf "$work"
}

# Stage a fixture root holding one bare origin and one clone of it.
init_remote_repo() {
    local target=$1
    local default_branch=$2
    local repo="$target/repo"

    rm -rf "$target"
    mkdir -p "$target"
    seed_bare "$target/origin.git" "$default_branch"
    git clone --quiet "$target/origin.git" "$repo" 2>/dev/null
    (
        cd "$repo"
        setup_identity
        git remote set-head origin "$default_branch"
    )
    printf '%s\n' "$repo"
}

# Push a branch into a bare repository from a throwaway clone, so the fixture's
# own clone has never fetched it.
push_branch_from_side() {
    local bare=$1
    local base=$2
    local branch=$3
    local file=$4
    local content=$5
    local work

    work="$(mktemp -d)"
    git clone --quiet "$bare" "$work/side" 2>/dev/null
    (
        cd "$work/side"
        setup_identity
        git checkout --quiet "$base"
        git checkout --quiet -b "$branch"
        printf '%s\n' "$content" > "$file"
        git add "$file"
        git commit --quiet -m "$branch work"
        git push --quiet -u origin "$branch"
    )
    rm -rf "$work"
}
