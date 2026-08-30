#!/usr/bin/env bash
# lossless_single fixture: a source note that is ONE unit of work but
# carries several relevant details that must all survive into the single
# derived task. Producing one task does not exempt the lossless check —
# the lone task must capture everything relevant. The prompt does NOT ask
# the agent to preserve anything; the contract must fire on its own.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"

mkdir -p "$proj/notes"
cat > "$proj/notes/session-cache-bug.md" <<'EOF'
# Bug: stale sessions after logout

Logging out does not always clear the session. The details that matter:

- Repro: it only happens under a race condition when two tabs log out
  within the same second.
- The culprit is the SessionCache layer, which keeps a copy keyed by
  user id even after the store entry is deleted.
- Constraint: the fix must stay backward-compatible with the existing
  on-disk session format — we cannot force every user to re-login.
EOF

# Snapshot the source so grade.sh can prove the skill left it untouched.
sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
sha_of "$proj/notes/session-cache-bug.md" > "$target/.source_sha256"

echo "lossless_single sandbox staged at $proj"
