#!/usr/bin/env bash
# wide_run_plans_session_boundary: a sweep over one hundred twenty pages whose
# request states the host's context window. The announcement states the context
# estimate and names the wave end where the session boundary falls.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

for n in $(seq -w 1 120); do
  printf '# page %s\n\nThis page describes the legacy path.\n' "$n" \
    > "$proj/docs/page$n.md"
done

seal "$target" "$proj"
echo "wide_run_plans_session_boundary sandbox staged at $proj"
