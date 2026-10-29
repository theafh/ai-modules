#!/usr/bin/env bash
# run_relay.sh - initialise one git_auto_review run's relay directory.
#
# Creates the repository-root `.git_auto_review/.gitignore` holding the sole
# line `*`, creates the run-stem directory, clears every file an earlier run
# left there except the deliberately pre-seeded marked gate-return pairs, and
# writes the empty ledger the run's first fixer appends to.
#
# The stem is the optional task file's basename without its extension, or
# `default` when no task file is given. A task path that does not resolve to a
# readable regular file is rejected as an environment error before any relay
# state is created.
#
# Usage:
#   run_relay.sh [--task <path>] [--root <dir>]
#
# Exit codes:
#   0  the relay is initialised; the stem directory path is the last stdout line
#   1  usage error
#   2  environment error (git missing, or not inside a git repository)

set -uo pipefail

EXIT_USAGE=1
EXIT_ENV=2

TASK=""
ROOT=""

usage() {
    cat <<'USAGE'
run_relay.sh - initialise one git_auto_review run's relay directory.

Usage:
  run_relay.sh [--task <path>] [--root <dir>]
  run_relay.sh --help

Behavior:
  - Resolves the repository root with `git rev-parse --show-toplevel`, or uses
    --root when it is given (-C style override for harnesses).
  - Derives the run stem from --task's basename without its extension, or
    `default` when --task is absent.
  - Rejects --task as an environment error before creating any relay state
    when the path does not resolve to a readable regular file, resolving a
    relative value against the repository root.
  - Writes `.git_auto_review/.gitignore` with the sole line `*`, creating the
    `.git_auto_review/` directory as part of that write.
  - Creates `.git_auto_review/<stem>/` and clears every file an earlier run
    left there, preserving one marked pair per pre-seeded round:
    `gate-r<round>.txt` beside an empty `gate-r<round>.preseed` marker.
  - Writes an empty `ledger.txt` under the stem, zero reproduction lines.

Exit codes:
  0  initialised; the stem directory path is the last stdout line
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

# A marked pre-seeded pair is a `gate-r<round>.txt` whose sibling
# `gate-r<round>.preseed` exists. Presence of the marker alone selects the
# pair, and the pair survives the clear so the round consumes it in place of a
# gate invocation.
is_marked_pair() {
    local repo_root=$1 stem=$2 name=$3 base
    case "$name" in
        gate-r*.txt) ;;
        gate-r*.preseed) ;;
        *) return 1 ;;
    esac
    base="${name%.*}"
    [[ -f "$repo_root/.git_auto_review/$stem/$base.txt" \
        && -f "$repo_root/.git_auto_review/$stem/$base.preseed" ]]
}

clear_stem() {
    local repo_root=$1 stem=$2 stem_dir name
    stem_dir="$repo_root/.git_auto_review/$stem"
    [[ -d "$stem_dir" ]] || return 0
    for name in "$stem_dir"/* "$stem_dir"/.[!.]*; do
        [[ -e "$name" || -L "$name" ]] || continue
        if is_marked_pair "$repo_root" "$stem" "${name##*/}"; then
            continue
        fi
        rm -rf -- "$name"
    done
}

main() {
    while (($# > 0)); do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --task) TASK="${2:?--task needs a path}"; shift 2 ;;
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

    # The task file anchors the run's scope, so a path that does not resolve is
    # an environment failure rather than a stem to derive. A relative path
    # resolves against the relay root, the same root every relay path uses.
    if [[ -n "$TASK" ]]; then
        local task_path="$TASK"
        [[ "$task_path" = /* ]] || task_path="$repo_root/$TASK"
        if [[ ! -f "$task_path" || ! -r "$task_path" ]]; then
            die_env "task path is not a readable regular file: $TASK"
        fi
    fi

    local stem
    if [[ -n "$TASK" ]]; then
        stem="${TASK##*/}"
        stem="${stem%.*}"
        [[ -n "$stem" ]] || stem="default"
    else
        stem="default"
    fi

    mkdir -p "$repo_root/.git_auto_review" \
        || die_env "cannot create $repo_root/.git_auto_review"
    printf '*\n' > "$repo_root/.git_auto_review/.gitignore" \
        || die_env "cannot write the relay .gitignore"

    clear_stem "$repo_root" "$stem"

    local stem_dir="$repo_root/.git_auto_review/$stem"
    mkdir -p "$stem_dir" || die_env "cannot create $stem_dir"
    : > "$stem_dir/ledger.txt" || die_env "cannot write $stem_dir/ledger.txt"

    printf 'Relay initialised at %s\n' "$stem_dir"
    printf '%s\n' "$stem_dir"
}

main "$@"
