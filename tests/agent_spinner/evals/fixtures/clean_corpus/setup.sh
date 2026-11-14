#!/usr/bin/env bash
# clean_corpus: the corpus carries no defect. Every documented command names
# the script by the path it is run from, every documented flag is one the
# command actually parses, and the script's own comment matches its code, so
# the run reports zero findings, invents none, and records what it examined and
# cleared.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs" "$proj/bin"

cat > "$proj/bin/tool.sh" <<'TOOL'
#!/usr/bin/env bash
# Two subcommands. verify parses exactly one optional flag; status parses none.
set -euo pipefail

sub="${1:-}"
shift || true

case "$sub" in
  verify)
    if [ "$#" -gt 1 ]; then
      echo "verify: takes at most one flag" >&2
      exit 2
    fi
    case "${1:-}" in
      --strict) echo "verify: strict mode" ;;
      "")       echo "verify: default mode" ;;
      *)        echo "verify: unknown flag ${1}" >&2; exit 2 ;;
    esac
    ;;
  status)
    if [ "$#" -gt 0 ]; then
      echo "status: takes no flags" >&2
      exit 2
    fi
    echo "status: ok"
    ;;
  *)
    echo "usage: tool.sh {verify [--strict]|status}" >&2
    exit 2
    ;;
esac
TOOL
chmod +x "$proj/bin/tool.sh"

cat > "$proj/docs/verify.md" <<'DOC'
# verify

From the repository root, run `bin/tool.sh verify --strict` to check in strict
mode.

Run `bin/tool.sh verify` with no flag for the default mode. Any other flag
exits 2.
DOC

cat > "$proj/docs/status.md" <<'DOC'
# status

From the repository root, run `bin/tool.sh status`. It takes no arguments, and
any argument exits 2.
DOC

seal "$target" "$proj"
echo "clean_corpus sandbox staged at $proj"
