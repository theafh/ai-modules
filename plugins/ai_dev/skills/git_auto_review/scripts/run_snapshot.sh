#!/usr/bin/env bash
# run_snapshot.sh - write one git_auto_review round's pre-fix snapshot.
#
# Writes the three restore artefacts run_restore.sh replays: `pre-fix.patch`,
# the patch of the round's tracked changes with the index and the worktree
# read together (`git diff HEAD --binary --no-color --no-ext-diff`);
# `pre-fix.untracked.tar`, a copy of the untracked files present before the
# fix (enumerated with `git status --porcelain --untracked-files=all`, ignored
# paths excluded); and `pre-fix.ignored.manifest`, the ignored files present
# before the fix as NUL-delimited path-plus-content-hash records, enumerated
# with `git ls-files --others --ignored --exclude-standard -z`. The ignored
# enumeration leaves out the run's own `.git_auto_review/` folder and the
# harness run-output trees this repository regenerates.
#
# On the round where the run's baseline pair is absent it also writes
# `baseline.patch` and `baseline.untracked.tar` once and never rewrites them,
# so a later round rewrites only the `pre-fix.*` files.
#
# Usage:
#   run_snapshot.sh [--stem <name>] [--root <dir>]
#
# Exit codes:
#   0  the snapshot is written; the stem directory path is the last stdout line
#   1  usage error
#   2  environment error (git missing, not in a repository, or a write failed)

set -uo pipefail

EXIT_USAGE=1
EXIT_ENV=2

STEM=""
ROOT=""

usage() {
    cat <<'USAGE'
run_snapshot.sh - write one git_auto_review round's pre-fix snapshot.

Usage:
  run_snapshot.sh [--stem <name>] [--root <dir>]
  run_snapshot.sh --help

Behavior:
  - Resolves the repository root with `git rev-parse --show-toplevel`, or uses
    --root when it is given.
  - Uses the run stem from --stem, or `default` when it is absent, and writes
    under `.git_auto_review/<stem>/`.
  - Rewrites `pre-fix.patch`, `pre-fix.untracked.tar`, and
    `pre-fix.ignored.manifest` for the round.
  - Writes the ignored manifest as NUL-delimited path-plus-content-hash
    records for the ignored files outside the run's `.git_auto_review/`
    folder and outside the harness run-output trees under `tests/`.
  - Writes `baseline.patch` and `baseline.untracked.tar` once, only when that
    pair is absent, and never rewrites it.

Exit codes:
  0  snapshot written; the stem directory path is the last stdout line
  1  usage error
  2  environment error
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

# Report success when the repository-root-relative path lies under the run's
# own `.git_auto_review/` folder or under a harness run-output tree this
# repository regenerates. The ignored manifest, the round diff, and Restore
# all read this one exclusion.
is_run_owned_path() {
    local path=$1 rest
    case "$path" in
        .git_auto_review/*) return 0 ;;
        tests/*) ;;
        *) return 1 ;;
    esac
    rest="/${path#tests/}/"
    case "$rest" in
        */workspace/*|*/scratch/*|*/.eval_cache/*|*/results/*|*/.vendor_probe/*)
            return 0 ;;
    esac
    case "$path" in
        tests/wiki/layer2/AS-*|tests/wiki/layer2/L2-*|tests/wiki/layer2/WI-*|tests/wiki/layer2/WU-*|tests/wiki/layer2/MP-*)
            return 0 ;;
    esac
    return 1
}

# Print one untracked path per NUL-delimited record, so a path holding a space
# or a newline survives the whole round trip, and never a path git considers
# ignored.
list_untracked() {
    local repo_root=$1
    (cd "$repo_root" && git status --porcelain -z --untracked-files=all) \
        | while IFS= read -r -d '' record; do
            case "$record" in
                "?? "*) printf '%s\0' "${record#\?\? }" ;;
            esac
        done
}

# Print one ignored path per NUL-delimited record, leaving out the run's own
# `.git_auto_review/` folder and the harness run-output trees.
list_ignored() {
    local repo_root=$1 path
    (cd "$repo_root" && git ls-files --others --ignored --exclude-standard -z) \
        | while IFS= read -r -d '' path; do
            is_run_owned_path "$path" && continue
            printf '%s\0' "$path"
        done
}

# Hash one file's content with SHA-256, using whichever of the two standing
# tools this machine carries.
file_hash() {
    local file=$1
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    else
        return 1
    fi
}

# Write the ignored manifest as NUL-delimited path-plus-content-hash records.
# The hash is best-effort: no consumer reads it, so a path this machine cannot
# hash still records its path instead of failing the snapshot.
write_ignored_manifest() {
    local repo_root=$1 dest=$2 path hash
    : > "$dest" || return 1
    while IFS= read -r -d '' path; do
        hash="$(file_hash "$repo_root/$path")" || hash=""
        printf '%s\0%s\0' "$path" "$hash" >> "$dest" || return 1
    done < <(list_ignored "$repo_root")
    return 0
}

# Write a tar of the listed untracked paths, one NUL-delimited path per record
# on stdin, with paths stored relative to the repository root. `tar --null`
# reads the list as NUL-delimited too, so a name holding a newline stays one
# member instead of splitting into two. An empty list still writes a valid
# empty archive.
write_untracked_tar() {
    local repo_root=$1 dest=$2 list
    list="$(mktemp "${TMPDIR:-/tmp}/git_auto_review.XXXXXX")"
    cat > "$list"
    tar --null -cf "$dest" -C "$repo_root" -T "$list" || {
        rm -f "$list"
        return 1
    }
    rm -f "$list"
}

write_tracked_patch() {
    local repo_root=$1 dest=$2
    (cd "$repo_root" && git diff HEAD --binary --no-color --no-ext-diff) \
        > "$dest"
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
    mkdir -p "$stem_dir" || die_env "cannot create $stem_dir"

    write_tracked_patch "$repo_root" "$stem_dir/pre-fix.patch" \
        || die_env "cannot write pre-fix.patch"
    list_untracked "$repo_root" \
        | write_untracked_tar "$repo_root" "$stem_dir/pre-fix.untracked.tar" \
        || die_env "cannot write pre-fix.untracked.tar"
    write_ignored_manifest "$repo_root" "$stem_dir/pre-fix.ignored.manifest" \
        || die_env "cannot write pre-fix.ignored.manifest"

    if [[ ! -f "$stem_dir/baseline.patch" \
        || ! -f "$stem_dir/baseline.untracked.tar" ]]; then
        write_tracked_patch "$repo_root" "$stem_dir/baseline.patch" \
            || die_env "cannot write baseline.patch"
        list_untracked "$repo_root" \
            | write_untracked_tar "$repo_root" \
                "$stem_dir/baseline.untracked.tar" \
            || die_env "cannot write baseline.untracked.tar"
    fi

    printf 'Snapshot written under %s\n' "$stem_dir"
    printf '%s\n' "$stem_dir"
}

main "$@"
