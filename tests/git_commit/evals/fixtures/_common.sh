#!/usr/bin/env bash
# Shared helpers for git_commit eval fixtures.
#
# Each fixture sources this file, then calls `init_sandbox "$1"` to get
# a fresh git repo at the target dir with one seed commit.

set -euo pipefail

init_sandbox() {
    local target="$1"
    if [[ -z "$target" ]]; then
        echo "init_sandbox: target dir is required" >&2
        return 2
    fi
    rm -rf "$target"
    mkdir -p "$target"
    (
        cd "$target"
        git init --quiet --initial-branch=main
        git config user.email "evals@example.com"
        git config user.name "Evals"
        printf 'seed\n' > seed.txt
        git add seed.txt
        git commit --quiet -m "seed"
    )
}
