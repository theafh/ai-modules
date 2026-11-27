#!/usr/bin/env bash
# grade.sh - deterministic grader for the update_features behavioural evals.
#
# Usage:
#   grade.sh <eval-id> <path-to-produced-FEATURES.md> [<pre-run-FEATURES.md>]
#
# Grades the ledger an agent produced against the eval's expectations. The
# "run reports ..." expectations are graded from the run's prose, not from the
# ledger, so they stay out of this file check.
#
# Exit 0 when every graded expectation passes; exit 1 naming each failure.

set -uo pipefail

EVAL_ID="${1:-}"
FEATURES="${2:-}"
PREV="${3:-}"

usage() { echo "usage: grade.sh <eval-id> <FEATURES.md> [<pre-run FEATURES.md>]" >&2; exit 2; }
[[ -n "$EVAL_ID" && -n "$FEATURES" ]] || usage
[[ -f "$FEATURES" ]] || { echo "FAIL  produced ledger missing: $FEATURES" >&2; exit 1; }

pass=0
fail=0
ok()  { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL  %s\n' "$1"; }

# Print the body of a `## <heading>` section, heading excluded, up to the next
# `## ` heading. One helper for both the boundary checks and the section
# comparison, so the two cannot disagree about where a section ends.
section_body() {
    python3 - "$1" "$2" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
heading = re.escape(sys.argv[2])
match = re.search(rf"(?ms)^## {heading}\n(.*?)(?=^## |\Z)", text)
sys.stdout.write(match.group(1) if match else "")
PY
}

has_section() {
    python3 - "$1" "$2" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
sys.exit(0 if re.search(rf"(?m)^## {re.escape(sys.argv[2])}$", text) else 1)
PY
}

grade_eval_1() {
    if grep -q '^# FEATURES' "$FEATURES"; then
        ok "opens with an H1"
    else
        bad "opens with an H1"
    fi
    if grep -q '^## ' "$FEATURES"; then
        ok "carries capability sections"
    else
        bad "carries capability sections"
    fi

    if grep -qiE 'hello, ?<name>|greet' "$FEATURES" && grep -qi 'world' "$FEATURES"; then
        ok "states the greeting behaviour and its default name"
    else
        bad "states the greeting behaviour and its default name"
    fi

    if has_section "$FEATURES" "Not yet implemented"; then
        ok "carries a '## Not yet implemented' section"
    else
        bad "carries a '## Not yet implemented' section"
    fi

    local boundary capability
    boundary=$(section_body "$FEATURES" "Not yet implemented")
    capability=$(python3 - "$FEATURES" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
cut = re.search(r"(?m)^## Not yet implemented$", text)
sys.stdout.write(text[:cut.start()] if cut else text)
PY
)
    if [[ "$boundary" == *--shout* && "$capability" != *--shout* ]]; then
        ok "--shout appears only under the boundary"
    else
        bad "--shout appears only under the boundary"
    fi

    if grep -qE '^[-*] `(src/|package\.json|test/)' "$FEATURES"; then
        bad "no bullet subject is a file path or module name"
    else
        ok "no bullet subject is a file path or module name"
    fi

    if grep -qE '(task-[a-z0-9-]+|sprint|status: (open|ready|done)|20[0-9]{2}-[0-9]{2}-[0-9]{2})' "$FEATURES"; then
        bad "carries no task ids, sprint state, or dates"
    else
        ok "carries no task ids, sprint state, or dates"
    fi
}

grade_eval_2() {
    if [[ -z "$PREV" || ! -f "$PREV" ]]; then
        bad "pre-run ledger supplied"
        return
    fi

    local before after
    before=$(section_body "$PREV" "Greeting")
    after=$(section_body "$FEATURES" "Greeting")
    if [[ -n "$before" && "$before" == "$after" ]]; then
        ok "the greeting entry is unchanged"
    else
        bad "the greeting entry is unchanged"
    fi

    local boundary capability
    boundary=$(section_body "$FEATURES" "Not yet implemented")
    capability=$(python3 - "$FEATURES" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
cut = re.search(r"(?m)^## Not yet implemented$", text)
sys.stdout.write(text[:cut.start()] if cut else text)
PY
)

    if [[ "$capability" == *--shout* ]]; then
        ok "--shout appears as a current capability"
    else
        bad "--shout appears as a current capability"
    fi

    if [[ "$boundary" == *--shout* ]]; then
        bad "the boundary no longer lists --shout"
    else
        ok "the boundary no longer lists --shout"
    fi

    if grep -qiE 'not (yet )?(built|implemented)[^.]*--shout|--shout[^.]*not (yet )?(built|implemented)' "$FEATURES"; then
        bad "no stale unbuilt claim remains"
    else
        ok "no stale unbuilt claim remains"
    fi
}

case "$EVAL_ID" in
    1) grade_eval_1 ;;
    2) grade_eval_2 ;;
    *) echo "FAIL  unknown eval id: $EVAL_ID" >&2; exit 2 ;;
esac

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]] || exit 1
exit 0
