#!/usr/bin/env bash
# probe_positive_control: a page holding two dashes and one percentage, and a
# request for those counts. The fixture registers one counter per count, so the
# run's counter check must pass each counter's positive control before the gate
# may report a count. The ledger then records counts of 2 and 1, each beside a
# counter whose positive control passed.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs" "$proj/bin"

cat > "$proj/docs/page.md" <<'DOC'
# Numbers

The first dash — and the second dash — frame the aside.

About 95% of reads hit the cache.
DOC

cat > "$proj/bin/count.sh" <<'SH'
#!/usr/bin/env bash
printf 'dashes: 2\npercentages: 1\n'
SH
chmod +x "$proj/bin/count.sh"

commit_tree "$proj"
# One counter per count. Each pattern must fire on the ledger's known positive
# when `diff --count` runs, which is the positive control a count gate needs.
run_ledger "$proj" init --phase measure --bound 240 \
  --unit measure:page --unit-path measure:page=docs/page.md \
  --gate count=./bin/count.sh \
  --counter 'dashes=—|CONTROL_MARKER' \
  --counter 'percentages=%|CONTROL_MARKER' >/dev/null

seal_open_run "$target" "$proj"
echo "probe_positive_control sandbox staged at $proj"
