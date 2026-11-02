#!/usr/bin/env bash
# tests/run_all.sh — the aggregate deterministic gate for the whole test tree.
#
# A harness directory is an immediate child of tests/ that carries a
# deterministic entrypoint: run_all.sh, script_tests/run.sh, evals/test_run.py,
# or evals/test_grade.py. Discovery runs at run time, so a new harness joins
# the gate by existing; no registration list needs editing.
#
# For each harness the gate runs run_all.sh when present and
# script_tests/run.sh otherwise, then every evals/test_run.py or
# evals/test_grade.py the entrypoint does not already run, so each
# deterministic file runs once. tests/lib/ is one more surface: every
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

  --list           print the discovered set without running it
  --surface NAME   run one surface only (a harness name or lib); repeatable
  -h, --help       show this help

A harness directory is an immediate child of tests/ that carries run_all.sh,
script_tests/run.sh, evals/test_run.py, or evals/test_grade.py. tests/lib/ is
one more surface, running every tests/lib/test_* file. Behavioural evals stay
out of band.
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

entrypoint_invokes() {
    # True when the entrypoint runs the named file rather than merely
    # mentioning it. Comment text and here-doc bodies are dropped first, so a
    # usage message that spells out the command cannot silence the suite.
    # What remains is tokenized, and the file counts as invoked only as an
    # argument to an interpreter: a literal command word, an interpreter
    # reached through a variable, or a for loop over the file whose body runs
    # the loop variable. A reserved word or group operator that opens a
    # segment is stepped over, and any shell delimiter may follow the name.
    local entry="$1"
    local name="$2"
    [ -f "$entry" ] || return 1
    awk -v name="$name" '
BEGIN {
    SQ = sprintf("%c", 39)
    DQ = sprintf("%c", 34)
    esc = name
    gsub(/\./, "\\.", esc)
    delim = ""
    buffer = ""
    found = 0
    ARITH = 0
}

function trim(s) {
    sub(/^[ \t]+/, "", s)
    sub(/[ \t]+$/, "", s)
    return s
}

# Drop comment text and here-doc bodies, and record the first here-doc
# delimiter seen on the line in DELIM. Shell arithmetic spells a left shift
# with the same two characters as a here-doc opener, so the ARITH counter
# tracks `((...))` nesting and `<<` inside it stays a shift. A bare
# `((...))` arithmetic command opens the same nesting as `$((...))`, and the
# counter lives across lines because an arithmetic expression may continue
# onto the next one.
function scan(s,    i, c, out, in_s, in_d, prev, d, q, e, word) {
    out = ""
    in_s = 0
    in_d = 0
    prev = ""
    DELIM = ""
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (in_s) {
            out = out c
            if (c == SQ) in_s = 0
        } else if (in_d) {
            if (c == "\\") { i++; c = substr(s, i, 1); out = out "\\" c }
            else { out = out c; if (c == DQ) in_d = 0 }
        } else if (c == SQ) { in_s = 1; out = out c }
        else if (c == DQ) { in_d = 1; out = out c }
        else if (c == "\\") { i++; c = substr(s, i, 1); out = out "\\" c }
        else if (c == "#" && (i == 1 || prev ~ /[ \t;&|(]/)) break
        else if (c == "(" && substr(s, i + 1, 1) == "(") { ARITH++; out = out "(("; i++ }
        else if (ARITH > 0 && c == ")" && substr(s, i + 1, 1) == ")") { ARITH--; out = out "))"; i++ }
        else if (c == "<" && ARITH == 0 && substr(s, i + 1, 1) == "<" && substr(s, i + 2, 1) != "<") {
            d = i + 2
            if (substr(s, d, 1) == "-") d++
            while (d <= length(s) && substr(s, d, 1) ~ /[ \t]/) d++
            q = substr(s, d, 1)
            if (q == SQ || q == DQ) {
                e = index(substr(s, d + 1), q)
                if (e > 0) { DELIM = substr(s, d + 1, e - 1); i = d + e }
            } else {
                word = substr(s, d)
                if (match(word, /^[A-Za-z0-9_.\/-]+/)) {
                    DELIM = substr(word, 1, RLENGTH)
                    i = d + RLENGTH - 1
                }
            }
            out = out c
        }
        else out = out c
        prev = c
    }
    return out
}

function tokenize(s, toks,    i, c, cur, n, in_s, in_d) {
    n = 0
    cur = ""
    in_s = 0
    in_d = 0
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (in_s) { cur = cur c; if (c == SQ) in_s = 0; continue }
        if (in_d) {
            if (c == "\\") { cur = cur c substr(s, i + 1, 1); i++ }
            else { cur = cur c; if (c == DQ) in_d = 0 }
            continue
        }
        if (c == SQ) { in_s = 1; cur = cur c; continue }
        if (c == DQ) { in_d = 1; cur = cur c; continue }
        if (c == "\\") { cur = cur c substr(s, i + 1, 1); i++; continue }
        if (c ~ /[ \t]/) { if (cur != "") { toks[++n] = cur; cur = "" }; continue }
        if (c ~ /[;&|()]/) {
            if (cur != "") { toks[++n] = cur; cur = "" }
            toks[++n] = c
            continue
        }
        cur = cur c
    }
    if (cur != "") toks[++n] = cur
    return n
}

