#!/usr/bin/env bash
# update_features harness - deterministic entrypoint.
#
# Runs the shipped helper's script tests. The behavioural eval that exercises
# the skill end to end lives in evals/evals.json and runs out of band through
# the skill-creator runner, so this entrypoint stays fast and network-free.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/script_tests/run.sh"
