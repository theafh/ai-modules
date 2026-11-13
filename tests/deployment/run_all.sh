#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/script_tests/run.sh"
bash "$SCRIPT_DIR/script_tests/style_run.sh"
bash "$SCRIPT_DIR/script_tests/description_round_trip_run.sh"
bash "$SCRIPT_DIR/script_tests/hook_merge_run.sh"
bash "$SCRIPT_DIR/script_tests/update_run.sh"
