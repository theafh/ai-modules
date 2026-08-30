#!/usr/bin/env bash
# Entry point for skill_doctor bundled-script unit tests.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/script_tests/run.sh"
