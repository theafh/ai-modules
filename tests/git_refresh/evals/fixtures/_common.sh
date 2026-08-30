#!/usr/bin/env bash

set -euo pipefail

setup_identity() {
    git config user.email "harness@example.com"
    git config user.name "Harness"
}

init_remote_repo() {
    local target=$1
    local default_branch=$2
    local origin="$target/origin.git"
    local repo="$target/repo"

    rm -rf "$target"
    mkdir -p "$target"
    git init --quiet --bare --initial-branch="$default_branch" "$origin"
    git clone --quiet "$origin" "$repo"
    (
        cd "$repo"
        setup_identity
        printf 'seed\n' > seed.txt
        git add seed.txt
        git commit --quiet -m "seed"
        git push --quiet -u origin "$default_branch"
        git remote set-head origin "$default_branch"
    )
    printf '%s\n' "$repo"
}
