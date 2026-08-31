#!/usr/bin/env bash
# Shared helpers for task-family eval fixtures.
#
# Each fixture sources this file, then calls `new_project "$target"` (or
# `new_project "$target" --git`) to get a fresh sandbox project whose
# backlog lives at <proj>/tasks/. The project carries a discovery marker
# (CLAUDE.md for git projects, .project-root otherwise) so the skill's
# discover_tasks.sh resolves the sandbox — never the surrounding repo.

set -euo pipefail

# new_project <target> [--git] -> wipes <target>, creates <target>/proj
# with tasks/ + tasks/archive/, prints the absolute proj path. With
# --git the project is a committable git repo (needed by close-out and
# implement evals that rely on `git mv` / a test suite).
new_project() {
    local target="$1"; shift || true
    local want_git=0
    [[ "${1:-}" == "--git" ]] && want_git=1
    rm -rf "$target"
    mkdir -p "$target"
    local proj="$target/proj"
    mkdir -p "$proj/tasks/archive"
    if (( want_git )); then
        git -C "$proj" init -q --initial-branch=main
        git -C "$proj" config user.email "evals@example.com"
        git -C "$proj" config user.name "Evals"
        : > "$proj/CLAUDE.md"
    else
        : > "$proj/.project-root"
    fi
    (cd "$proj" && pwd -P)
}

# now_iso -> ISO 8601 local timestamp matching the skill's stamp format.
now_iso() { date +%Y-%m-%dT%H:%M:%S; }

# git_commit_all <proj> <message> -> stage and commit the whole tree so a
# later `git status --porcelain` cleanly reveals what the agent changed.
git_commit_all() {
    local proj="$1" msg="$2"
    git -C "$proj" add -A
    git -C "$proj" commit -q -m "$msg"
}
