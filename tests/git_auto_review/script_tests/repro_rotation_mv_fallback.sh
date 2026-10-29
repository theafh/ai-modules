#!/usr/bin/env bash
# Reproduction for the round-1 finding on `<fix_log_rotation>`: the rotation
# move must fall back to plain `mv` when `git mv` cannot run.
#
# Before the fix, the block named `git mv` as the only rename route. `git mv`
# exits 128 both outside a repository (`fatal: not a git repository`) and on an
# untracked file inside one (`fatal: not under version control`), so a non-git
# wiki and an untracked log both handed the agent a rotation finding it could
# never clear.
#
# The check reads the prompt block and asserts the tracked probe it must now
# carry, then runs the procedure that block states over the four cases:
# a non-git wiki, an untracked log in a repository, a tracked log, and an
# occupied archive name. Every case stages its own temporary directory, so
# nothing touches the host tree.
#
# The fourth case pins the no-clobber guarantee on the fallback route: `git mv`
# refuses an occupied destination, but a plain `mv` replaces it, so the block
# must name a guard that makes the fallback refuse too. Before that guard the
# fallback silently destroyed the archive, which is the history loss the
# rotation exists to prevent.
#
# Exit codes:
#   0  the block states the tracked-probe fallback and its no-clobber guard,
#      and all four moves behave as stated
#   1  the block lacks the fallback or the guard, or a move misbehaved

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AGENT="$REPO_ROOT/plugins/knowledge_management/agents/auto_shaper_wiki.md"

work="$(mktemp -d "${TMPDIR:-/tmp}/rotation_repro.XXXXXX")"
trap 'rm -rf "$work"' EXIT

fail() {
    printf 'repro: %s\n' "$*" >&2
    exit 1
}

[[ -f "$AGENT" ]] || fail "agent file not found: $AGENT"

block="$work/rotation_block.txt"
awk '/<fix_log_rotation>/{on=1} on{print} /<\/fix_log_rotation>/{on=0}' \
    "$AGENT" > "$block"
[[ -s "$block" ]] || fail "no <fix_log_rotation> block in $AGENT"

# The discriminating property: the move is gated on a tracked probe that also
# settles the non-repository case, and plain `mv` is the named fallback.
grep -Fq -- 'git ls-files --error-unmatch' "$block" \
    || fail "the rotation move states no tracked probe"
grep -Fq -- 'git mv' "$block" \
    || fail "the rotation move no longer names git mv"
grep -Fq -- 'mv' "$block" \
    || fail "the rotation move names no fallback"
# The no-clobber guard on the fallback route: the block must refuse an occupied
# destination explicitly, because plain `mv` replaces one.
grep -Fq -- '[ -e "$archive" ]' "$block" \
    || fail "the fallback move states no occupied-destination guard"
grep -Fq -- 'mv -n' "$block" \
    || fail "the fallback move states no no-clobber flag"
# The preamble guarantee: rotation must carry the live preamble rather than
# restore canonical template text, so an owner-added line survives the move.
grep -Fq -- 'live `log.md`' "$block" \
    || fail "the rotation move does not name the live preamble"
if grep -Fq -- 'canonical preamble from' "$block"; then
    fail "the rotation move still restores canonical preamble text"
fi

# The move a wiki owner's added preamble line must survive rotation.
preamble_case() {
    local dir=$1
    mkdir -p "$dir"
    {
        printf '# Wiki Log\n\n'
        printf '> Chronological record of wiki changes. Append-only.\n'
        printf '> House rule: cite a source on every concept page.\n'
        printf '\n## [2026-01-01 00:00] note | a\n'
    } > "$dir/log.md"
    # Rotation as the block states it: carry the live preamble verbatim.
    local preamble
    preamble=$(sed -n '1,/^## /{/^## /d;p;}' "$dir/log.md")
    printf '%s\n\n' "$preamble" > "$dir/log.md.new"
    printf '## [2026-06-01 00:00] rotate | rotated\n' >> "$dir/log.md.new"
    mv "$dir/log.md.new" "$dir/log.md"
    grep -Fq 'House rule: cite a source' "$dir/log.md" \
        || fail "rotation dropped the owner's preamble line"
}
preamble_case "$work/preamble"

