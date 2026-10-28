#!/usr/bin/env bash
# run_restore.sh - return one git_auto_review round's working tree to its
# captured pre-fix state.
#
# The procedure returns the working-tree content of every captured tracked
# path to the captured pre-fix state while the index keeps the content it held
# at capture, solely from the two artefacts run_snapshot.sh wrote. It never
# touches committed history:
#
#   1. For each tracked path `pre-fix.patch` carries, set its working-tree
#      content to HEAD (`git restore --source=HEAD --worktree` or a
#      `git show HEAD:<path>` write), which leaves the index untouched, and
#      remove a path whose a-side is /dev/null.
#   2. Apply `pre-fix.patch` forward into the working tree alone, never with
#      --index or --cached, so the captured worktree content becomes the
#      working-tree state again.
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
  - Reproduces the captured working-tree content of every captured tracked
    path while the index keeps the content it held at capture, and deletes the
    untracked files the fixer added that the captured copy does not contain.

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

# Print the tracked paths pre-fix.patch carries, one per line.
patch_paths() {
    local patch=$1
    git apply --numstat -- "$patch" 2>/dev/null \
        | awk '{ $1=""; $2=""; sub(/^  /, ""); print }'
}

reset_path_to_head() {
    local repo_root=$1 path=$2
    if (cd "$repo_root" && git cat-file -e "HEAD:$path" 2>/dev/null); then
        (cd "$repo_root" && git restore --source=HEAD --worktree -- "$path") \
            || return 1
    else
        # The patch's a-side is /dev/null: HEAD holds no such path, so the
        # captured state has no working-tree file at it.
        rm -f -- "$repo_root/$path" || return 1
    fi
    return 0
}

# Extract the tar's member paths, one per line.
tar_members() {
    local tar_file=$1
    tar -tf "$tar_file" 2>/dev/null
}

member_listed() {
    local members=$1 candidate=$2 member
    while IFS= read -r member; do
        [[ "$member" == "$candidate" ]] && return 0
        # tar may store a directory member with a trailing slash.
        [[ "${member%/}" == "$candidate" ]] && return 0
    done <<< "$members"
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

    # Step 1: reset every captured tracked path's working-tree content to HEAD,
    # leaving the index untouched.
    local path
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        reset_path_to_head "$repo_root" "$path" \
            || die_env "cannot reset working-tree content for $path"
    done < <(patch_paths "$patch")

    # Step 2: apply the captured patch forward into the working tree alone.
    (cd "$repo_root" && git apply -- "$patch") \
        || die_env "cannot re-apply the captured patch into the working tree"

    # Step 3: copy the captured untracked files back over their paths.
    (cd "$repo_root" && tar -xf "$untracked_tar") \
        || die_env "cannot restore the captured untracked files"

    # Step 4: delete the untracked files the fixer added that the captured copy
    # does not contain.
    local members current record
    members="$(tar_members "$untracked_tar")"
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
