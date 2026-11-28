#!/usr/bin/env bash
# checker_generic_over_found_role: one page edited from a recorded instruction,
# with its baseline. The host registers the read-only checker role, so the probe
# finds it, but the prompt asks for the generic helper, so the run records a
# generic route and a narrowing naming the user's choice.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/baseline"

cat > "$proj/INSTRUCTION.txt" <<'INSTRUCTION'
Recorded instruction: set the retry count in settings.md to 5.
INSTRUCTION
printf '# Settings\n\nretry count: 3\n' > "$proj/baseline/settings.md"
printf '# Settings\n\nretry count: 5\n' > "$proj/settings.md"

seal "$target" "$proj"
echo "checker_generic_over_found_role sandbox staged at $proj"
