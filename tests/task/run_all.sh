#!/usr/bin/env bash
# Entrypoint for the task skill's deterministic regression surfaces.
#
# Drives both bundled-script runners, in order:
#   - script_tests/run.sh          — lint.py / discover_tasks.sh /
#                                    init_tasks.sh unit tests
#   - script_tests/contract_run.sh — family contract assertions over the
#                                    hub, its siblings, and the family agents
#
# Both run on every invocation and the exit code aggregates them, so a
# failure in the first surface still leaves the second one's verdict
# visible. Skill-prose behavior is covered separately by tests/task/evals/
# under the skill-creator convention — run that out-of-band, not from here.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/script_tests/run.sh"
UNIT_RC=$?

bash "$SCRIPT_DIR/script_tests/contract_run.sh"
CONTRACT_RC=$?

if [ "$UNIT_RC" -ne 0 ] || [ "$CONTRACT_RC" -ne 0 ]; then
    printf 'FAIL: script_tests/run.sh rc=%s, script_tests/contract_run.sh rc=%s\n' \
        "$UNIT_RC" "$CONTRACT_RC" >&2
    exit 1
fi
exit 0
