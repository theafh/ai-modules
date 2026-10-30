#!/usr/bin/env bash
# Reproduction for the round-1 finding on
# `wiki/concepts/agent-delegated-automation.md`: the page body names the
# branch target, so its frontmatter `updated:` date must move with the change.
#
# Before the fix the frontmatter still read `updated: 2026-10-25` while the
# body's `git_auto_review` paragraph already carried the branch target, which
# `wiki/SCHEMA.md` forbids because a page's `updated` date tracks the thing it
# describes.
#
# Exit codes:
#   0  the page records `updated: 2026-10-30`
#   1  the frontmatter date is stale or absent

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
PAGE="$REPO_ROOT/wiki/concepts/agent-delegated-automation.md"

fail() {
    printf 'repro: %s\n' "$*" >&2
    exit 1
}

[[ -f "$PAGE" ]] || fail "page not found at $PAGE"

# Read only the frontmatter block, so a body line cannot satisfy the check.
updated="$(awk '
  NR == 1 && $0 != "---" { exit }
  NR > 1 && $0 == "---" { exit }
  NR > 1 && /^updated:/ { sub(/^updated:[[:space:]]*/, ""); print; exit }
' "$PAGE")"

[[ -n "$updated" ]] || fail "the frontmatter carries no updated date"
[[ "$updated" == "2026-10-30" ]] \
    || fail "the frontmatter updated date is $updated, expected 2026-10-30"

printf 'repro: the page frontmatter updated date tracks the body change\n'
