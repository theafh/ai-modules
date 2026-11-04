#!/usr/bin/env bash
# tests/run_all.sh — the aggregate deterministic gate for the whole test tree.
#
# A harness directory is an immediate child of tests/ that carries a
# deterministic entrypoint: run_all.sh, script_tests/run.sh, evals/test_run.py,
# or evals/test_grade.py. Discovery runs at run time, so a new harness joins
# the gate by existing; no registration list needs editing.
#
# For each harness the gate runs its entrypoint (run_all.sh when present and
# script_tests/run.sh otherwise) plus every evals/test_run.py or
# evals/test_grade.py that harness's evals/covered-by-entrypoint declaration
# omits. The declaration names, one file per line, the eval files the
# entrypoint runs; a harness that carries an eval file without a declaration
# fails the gate by name. tests/lib/ is one more surface: every
# tests/lib/test_* file runs there, .py through python3 and .sh through bash.
#
# Prints one pass/fail line per surface and a final tally, and exits non-zero
# when any surface fails. Behavioural evals stay out of band.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
LIB_DIR="$TESTS_DIR/lib"
cd "$REPO_ROOT" || exit 1

usage() {
    cat <<'USAGE'
Usage: bash tests/run_all.sh [--list] [--surface NAME]

Runs every deterministic test surface under tests/ and prints one pass/fail
line per surface plus a final tally. Exits non-zero when any surface fails.

  --list           print the discovered coverage tree without running it
  --surface NAME   run one surface only (a harness name or lib); repeatable
  -h, --help       show this help

A harness directory is an immediate child of tests/ that carries run_all.sh,
script_tests/run.sh, evals/test_run.py, or evals/test_grade.py. tests/lib/ is
one more surface, running every tests/lib/test_* file. A harness that carries
an eval file names the eval files its entrypoint runs in
evals/covered-by-entrypoint. Behavioural evals stay out of band.
USAGE
}

usage_error() {
    printf 'run_all.sh: %s\n' "$1" >&2
    printf 'usage: bash tests/run_all.sh [--list] [--surface NAME]\n' >&2
    exit 2
}

