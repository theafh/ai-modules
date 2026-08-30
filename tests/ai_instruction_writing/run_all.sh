#!/usr/bin/env bash
# Top-level ai_instruction_writing regression test entrypoint.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            cat <<EOF
Usage: $0

Runs the deterministic content-contract tests for ai_instruction_writing.
EOF
            exit 0
            ;;
    esac
done

echo "================================================================"
echo "  ai_instruction_writing regression - content contract"
echo "================================================================"
"$SCRIPT_DIR/script_tests/run.sh"
