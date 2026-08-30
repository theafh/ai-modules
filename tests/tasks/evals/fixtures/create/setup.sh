#!/usr/bin/env bash
# create fixture: an empty backlog. The agent must write exactly one
# well-formed task and stamp created/updated from the real wall clock.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"

echo "create sandbox staged at $proj"
