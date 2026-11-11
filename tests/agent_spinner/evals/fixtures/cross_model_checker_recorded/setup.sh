#!/usr/bin/env bash
# cross_model_checker_recorded: a request that asks for each checker to run on a
# model other than its producer's. The roster records a requested checker model
# that differs from its producer's, and the report names the cross-model benefit
# as unmeasured. Claude-only: a per-spawn model choice is the Claude feature it
# exercises.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs" "$proj/bin"

cat > "$proj/bin/tool.sh" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  page) echo "page takes --jobs" ;;
  *)    echo "usage: tool.sh page" ;;
esac
TOOL
chmod +x "$proj/bin/tool.sh"

printf '# page\n\nRun `tool.sh page --jobs 4`.\n' > "$proj/docs/page.md"

seal "$target" "$proj"
echo "cross_model_checker_recorded sandbox staged at $proj"