# Run the move the block now prescribes: probe, then git mv or the guarded
# plain mv.
rotate() {
    local wiki=$1 archive=$2 branch
    if (cd "$wiki" && git ls-files --error-unmatch log.md >/dev/null 2>&1); then
        branch="git mv"
        (cd "$wiki" && git mv log.md "$archive") || return 1
    else
        branch="mv"
        (
            cd "$wiki" || exit 1
            if [ -e "$archive" ]; then exit 1; fi
            mv -n log.md "$archive"
        ) || return 1
    fi
    printf '%s' "$branch"
}

stage_wiki() {
    local dir=$1
    mkdir -p "$dir"
    printf '## [2026-01-01 00:00] note | a\n' > "$dir/log.md"
}

# Case 1: a non-git wiki.
plain="$work/plain"
stage_wiki "$plain"
branch=$(rotate "$plain" log-2026.md) || fail "rotation failed on a non-git wiki"
[[ "$branch" == "mv" ]] || fail "a non-git wiki took $branch"
[[ -f "$plain/log-2026.md" ]] || fail "the non-git archive is missing"
[[ ! -e "$plain/log.md" ]] || fail "the non-git log was left behind"

# Case 2: an untracked log inside a repository.
untracked="$work/untracked"
stage_wiki "$untracked"
(
    set -e
    cd "$untracked"
    git init --quiet --initial-branch=main
    git config user.name "Harness"
    git config user.email "harness@example.test"
    printf 'base\n' > tracked.txt
    git add tracked.txt
    git commit --quiet -m "base"
) || fail "cannot stage the untracked-log repository"
branch=$(rotate "$untracked" log-2026.md) || fail "rotation failed on an untracked log"
[[ "$branch" == "mv" ]] || fail "an untracked log took $branch"
[[ -f "$untracked/log-2026.md" ]] || fail "the untracked archive is missing"

# Case 3: a tracked log keeps the rename.
tracked="$work/tracked"
stage_wiki "$tracked"
(
    set -e
    cd "$tracked"
    git init --quiet --initial-branch=main
    git config user.name "Harness"
    git config user.email "harness@example.test"
    git add log.md
    git commit --quiet -m "base"
) || fail "cannot stage the tracked-log repository"
branch=$(rotate "$tracked" log-2026.md) || fail "rotation failed on a tracked log"
[[ "$branch" == "git mv" ]] || fail "a tracked log took $branch"
(cd "$tracked" && git status --porcelain | grep -Fq 'R  log.md -> log-2026.md') \
    || fail "git did not record the tracked move as a rename"

# Case 4: an occupied archive name refuses on both routes and loses nothing.
# The resolved name is free by construction, so this is the stale-resolution
# path: a hard failure here is the guarantee, and a silent replacement is the
# history loss the rotation exists to prevent.
occupied_plain="$work/occupied-plain"
stage_wiki "$occupied_plain"
printf '## [2025-01-01 00:00] note | older\n' > "$occupied_plain/log-2026.md"
if branch=$(rotate "$occupied_plain" log-2026.md); then
    fail "the plain-mv fallback replaced an occupied archive via $branch"
fi
grep -Fq 'older' "$occupied_plain/log-2026.md" \
    || fail "the fallback destroyed the occupied archive's history"
[[ -f "$occupied_plain/log.md" ]] \
    || fail "the fallback removed the log it refused to move"

occupied_tracked="$work/occupied-tracked"
stage_wiki "$occupied_tracked"
printf '## [2025-01-01 00:00] note | older\n' > "$occupied_tracked/log-2026.md"
(
    set -e
    cd "$occupied_tracked"
    git init --quiet --initial-branch=main
    git config user.name "Harness"
    git config user.email "harness@example.test"
    git add log.md log-2026.md
    git commit --quiet -m "base"
) || fail "cannot stage the occupied-archive repository"
if branch=$(rotate "$occupied_tracked" log-2026.md); then
    fail "the git-mv route replaced an occupied archive via $branch"
fi
grep -Fq 'older' "$occupied_tracked/log-2026.md" \
    || fail "git mv destroyed the occupied archive's history"
[[ -f "$occupied_tracked/log.md" ]] \
    || fail "git mv removed the log it refused to move"

printf 'repro: rotation falls back to mv off-git and on an untracked log\n'
printf 'repro: rotation refuses an occupied archive on both routes\n'
