#!/usr/bin/env bash
# Top-level ai_instruction_formatting regression test entrypoint.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            cat <<EOF
Usage: $0

Runs the deterministic bundled-script tests for ai_instruction_formatting's
pseudo-XML linter.
EOF
            exit 0
            ;;
    esac
done

echo "================================================================"
echo "  ai_instruction_formatting regression - pseudo-XML linter"
echo "================================================================"
"$SCRIPT_DIR/script_tests/run.sh"
