#!/usr/bin/env bash
# scan_features_sources.sh - enumerate one repository's behaviour surfaces.
#
# Writes one structured context file describing where the repository's
# user-observable behaviour is declared: project-name candidates, manifests,
# the top-level layout, executable entry points, declared package entry points,
# public API surfaces, the docs that already describe the system, the
# declared-target markers that feed the not-yet-built boundary, and the test
# layout. The ledger author reads that file, then reads the code it names.
#
# The scan is read-only and repository-agnostic: it needs no task system, no
# network, and no build. When the root lies inside a git work tree, a
# subdirectory root included, it enumerates that root's tracked files with
# `git ls-files`, so ignored run output and dependency trees stay out of the
# scan; elsewhere it falls back to `find`. Every section is sorted, so two
# runs over an unchanged tree produce byte-identical output.
#
# Usage:
#   scan_features_sources.sh [--root <dir>] [--out <file>]
#
# With no --out the file lands under the system tmp dir. The last stdout line
# is the context file's absolute path.

set -uo pipefail

ROOT=""
OUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="${2:-}"; shift 2 ;;
        --out) OUT="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "scan_features_sources.sh: unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$ROOT" ]]; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(pwd)
fi
[[ -d "$ROOT" ]] || { echo "scan_features_sources.sh: not a directory: $ROOT" >&2; exit 2; }
ROOT=$(cd "$ROOT" && pwd)

if [[ -z "$OUT" ]]; then
    OUT="${TMPDIR:-/tmp}/features-sources-$(basename "$ROOT")-$$.txt"
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/features-scan.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

# One sorted root-relative file list, the single enumeration every section reads.
TOPLEVEL=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)
if [[ -n "$TOPLEVEL" ]]; then
    ( cd "$ROOT" && git ls-files ) > "$TMP/files"
else
    ( cd "$ROOT" && find . -type f -print ) | sed 's#^\./##' | sort > "$TMP/files"
fi

section() { printf '\n## %s\n' "$1"; }

{
    printf '# Behaviour-surface scan\n'
    printf 'root: %s\n' "$ROOT"
    printf 'files: %s\n' "$(wc -l < "$TMP/files" | tr -d ' ')"

    section "Project-name candidates"
    basename "$ROOT"
    for f in package.json Cargo.toml pyproject.toml go.mod; do
        [[ -f "$ROOT/$f" ]] || continue
        case "$f" in
            package.json) python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("name",""))' "$ROOT/$f" 2>/dev/null ;;
            Cargo.toml|pyproject.toml) sed -n 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/$f" | head -1 ;;
            go.mod) sed -n 's/^module[[:space:]]\+//p' "$ROOT/go.mod" | head -1 ;;
        esac
    done | sed '/^$/d' | sort -u
    sed -n 's/^# \{1,2\}\([^#].*\)/\1/p' "$ROOT/README.md" 2>/dev/null | head -1

    section "Manifests and toolchain files"
    grep -xE '(package\.json|Cargo\.toml|pyproject\.toml|setup\.py|go\.mod|Makefile|justfile|Taskfile\.yml)' "$TMP/files" || true

    section "Top-level layout"
    sed 's#/.*##' "$TMP/files" | sort -u

    section "Executable entry points"
    grep -E '(^|/)(main\.[a-z]+|cli\.[a-z]+|__main__\.py|index\.(js|ts))$' "$TMP/files" \
        | grep -vE '/tests?/|/scratch/|/workspace/' | head -60 || true

    section "Declared package entry points"
    if [[ -f "$ROOT/package.json" ]]; then
        python3 - "$ROOT/package.json" <<'PY' 2>/dev/null || true
import json, sys
d = json.load(open(sys.argv[1]))
for key in ("bin", "main", "exports"):
    if key in d:
        print(f"{key}: {json.dumps(d[key], sort_keys=True)}")
PY
    fi

    section "Public API surfaces"
    grep -E '(^|/)(lib\.rs|mod\.rs|__init__\.py|index\.(js|ts))$' "$TMP/files" | head -60 || true

    section "Behaviour-describing docs"
    grep -xE '(README|ARCHITECTURE|FEATURES|CHANGELOG|TESTING|SECURITY)\.md' "$TMP/files" || true

    section "Declared-target markers (not-yet-built boundary)"
    grep -E '\.(md|py|ts|js|rs|go)$' "$TMP/files" > "$TMP/marker-sources" || true
    if [[ -s "$TMP/marker-sources" ]]; then
        marker_files=()
        while IFS= read -r f; do marker_files+=("$f"); done < <(head -2000 "$TMP/marker-sources")
        ( cd "$ROOT" && grep -nE '\b(TODO|FIXME|ROADMAP|not yet implemented|unimplemented!|todo!)\b' \
            "${marker_files[@]}" 2>/dev/null ) | head -80 || true
    fi

    section "Test layout"
    grep -E '(^|/)(test|tests|spec|__tests__)/' "$TMP/files" \
        | sed -E 's#((^|/)(test|tests|spec|__tests__)/).*#\1#' | sort -u | head -40 || true
} > "$OUT" || { echo "scan_features_sources.sh: cannot write $OUT" >&2; exit 1; }

printf '%s\n' "$OUT"
