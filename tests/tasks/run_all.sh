#!/usr/bin/env bash
# Entrypoint for the tasks skill's bundled-script unit tests.
#
# Drives script_tests/run.sh (deterministic, no LLM cost). Skill-prose
# behavior is covered separately by tests/tasks/evals/ under the
# skill-creator convention — run that out-of-band, not from here.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/script_tests/run.sh"
