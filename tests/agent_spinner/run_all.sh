#!/usr/bin/env bash
# Top-level agent_spinner regression entrypoint.
#
# agent_spinner ships no bundled scripts, so the deterministic surface here is
# the static contract: SKILL.md budgets and blocks, the reference set, the
# per-harness greps that must stay empty, and registration lockstep.
#
# The behavioral evals under evals/ are intentionally not run from here. They
# spawn vendor workers (`agent -p` by default) and consume tokens; see evals/README.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            cat <<USAGE
Usage: $0

Runs the static contract checks (script_tests/run.sh).

For the behavioral evals, see tests/agent_spinner/evals/README.md.
USAGE
            exit 0
            ;;
    esac
done

echo "================================================================"
echo "  agent_spinner skill regression — static contract"
echo "================================================================"
"$SCRIPT_DIR/script_tests/run.sh"
RC=$?

cat <<'NOTE'

================================================================
  Behavioral evals
================================================================
Twenty-one staged evals live under tests/agent_spinner/evals/. They are
NOT run from this entrypoint — they spawn workers and consume tokens.
See tests/agent_spinner/evals/README.md.
NOTE

exit $RC
