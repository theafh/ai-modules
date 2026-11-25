#!/usr/bin/env bash
# Bundled-script unit tests for the ai_instruction_formatting pseudo-XML linter.
#
# Scope: plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py.
# The fixtures under script_tests/fixtures/ drive the linter over each of the
# four document shapes it recognises (prose-only, XML-instruction body,
# tutorial with ```xml fences, mixed-agent), plus one file that trips an error
# and one that trips only a warning. Every scenario asserts the linter's exit
# status, its blocking-issue count, its error count, and the shape it detected,
# so a change to the parser is regression-checked instead of taken on trust.
# The skill's agent-level prose behaviour is out of scope here.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LINTER="$REPO_ROOT/plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py"
FIXTURES="$SCRIPT_DIR/fixtures"
RESULTS="$SCRIPT_DIR/../results/script_tests.log"

mkdir -p "$(dirname "$RESULTS")"
: > "$RESULTS"

PASS=0
FAIL=0
FAILED_IDS=()

pass() {
    PASS=$((PASS + 1))
    printf 'PASS %s\n' "$1" | tee -a "$RESULTS"
}

fail() {
    FAIL=$((FAIL + 1))
    FAILED_IDS+=("$1")
    printf 'FAIL %s\n' "$1" | tee -a "$RESULTS"
    [ -n "${2:-}" ] && printf '     %s\n' "$2" | tee -a "$RESULTS"
    return 0
}

# Fixed-string containment without a pipe. `printf ... | grep -q` closes the
# pipe early, and with `set -o pipefail` that SIGPIPE turns a match into a
# failure on large output.
has() {
    case "$1" in
        *"$2"*) return 0 ;;
        *) return 1 ;;
    esac
}

# tally_field <output> <label> -> the number after "<label>:" on the linter's
# closing tally line, or an empty string when the run printed none.
tally_field() {
    printf '%s\n' "$1" \
        | sed -nE "s/.*${2}: ([0-9]+).*/\1/p" \
        | tail -n 1
}

# expect <id> <fixture> <exit> <blocking-issues> <errors> <shape substring>
expect() {
    local id="$1"
    local fixture="$2"
    local want_rc="$3"
    local want_issues="$4"
    local want_errors="$5"
    local shape="$6"
    local out rc issues errors

    out="$(cd "$REPO_ROOT" && python3 "$LINTER" "$FIXTURES/$fixture" 2>&1)" && rc=0 || rc=$?
    issues="$(tally_field "$out" Issues)"
    errors="$(tally_field "$out" errors)"

    if [ "$rc" -eq "$want_rc" ]; then
        pass "$id-exit"
    else
        fail "$id-exit" "expected exit $want_rc, got $rc"
    fi

    if [ "$issues" = "$want_issues" ]; then
        pass "$id-issues"
    else
        fail "$id-issues" "expected $want_issues blocking issues, got '${issues:-none}'"
    fi

    if [ "$errors" = "$want_errors" ]; then
        pass "$id-errors"
    else
        fail "$id-errors" "expected $want_errors errors, got '${errors:-none}'"
    fi

    if has "$out" "$shape"; then
        pass "$id-shape"
    else
        fail "$id-shape" "output does not name '$shape'"
    fi
}

# --- The four recognised document shapes -----------------------------------

expect prose-only prose_only.md 0 0 0 "Mode: prose-only"
expect xml-instruction xml_instruction.md 0 0 0 "Mode: XML-instruction body"
expect tutorial tutorial.md 0 0 0 "Mode: tutorial"
expect mixed-agent mixed_agent.md 0 0 0 "Mode: mixed-agent"

# A clean file reports its pass line beside the zero counts above.
clean_out="$(cd "$REPO_ROOT" && python3 "$LINTER" "$FIXTURES/prose_only.md" 2>&1)"
if has "$clean_out" "PASS — no errors or warnings."; then
    pass clean-file-pass-line
else
    fail clean-file-pass-line "clean fixture did not print the pass line"
fi

# --- Error and warning files ------------------------------------------------

# The mismatched close and the stray close it leaves behind are two errors,
# and any error makes the linter exit non-zero.
expect error-case error_case.md 1 2 2 "Mode: XML-instruction body"

# A warning-only file reports one blocking issue but no error, so it exits 0.
expect warning-case warning_case.md 0 1 0 "Mode: XML-instruction body"

# --- Tally -----------------------------------------------------------------

TOTAL=$((PASS + FAIL))
printf '\n%d of %d scenarios passed, %d failed\n' "$PASS" "$TOTAL" "$FAIL" | tee -a "$RESULTS"
if [ "$FAIL" -ne 0 ]; then
    printf 'failed scenarios: %s\n' "${FAILED_IDS[*]}" | tee -a "$RESULTS"
    exit 1
fi
exit 0
