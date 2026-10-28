#!/usr/bin/env bash
# run_restore.sh - return one git_auto_review round's working tree to its
# captured pre-fix state.
#
# The procedure returns the working-tree content of every tracked path to the
# captured pre-fix state while the index keeps the content it held at capture,
# solely from the two artefacts run_snapshot.sh wrote. It never touches
# committed history:
#
#   1. Reset every tracked path's working-tree content to HEAD
#      (`git restore --source=HEAD --worktree -- .`), which leaves the index
#      untouched, so a path that was clean at capture and a fixer edited, and
#      both sides of a rename, return to HEAD. Remove a working-tree file the
#      index knows and HEAD does not; the captured patch re-adds it when the
#      pre-fix state held it.
#   2. Apply `pre-fix.patch` forward into the working tree alone, never with
#      --index or --cached, so the captured worktree content becomes the
#      working-tree state again. An empty patch needs no apply.
#   3. Copy each file in `pre-fix.untracked.tar` back over its working-tree
#      path.
#   4. Delete the untracked files the fixer added that the copy does not
#      contain.
#
# Usage:
#   run_restore.sh [--stem <name>] [--root <dir>]
#
# Exit codes:
#   0  the working tree matches the captured pre-fix state
#   1  usage error
#   2  environment error: the procedure ran and could not reproduce the
#      captured state

set -uo pipefail

EXIT_USAGE=1
EXIT_ENV=2

STEM=""
ROOT=""

usage() {
    cat <<'USAGE'
run_restore.sh - return one git_auto_review round's working tree to its
captured pre-fix state.

Usage:
  run_restore.sh [--stem <name>] [--root <dir>]
  run_restore.sh --help

Behavior:
  - Resolves the repository root with `git rev-parse --show-toplevel`, or uses
    --root when it is given.
  - Uses the run stem from --stem, or `default` when it is absent, and reads
    `.git_auto_review/<stem>/pre-fix.patch` and
    `.git_auto_review/<stem>/pre-fix.untracked.tar`.
  - Resets every tracked path's working-tree content to HEAD, removes the
    working-tree files the index knows and HEAD does not, replays the captured
    patch, and deletes the untracked files the fixer added that the captured
    copy does not contain, while the index keeps the content it held at
    capture.

Exit codes:
  0  the working tree matches the captured pre-fix state
  1  usage error
  2  environment error: could not reproduce the captured state
USAGE
}

die() {
    printf 'git_auto_review: %s\n' "$*" >&2
    exit "$EXIT_USAGE"
}

die_env() {
    printf 'git_auto_review: %s\n' "$*" >&2
    exit "$EXIT_ENV"
}

# Print the paths the index tracks, one per line.
index_paths() {
    (cd "$1" && git ls-files)
}

# Remove the working-tree files the index tracks but HEAD does not. Their
# captured content returns from the patch in step 2, so the index keeps its
# content while the pre-fix working tree is reproduced.
remove_head_absent_paths() {
    local repo_root=$1 path
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        if (cd "$repo_root" && git cat-file -e "HEAD:$path" 2>/dev/null); then
            continue
        fi
        rm -f -- "$repo_root/$path" || return 1
    done < <(index_paths "$repo_root")
    return 0
}

# Write the tar's member paths to the file named by the second argument, one
# NUL-delimited record per member. The archive is unpacked into a scratch
# directory and walked there, because a `tar -tf` listing separates member names
# with newlines and so cannot carry a name that holds one.
tar_members() {
    local tar_file=$1 dest=$2 probe
    probe="$(mktemp -d "${TMPDIR:-/tmp}/git_auto_review.XXXXXX")" || return 1
    if ! (cd "$probe" && tar -xf "$tar_file") 2>/dev/null; then
        rm -rf "$probe"
        return 1
    fi
    (cd "$probe" && find . \( -type f -o -type l \) -print0) \
        | while IFS= read -r -d '' member; do
            printf '%s\0' "${member#./}"
        done > "$dest"
    rm -rf "$probe"
}