relpath() {
    case "$1" in
        "$REPO_ROOT"/*) printf '%s\n' "${1#"$REPO_ROOT"/}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

has_deterministic_surface() {
    local dir="$1"
    [ -f "$dir/run_all.sh" ] && return 0
    [ -f "$dir/script_tests/run.sh" ] && return 0
    [ -f "$dir/evals/test_run.py" ] && return 0
    [ -f "$dir/evals/test_grade.py" ] && return 0
    return 1
}

harness_names() {
    find "$TESTS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name lib -print \
        | LC_ALL=C sort \
        | while IFS= read -r dir; do
            if has_deterministic_surface "$dir"; then
                basename "$dir"
            fi
        done
}

lib_files() {
    find "$LIB_DIR" -mindepth 1 -maxdepth 1 -type f -name 'test_*' -print \
        | LC_ALL=C sort
}

declaration_path() {
    printf '%s\n' "$1/evals/covered-by-entrypoint"
}

harness_entrypoint() {
    local dir="$1"
    if [ -f "$dir/run_all.sh" ]; then
        printf '%s\n' "$dir/run_all.sh"
    elif [ -f "$dir/script_tests/run.sh" ]; then
        printf '%s\n' "$dir/script_tests/run.sh"
    fi
}

harness_eval_files() {
    local dir="$1"
    local extra
    for extra in "$dir/evals/test_run.py" "$dir/evals/test_grade.py"; do
        if [ -f "$extra" ]; then
            printf '%s\n' "$extra"
        fi
    done
}

harness_files() {
    local dir="$1"
    local entry
    local decl
    local extra
    entry="$(harness_entrypoint "$dir")"
    if [ -n "$entry" ]; then
        printf '%s\n' "$entry"
    fi
    decl="$(declaration_path "$dir")"
    while IFS= read -r extra; do
        [ -n "$extra" ] || continue
        if [ -f "$decl" ] && grep -qxF "$(basename "$extra")" "$decl"; then
            continue
        fi
        printf '%s\n' "$extra"
    done <<EOF
$(harness_eval_files "$dir")
EOF
}

surface_listing_files() {
    local dir="$1"
    local entry
    entry="$(harness_entrypoint "$dir")"
    if [ -n "$entry" ]; then
        printf '%s\n' "$entry"
    fi
    harness_eval_files "$dir"
}

check_coverage_declarations() {
    local names="$1"
    local name
    local dir
    local decl
    local missing=0
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        dir="$TESTS_DIR/$name"
        if [ ! -f "$dir/evals/test_run.py" ] && [ ! -f "$dir/evals/test_grade.py" ]; then
            continue
        fi
        decl="$(declaration_path "$dir")"
        if [ ! -f "$decl" ]; then
            printf 'run_all.sh: %s carries an eval file but has no coverage declaration; create %s\n' \
                "$name" "$(relpath "$decl")" >&2
            missing=1
        fi
    done <<EOF
$names
EOF
    return "$missing"
}

all_surfaces() {
    printf 'lib\n'
    harness_names
}

is_selected() {
    local want="$1"
    local name
    [ -z "$SELECTED" ] && return 0
    while IFS= read -r name; do
        [ "$name" = "$want" ] && return 0
    done <<EOF
$SELECTED
EOF
    return 1
}

run_file() {
    case "$1" in
        *.py) python3 "$1" ;;
        *) bash "$1" ;;
    esac
}

run_surface() {
    local name="$1"
    local rc=0
    local file
    local files
    if [ "$name" = "lib" ]; then
        files="$(lib_files)"
    else
        files="$(harness_files "$TESTS_DIR/$name")"
    fi
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        run_file "$file" || rc=1
    done <<EOF
$files
EOF
    return "$rc"
}

print_listing() {
    local name
    local file
    local files
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        printf '%s\n' "$name"
        if [ "$name" = "lib" ]; then
            files="$(lib_files)"
        else
            files="$(surface_listing_files "$TESTS_DIR/$name")"
        fi
        while IFS= read -r file; do
            [ -n "$file" ] || continue
            printf '    %s\n' "$(relpath "$file")"
        done <<EOF
$files
EOF
    done <<EOF
$SURFACES
EOF
}

LIST=false
SELECTED=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --list)
            LIST=true
            ;;
        --surface)
            [ "$#" -ge 2 ] || usage_error "--surface needs a name"
            SELECTED="$SELECTED$2
"
            shift
            ;;
        --surface=*)
            SELECTED="$SELECTED${1#--surface=}
"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage_error "unknown argument: $1"
            ;;
    esac
    shift
done

ALL_SURFACES="$(all_surfaces)"

if ! check_coverage_declarations "$ALL_SURFACES"; then
    exit 1
fi

if [ -n "$SELECTED" ]; then
    name=""
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        printf '%s\n' "$ALL_SURFACES" | grep -qxF -- "$name" \
            || usage_error "unknown surface: $name"
    done <<EOF
$SELECTED
EOF
fi

SURFACES=""
while IFS= read -r name; do
    [ -n "$name" ] || continue
    if is_selected "$name"; then
        SURFACES="$SURFACES$name
"
    fi
done <<EOF
$ALL_SURFACES
EOF

if $LIST; then
    print_listing
    exit 0
fi

PASSED=0
FAILED=0
FAILED_NAMES=""

while IFS= read -r name; do
    [ -n "$name" ] || continue
    if run_surface "$name"; then
        printf 'PASS %s\n' "$name"
        PASSED=$((PASSED + 1))
    else
        printf 'FAIL %s\n' "$name"
        FAILED=$((FAILED + 1))
        FAILED_NAMES="$FAILED_NAMES$name "
    fi
done <<EOF
$SURFACES
EOF

TOTAL=$((PASSED + FAILED))
printf '\n%d of %d surfaces passed, %d failed\n' "$PASSED" "$TOTAL" "$FAILED"

if [ "$FAILED" -ne 0 ]; then
    printf 'failed surfaces: %s\n' "${FAILED_NAMES% }"
    exit 1
fi
exit 0
