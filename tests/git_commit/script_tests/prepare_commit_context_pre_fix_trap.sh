#!/usr/bin/env bash
# Pre-fix EXIT-trap shape for the injected-abort script-test scenario.
#
# Keeps only trap 'rm -rf "$tmp_dir"' EXIT (cleanup with no completion flag).
# The scenario copies this stub, inserts one unbound-variable reference after
# the trap line, and runs the copy under /bin/bash. On bash 3.2 that abort
# exits 0 because $? is masked inside the EXIT trap; the fixed prepare script
# exits non-zero for the same injection.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# Reachable body so the trap is installed before any later statement. The
# scenario injects an unbound reference immediately after the trap line above.
printf 'pre-fix stub marker\n' >"$tmp_dir/marker"
