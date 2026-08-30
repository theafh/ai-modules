#!/usr/bin/env bash
# lossless_split fixture: a multi-section source document with a shared,
# source-wide preamble that governs every section, living OUTSIDE tasks/.
# Deriving tasks from it must (a) cover every section, (b) carry the
# shared preamble into each derived task, and (c) leave the source file
# in place for the user to dispose of. The prompt does NOT ask the agent
# to preserve anything — the lossless-conversion contract must fire on
# its own.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"

mkdir -p "$proj/notes"
cat > "$proj/notes/db-migration-plan.md" <<'EOF'
# Database migration plan

> Preamble — applies to every step below: all work lands on the staging
> cluster first and ships to production only behind a green canary. No
> step is exempt from the green-canary gate.

## Connection pooling

Introduce pgbouncer in front of the primary so short-lived web requests
stop exhausting Postgres connection slots.

## Read replicas

Add two read replicas and route reporting queries to them; alert when
replica lag exceeds five seconds.

## Backup cadence

Move from nightly dumps to continuous WAL archiving so point-in-time
recovery becomes possible.
EOF

# Snapshot the source so grade.sh can prove the skill left it untouched:
# disposition is the user's call — the skill never deletes, moves,
# overwrites, or truncates the source on its own initiative.
sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
sha_of "$proj/notes/db-migration-plan.md" > "$target/.source_sha256"

echo "lossless_split sandbox staged at $proj"
