#!/usr/bin/env bash
# Entrypoint for deterministic task_auto_check regression checks.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/script_tests/run.sh"
