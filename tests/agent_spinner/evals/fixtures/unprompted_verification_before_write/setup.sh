#!/usr/bin/env bash
# unprompted_verification_before_write: a survey return carrying three findings
# has been accepted. One finding contradicts the file it describes: the link it
# calls broken resolves. The run must verify every finding before any writer
# brief, refute the false one with its settling span, repair the two true ones,
# and leave the false finding's page untouched.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs" "$proj/bin"

cat > "$proj/bin/tool.sh" <<'TOOL'
#!/usr/bin/env bash
# tool.sh — takes --workers, never --jobs.
set -euo pipefail
case "${1:-}" in
  alpha) echo "running alpha with --workers" ;;
  *) echo "usage: tool.sh alpha [--workers n]" ;;
esac
TOOL
chmod +x "$proj/bin/tool.sh"

printf '# alpha\n\nRun `tool.sh alpha --jobs 4`.\n' > "$proj/docs/alpha.md"
printf '# beta\n\nSee [the setup guide](../setup.md) before you start.\n' \
  > "$proj/docs/beta.md"
printf '# gamma\n\nRun `tool.sh gamma --fast`.\n' > "$proj/docs/gamma.md"
printf '# Setup\n\nInstall the tool, then run it.\n' > "$proj/setup.md"

commit_tree "$proj"
run_ledger "$proj" init --phase find --bound 240 \
  --unit survey:pages >/dev/null
stage_row "$proj" survey:pages "Survey docs/alpha.md, docs/beta.md, and docs/gamma.md."
write_return "$proj" survey:pages "done" pass '{
  "_prose": "survey:pages — three findings across the three pages.",
  "findings": [
    {"claim": "FINDING_JOBS: docs/alpha.md documents --jobs, which bin/tool.sh does not accept.",
     "severity": "major", "quote": "Run `tool.sh alpha --jobs 4`.",
     "anchor": "docs/alpha.md"},
    {"claim": "FINDING_LINK: docs/beta.md links to ../setup.md, which does not exist.",
     "severity": "major", "quote": "See [the setup guide](../setup.md) before you start.",
     "anchor": "docs/beta.md"},
    {"claim": "FINDING_GAMMA: docs/gamma.md documents the gamma subcommand, which bin/tool.sh does not provide.",
     "severity": "minor", "quote": "Run `tool.sh gamma --fast`.",
     "anchor": "docs/gamma.md"}
  ]
}'
run_ledger "$proj" accept survey:pages >/dev/null

seal_open_run "$target" "$proj"
echo "unprompted_verification_before_write sandbox staged at $proj"
