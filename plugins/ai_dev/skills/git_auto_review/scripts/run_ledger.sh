#!/usr/bin/env bash
# run_ledger.sh - run one git_auto_review regression ledger.
#
# Each ledger line is the reproduction's path, a tab, then the command that
# runs it. The script runs each line's command field in order and reports the
# line's 1-based number with its pass or fail. An empty ledger, one carrying
# zero reproduction lines, exits 0.
#
# Usage:
#   run_ledger.sh [--ledger <path>] [--cwd <dir>]
#
# Exit codes:
#   0  every line passed, or the ledger carried no line
#   1  usage error, or at least one line failed (the message names the 1-based
#      number of the first failing entry)

set -uo pipefail

EXIT_USAGE=1

LEDGER="ledger.txt"
CWD=""

usage() {
    cat <<'USAGE'
run_ledger.sh - run one git_auto_review regression ledger.

Usage:
  run_ledger.sh [--ledger <path>] [--cwd <dir>]
  run_ledger.sh --help

Behavior:
  - Reads each line's leading tab-separated path field and runs the command
    field after it, in order.
  - Reports each line's 1-based number with its pass or fail.
  - Runs each command from --cwd, or from the current directory when --cwd
    is absent.
  - Exits 0 on an all-passing ledger and on an empty ledger, zero
    reproduction lines included, and otherwise exits 1 naming the 1-based
    number of the first failing entry.

Exit codes:
  0  all lines passed, or the ledger was empty
  1  usage error, or a line failed
USAGE
}

die() {
    printf 'git_auto_review: %s\n' "$*" >&2
    exit "$EXIT_USAGE"
}

main() {
    while (($# > 0)); do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --ledger) LEDGER="${2:?--ledger needs a path}"; shift 2 ;;
            --cwd) CWD="${2:?--cwd needs a directory}"; shift 2 ;;
            *) die "unknown argument: $1" ;;
        esac
    done

    [[ -f "$LEDGER" ]] || die "ledger not found: $LEDGER"
    if [[ -n "$CWD" ]]; then
        [[ -d "$CWD" ]] || die "cwd is not a directory: $CWD"
    else
        CWD="$PWD"
    fi
    CWD="$(cd "$CWD" && pwd)"

    local number=0 path command first_fail=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        number=$((number + 1))
        # A blank line carries no reproduction entry.
        if [[ -z "$line" ]]; then
            continue
        fi
        # The path field is everything up to the first tab; the command field
        # is everything after it.
        if [[ "$line" != *$'\t'* ]]; then
            printf 'line %s: FAIL\t%s\n' "$number" "$line"
            if [[ -z "$first_fail" ]]; then first_fail="$number"; fi
            continue
        fi
        path="${line%%$'\t'*}"
        command="${line#*$'\t'}"
        if (cd "$CWD" && bash -c "$command") >/dev/null 2>&1; then
            printf 'line %s: PASS\t%s\n' "$number" "$path"
        else
            printf 'line %s: FAIL\t%s\n' "$number" "$path"
            if [[ -z "$first_fail" ]]; then first_fail="$number"; fi
        fi
    done < "$LEDGER"

    if [[ -n "$first_fail" ]]; then
        printf 'git_auto_review: ledger line %s failed\n' "$first_fail" >&2
        exit 1
    fi
    printf 'git_auto_review: ledger clean (%s line(s))\n' "$number"
    exit 0
}

main "$@"
