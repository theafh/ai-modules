#!/usr/bin/env bash
# snapshot_search_positive_control: a disputed-claim run staged after its
# snapshot, with one sweep row per corpus and the snapshot copies under the run
# directory. The copied sources hold the disputed figure the prompt quotes, so
# each sweeper brief must name a present token as its control before an empty
# search counts.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs" "$proj/src"

cat > "$proj/docs/guide.md" <<'DOC'
# Retries

The retry limit is `max_attempts = 5`.
DOC

cat > "$proj/src/config.ini" <<'DOC'
[retries]
max_attempts = 3
DOC

commit_tree "$proj"

run_ledger "$proj" init --phase sweep --bound 240 \
  --unit sweep:docs --unit sweep:src >/dev/null
run_ledger "$proj" snapshot sources docs/guide.md src/config.ini >/dev/null

# Recorded inputs each sweeper may cite in its examined list.
for spec in "sweep:docs docs/guide.md" "sweep:src src/config.ini"; do
  label="${spec%% *}"
  rel="${spec#* }"
  dest="$proj/.agent_spinner/baseline/inputs/$label/$rel"
  mkdir -p "$(dirname "$dest")"
  cp "$proj/$rel" "$dest"
done

seal_open_run "$target" "$proj"
echo "snapshot_search_positive_control sandbox staged at $proj"