# Report whether the candidate path is one of the NUL-delimited member records
# in the file named by the first argument.
member_listed() {
    local members=$1 candidate=$2 member
    while IFS= read -r -d '' member; do
        [[ "$member" == "$candidate" ]] && return 0
    done < "$members"
    return 1
}

main() {
    while (($# > 0)); do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --stem) STEM="${2:?--stem needs a name}"; shift 2 ;;
            --root) ROOT="${2:?--root needs a directory}"; shift 2 ;;
            *) die "unknown argument: $1" ;;
        esac
    done

    local repo_root
    if [[ -n "$ROOT" ]]; then
        [[ -d "$ROOT" ]] || die_env "root is not a directory: $ROOT"
        repo_root="$(cd "$ROOT" && pwd)"
    else
        command -v git >/dev/null 2>&1 || die_env "git was not found on PATH"
        repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
            || die_env "not inside a git repository"
    fi
    STEM="${STEM:-default}"

    local stem_dir="$repo_root/.git_auto_review/$STEM"
    local patch="$stem_dir/pre-fix.patch"
    local untracked_tar="$stem_dir/pre-fix.untracked.tar"
    [[ -f "$patch" ]] || die_env "pre-fix.patch not found: $patch"
    [[ -f "$untracked_tar" ]] \
        || die_env "pre-fix.untracked.tar not found: $untracked_tar"

    # Step 1: reset every tracked path's working-tree content to HEAD, leaving
    # the index untouched, then remove the index-known paths HEAD does not hold.
    (cd "$repo_root" && git restore --source=HEAD --worktree -- .) \
        || die_env "cannot reset the tracked working tree to HEAD"
    remove_head_absent_paths "$repo_root" \
        || die_env "cannot remove a working-tree file HEAD does not hold"

    # Step 2: apply the captured patch forward into the working tree alone. An
    # empty patch, written from a clean pre-fix tree, has nothing to apply.
    if [[ -s "$patch" ]]; then
        (cd "$repo_root" && git apply -- "$patch") \
            || die_env "cannot re-apply the captured patch into the working tree"
    fi

    # Step 3: copy the captured untracked files back over their paths.
    (cd "$repo_root" && tar -xf "$untracked_tar") \
        || die_env "cannot restore the captured untracked files"

    # Step 4: delete the untracked files the fixer added that the captured copy
    # does not contain.
    local members current record
    members="$(mktemp "${TMPDIR:-/tmp}/git_auto_review.XXXXXX")"
    if ! tar_members "$untracked_tar" "$members"; then
        rm -f "$members"
        die_env "cannot list the captured untracked files"
    fi
    while IFS= read -r -d '' record; do
        case "$record" in
            "?? "*) current="${record#\?\? }" ;;
            *) continue ;;
        esac
        if member_listed "$members" "$current"; then
            continue
        fi
        rm -f -- "$repo_root/$current" \
            || die_env "cannot remove the fixer-added untracked file $current"
    done < <(cd "$repo_root" && git status --porcelain -z --untracked-files=all)
    rm -f "$members"

    # Verify the captured tracked content is reproduced: re-deriving the round's
    # tracked patch must yield the captured patch byte for byte.
    local derived
    derived="$(mktemp "${TMPDIR:-/tmp}/git_auto_review.XXXXXX")"
    (cd "$repo_root" && git diff HEAD --binary --no-color --no-ext-diff) \
        > "$derived"
    if ! cmp -s "$derived" "$patch"; then
        rm -f "$derived"
        die_env "restored working tree does not reproduce the captured state"
    fi
    rm -f "$derived"

    printf 'Working tree restored to the captured pre-fix state under %s\n' \
        "$stem_dir"
    printf '%s\n' "$stem_dir"
    exit 0
}

main "$@"
