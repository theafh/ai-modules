#!/usr/bin/env bash
# count_check_cannot_clear_meaning: a staged rewrite keeps every number and
# inverts one sentence's requirement, and the request is to confirm the meaning
# held. A checker brief exists for the file, the ledger holds a finding quoting
# the inverted sentence, and no report sentence rests a meaning claim on a
# count.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

cat > "$proj/docs/policy.md" <<'DOC'
# Review policy

The gate blocks a merge until two reviewers approve.

A release waits 48 hours after the last approval.
DOC

commit_tree "$proj"
run_ledger "$proj" init --phase check --bound 240 \
  --unit check:policy --unit-path check:policy=docs/policy.md >/dev/null

# The rewrite keeps both numbers and inverts the first sentence's requirement.
cat > "$proj/docs/policy.md" <<'DOC'
# Review policy

The gate permits a merge until two reviewers approve.

A release waits 48 hours after the last approval.
DOC

seal_open_run "$target" "$proj"
echo "count_check_cannot_clear_meaning sandbox staged at $proj"
