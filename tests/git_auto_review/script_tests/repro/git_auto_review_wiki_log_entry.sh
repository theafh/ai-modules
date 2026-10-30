#!/usr/bin/env bash
# Reproduction for the round-1 finding on `wiki/log.md`: a wiki operation that
# updates a page appends one log entry naming the page and what changed.
#
# Before the fix the change edited
# `wiki/concepts/agent-delegated-automation.md` while the log's tail stayed at
# its 2026-10-29 entry, which `wiki/SCHEMA.md` forbids.
#
# Exit codes:
#   0  the log carries a 2026-10-30 entry naming the page
#   1  no such entry exists

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
LOG="$REPO_ROOT/wiki/log.md"

fail() {
    printf 'repro: %s\n' "$*" >&2
    exit 1
}

[[ -f "$LOG" ]] || fail "log not found at $LOG"

# The entry's heading must carry the date, and the entry's own body must name
# the page, so an entry for a different operation cannot satisfy the check.
entry="$(awk '
  /^## \[2026-10-30 / { inside = 1; next }
  inside && /^## / { exit }
  inside { print }
' "$LOG")"

[[ -n "$entry" ]] || fail "no 2026-10-30 entry in wiki/log.md"
printf '%s\n' "$entry" | grep -Fq 'concepts/agent-delegated-automation.md' \
    || fail "the 2026-10-30 entry does not name concepts/agent-delegated-automation.md"

printf 'repro: the wiki log carries an entry for the updated page\n'
