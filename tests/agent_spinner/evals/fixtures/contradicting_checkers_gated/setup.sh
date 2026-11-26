#!/usr/bin/env bash
# contradicting_checkers_gated: two checker returns on one claim disagree, one
# clearing it and one raising it. The run must surface the conflict as a user
# gate naming both rows, leave the page unchanged, and settle nothing itself.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs" "$proj/src"

printf '# Cache\n\nThe cache evicts on write, not on read.\n' > "$proj/docs/cache.md"

cat > "$proj/src/cache.py" <<'PY'
# Cache storage.
#
# Eviction runs on both paths: a write evicts the replaced entry, and a read of
# an expired key evicts that key too.

def write(key, value):
    evict(key)
    store(key, value)


def read(key):
    if expired(key):
        evict(key)
    return load(key)
PY

commit_tree "$proj"
run_ledger "$proj" init --phase check --bound 240 \
  --unit check:alpha --unit check:beta \
  --unit-path check:alpha=docs/cache.md \
  --unit-path check:beta=docs/cache.md >/dev/null

stage_row "$proj" check:alpha "Check docs/cache.md against its claim." \
  --checker --target docs/cache.md
write_return "$proj" check:alpha "done" pass '{
  "_prose": "check:alpha — PASS. The page states the eviction policy correctly.",
  "examined": [{"path": "docs/cache.md", "how": "full", "receipt": "The cache evicts on write, not on read."}],
  "checklist": [{"verdict": "pass", "span": "The cache evicts on write, not on read."}]
}'
run_ledger "$proj" accept check:alpha >/dev/null

stage_row "$proj" check:beta "Check docs/cache.md against its claim." \
  --checker --target docs/cache.md
write_return "$proj" check:beta "done" fail '{
  "_prose": "check:beta — FAIL. The page states the eviction policy backwards.",
  "examined": [{"path": "docs/cache.md", "how": "full", "receipt": "The cache evicts on write, not on read."}],
  "findings": [
    {"claim": "docs/cache.md says the cache evicts only on write, but src/cache.py also evicts on the read path.",
     "severity": "major",
     "quote": "The cache evicts on write, not on read.",
     "anchor": "docs/cache.md, under \"# Cache\""}
  ]
}'
run_ledger "$proj" accept check:beta >/dev/null

seal_open_run "$target" "$proj"
echo "contradicting_checkers_gated sandbox staged at $proj"
