#!/usr/bin/env bash
# mandated_step_listed: a governing document names a lint command. The run
# writes a row for that step before dispatch and reports it as run with its
# delta, or skipped with its reason.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# alpha\n\nRun `tool.sh alpha --jobs 4`.\n' > "$proj/docs/alpha.md"
printf 'The flag is now --workers everywhere.\n' > "$proj/NOTES.txt"

cat > "$proj/CHARTER.md" <<'CH'
# Charter

Every run over docs/ runs `./lint.sh` and reports its warning count beside the
baseline. The step is planned as a row before any page is dispatched.
CH

cat > "$proj/lint.sh" <<'SH'
#!/usr/bin/env bash
echo "lint: 0 warnings"
exit 0
SH
chmod +x "$proj/lint.sh"

seal "$target" "$proj"
echo "mandated_step_listed sandbox staged at $proj"