function names_file(tok,    pat) {
    pat = "(^|[^A-Za-z0-9_.])" esc "([^A-Za-z0-9_]|$)"
    return tok ~ pat
}

function is_interpreter(tok,    t) {
    t = tok
    gsub(SQ, "", t)
    gsub(DQ, "", t)
    if (t ~ /^\$[{]?[A-Za-z_][A-Za-z0-9_]*[}]?$/) return 1
    sub(/^.*\//, "", t)
    return t ~ /^(python[0-9.]*|bash|sh|zsh|uv|poetry|pdm|rye|pipenv|pyenv|node|perl|ruby)$/
}

function first_command(toks, from, to,    i) {
    i = from
    while (i <= to) {
        if (toks[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
        if (toks[i] ~ /^(env|exec|command|sudo|nohup|time|nice|stdbuf)$/) { i++; continue }
        if (toks[i] == "uv" && i + 1 <= to && toks[i + 1] == "run") { i += 2; continue }
        if (toks[i] ~ /^(then|do|else|elif|if|while|until|for)$/) { i++; continue }
        if (toks[i] == "{" || toks[i] == "!") { i++; continue }
        break
    }
    return i
}

function loop_invokes(toks, n,    i, j, k, v, listed, cmd, t) {
    for (i = 1; i <= n; i++) {
        if (toks[i] != "for") continue
        if (i + 2 > n || toks[i + 2] != "in") continue
        v = toks[i + 1]
        listed = 0
        j = i + 3
        while (j <= n && toks[j] != ";" && toks[j] != "do") {
            if (names_file(toks[j])) listed = 1
            j++
        }
        if (!listed) continue
        while (j <= n && toks[j] != "do") j++
        if (j >= n) continue
        cmd = first_command(toks, j + 1, n)
        if (cmd > n || !is_interpreter(toks[cmd])) continue
        for (k = cmd + 1; k <= n && toks[k] != "done"; k++) {
            t = toks[k]
            gsub(SQ, "", t)
            gsub(DQ, "", t)
            if (t ~ ("^\\$[{]?" v "[}]?$")) return 1
        }
    }
    return 0
}

function segment_invokes(toks, from, to,    i) {
    i = first_command(toks, from, to)
    if (i > to) return 0
    if (!is_interpreter(toks[i])) return 0
    for (i = i + 1; i <= to; i++) {
        if (names_file(toks[i])) return 1
    }
    return 0
}

{
    if (delim != "") {
        if (trim($0) == delim) delim = ""
        next
    }
    line = scan($0)
    if (DELIM != "") delim = DELIM
    if (buffer != "") {
        buffer = buffer " " line
        if (line ~ /(^|[;&|({ \t])done([ \t;&|)}]|$)/) {
            n = tokenize(buffer, toks)
            if (loop_invokes(toks, n)) { found = 1; exit }
            buffer = ""
        }
        next
    }
    if (line ~ /(^|[;&|({ \t])for[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+in([ \t]|$)/ \
        && line !~ /(^|[;&|({ \t])done([ \t;&|)}]|$)/) {
        buffer = line
        next
    }
    n = tokenize(line, toks)
    if (n == 0) next
    if (loop_invokes(toks, n)) { found = 1; exit }
    start = 1
    for (i = 1; i <= n + 1; i++) {
        if (i == n + 1 || toks[i] ~ /^[;&|()]$/) {
            if (segment_invokes(toks, start, i - 1)) { found = 1; exit }
            start = i + 1
        }
    }
}

END { exit (found ? 0 : 1) }
' "$entry" 2>/dev/null
}

harness_files() {
    local dir="$1"
    local entry=""
    if [ -f "$dir/run_all.sh" ]; then
        entry="$dir/run_all.sh"
    elif [ -f "$dir/script_tests/run.sh" ]; then
        entry="$dir/script_tests/run.sh"
    fi
    if [ -n "$entry" ]; then
        printf '%s\n' "$entry"
    fi
    local extra
    for extra in "$dir/evals/test_run.py" "$dir/evals/test_grade.py"; do
        [ -f "$extra" ] || continue
        if [ -n "$entry" ] && entrypoint_invokes "$entry" "$(basename "$extra")"; then
            continue
        fi
        printf '%s\n' "$extra"
    done
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
            files="$(harness_files "$TESTS_DIR/$name")"
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
