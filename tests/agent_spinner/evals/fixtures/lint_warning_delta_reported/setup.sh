#!/usr/bin/env bash
# lint_warning_delta_reported: the lint gate reports 2 warnings at the baseline
# and 17 after the requested edit, with none blocking. The gate lines record
# both values, the report states the move, and no sentence calls the lint
# clean.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# alpha\n\nRun `tool.sh alpha --jobs 4`.\n' > "$proj/docs/alpha.md"
cat > "$proj/lint.sh" <<'SH'
#!/usr/bin/env bash
# A warning-only lint: it always exits 0 and prints its warning count.
count="$(cat warnings.txt 2>/dev/null || echo 0)"
echo "lint: ${count} warnings"
exit 0
SH
chmod +x "$proj/lint.sh"
printf '2\n' > "$proj/warnings.txt"

commit_tree "$proj"
run_ledger "$proj" init --phase check --bound 240 \
  --gate "lint=./lint.sh" --unit produce:alpha \
  --unit-path produce:alpha=docs/alpha.md >/dev/null

# The requested edit raises the warning count, none of them blocking.
printf '17\n' > "$proj/warnings.txt"
stage_row "$proj" produce:alpha "Rewrite docs/alpha.md to use --workers." --target docs/alpha.md
write_return "$proj" produce:alpha "done" pass '{
  "_prose": "produce:alpha — docs/alpha.md is updated."
}'

seal_open_run "$target" "$proj"
echo "lint_warning_delta_reported sandbox staged at $proj"
