#!/usr/bin/env bash
# extract_heading_range.sh - print the inclusive slice of a markdown file that
# runs from one heading to another, for /git_review's publishing step.
#
# A posted slice and the chat report must carry identical headings, so the slice
# is cut from the drafted report file rather than re-composed. The range is
# inclusive of both named headings: it starts at the line of the first heading
# and ends at the line before the next heading at that heading's level or above,
# counting from the second named heading.

set -uo pipefail

EXIT_USAGE=1
EXIT_NOT_FOUND=3

usage() {
    cat <<'USAGE'
extract_heading_range.sh - print an inclusive heading range from a markdown file.

Usage:
  extract_heading_range.sh <file> <from-heading> [<to-heading>]
  extract_heading_range.sh --list <file>
  extract_heading_range.sh --help

Arguments:
  <from-heading>  Heading text to start at, without its leading # marks.
  <to-heading>    Heading text to end at, without its leading # marks. The
                  section under it is included. Omit it to run from
                  <from-heading> to the end of the file.

Matching:
  Heading text is matched exactly after the leading # marks and surrounding
  whitespace are stripped, so "What is critical" matches "## What is critical"
  and nothing else.

Exit codes:
  0  the slice was printed
  1  usage error, or the file is unreadable
  3  a named heading is absent from the file, or the range runs backwards
USAGE
}

die() {
    printf 'git_review: %s\n' "$*" >&2
    exit "$EXIT_USAGE"
}

not_found() {
    printf 'git_review: %s\n' "$*" >&2
    exit "$EXIT_NOT_FOUND"
}

list_headings() {
    local file="$1"
    grep -nE '^#{1,6}[[:space:]]+' "$file" | sed -E 's/^([0-9]+):#{1,6}[[:space:]]+/\1\t/'
}

main() {
    local file from to=""

    case "${1:-}" in
        -h|--help) usage; exit 0 ;;
        --list)
            file="${2:?--list needs a file}"
            [[ -r "$file" ]] || die "cannot read file: $file"
            list_headings "$file"
            exit 0
            ;;
        "") usage >&2; die "a file and a starting heading are required" ;;
        -*) die "unknown argument: $1" ;;
    esac

    file="$1"
    from="${2:-}"
    to="${3:-}"

    [[ -r "$file" ]] || die "cannot read file: $file"
    [[ -n "$from" ]] || die "a starting heading is required"

    awk -v from="$from" -v to="$to" '
        function text(line,   t) {
            t = line
            sub(/^#+[ \t]+/, "", t)
            sub(/[ \t]+$/, "", t)
            return t
        }
        function level(line,   n) {
            n = match(line, /^#+/)
            return n ? RLENGTH : 0
        }
        {
            lines[NR] = $0
            if ($0 ~ /^#{1,6}[ \t]+/) {
                hn++
                h_line[hn] = NR
                h_text[hn] = text($0)
                h_level[hn] = level($0)
            }
        }
        END {
            start = 0
            stop = 0
            for (i = 1; i <= hn; i++) {
                if (start == 0 && h_text[i] == from) {
                    start = i
                    if (to == from) { stop = i }
                } else if (start > 0 && to != "" && stop == 0 && h_text[i] == to) {
                    stop = i
                }
            }
            if (start == 0) { exit 3 }
            if (to != "" && stop == 0) { exit 3 }

            first = h_line[start]
            last = NR
            if (to != "") {
                for (j = stop + 1; j <= hn; j++) {
                    if (h_level[j] <= h_level[stop]) {
                        last = h_line[j] - 1
                        break
                    }
                }
            }
            while (last > first && lines[last] ~ /^[ \t]*$/) { last-- }
            for (k = first; k <= last; k++) print lines[k]
        }
    ' "$file"

    local rc=$?
    if ((rc == 3)); then
        if [[ -n "$to" ]]; then
            not_found "heading range not resolvable in $file: '$from' .. '$to'"
        fi
        not_found "heading not found in $file: '$from'"
    fi
    return "$rc"
}

main "$@"
