#!/usr/bin/env bash
# Reproduction for the round-1 finding on run_snapshot.sh: a tree carrying an
# untracked file whose name holds a newline must snapshot and restore.
#
# Before the fix, list_untracked printed newline-delimited paths and
# write_untracked_tar fed that list to `tar -T`, so the name split into two
# list lines, tar reported `Cannot stat` for each fragment, and the snapshot
# exited 2. The restore-side `tar -tf` listing could not represent the name
# either. This script stages its own git sandbox under a temporary directory,
# so it never touches the host repository's working tree.
#
# Exit codes:
#   0  the snapshot and the restore both survive a newline in a filename
#   1  either step failed, or the restored tree is wrong

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SCRIPTS="$REPO_ROOT/plugins/ai_dev/skills/git_auto_review/scripts"

work="$(mktemp -d "${TMPDIR:-/tmp}/git_auto_review_repro.XXXXXX")"
trap 'rm -rf "$work"' EXIT

fail() {
    printf 'repro: %s\n' "$*" >&2
    exit 1
}

repo="$work/repo"
mkdir -p "$repo"
(
    set -e
    cd "$repo"
    git init --quiet --initial-branch=main
    git config user.name "Harness"
    git config user.email "harness@example.test"
    printf 'base\n' > tracked.txt
    git add tracked.txt
    git commit --quiet -m "base"
) || fail "cannot stage the sandbox repository"

newline_name=$'weird\nname.txt'
printf 'n1\nn2\n' > "$repo/$newline_name"

bash "$SCRIPTS/run_relay.sh" --root "$repo" >"$work/relay.log" 2>&1 \
    || fail "run_relay.sh failed"

if ! bash "$SCRIPTS/run_snapshot.sh" --stem default --root "$repo" \
    >"$work/snapshot.log" 2>&1; then
    cat "$work/snapshot.log" >&2
    fail "run_snapshot.sh failed on an untracked filename holding a newline"
fi

stem="$repo/.git_auto_review/default"
mkdir -p "$work/extract"
tar -xf "$stem/pre-fix.untracked.tar" -C "$work/extract" 2>/dev/null \
    || fail "cannot unpack the snapshot archive"
[[ -f "$work/extract/$newline_name" ]] \
    || fail "the snapshot did not archive the newline-named path as one member"

# The restore must put the newline-named file back and delete an untracked file
# the fixer added, which is where the member listing is read.
printf 'fixer\n' > "$repo/tracked.txt"
printf 'fixer added\n' > "$repo/fixer-added.txt"
if ! bash "$SCRIPTS/run_restore.sh" --stem default --root "$repo" \
    >"$work/restore.log" 2>&1; then
    cat "$work/restore.log" >&2
    fail "run_restore.sh failed on an untracked filename holding a newline"
fi
[[ -f "$repo/$newline_name" ]] \
    || fail "the restore did not put the newline-named file back"
[[ "$(cat "$repo/tracked.txt")" == "base" ]] \
    || fail "the restore did not return the tracked path to HEAD"
[[ ! -e "$repo/fixer-added.txt" ]] \
    || fail "the restore did not delete the fixer-added untracked file"

printf 'repro: newline-named untracked path survived snapshot and restore\n'
