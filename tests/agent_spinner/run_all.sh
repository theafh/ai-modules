#!/usr/bin/env bash
# Top-level agent_spinner regression entrypoint.
#
# agent_spinner bundles one program, scripts/run_ledger.py, so the deterministic
# surface here is three runners: the static contract (SKILL.md budgets and
# blocks, the reference set, the per-harness greps that must stay empty, and the
# ledger's stdlib-only and read-only-git contract), the ledger's own script
# tests, and the eval runner's plumbing test against a stub worker.
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

Runs the static contract checks (script_tests/run.sh), the ledger script tests
(script_tests/ledger_run.sh), and the eval runner's plumbing test
(evals/test_run.py), with one aggregated exit code.

For the behavioral evals, see tests/agent_spinner/evals/README.md.
USAGE
            exit 0
            ;;
    esac
done

RC=0

echo "================================================================"
echo "  agent_spinner skill regression — static contract"
echo "================================================================"
"$SCRIPT_DIR/script_tests/run.sh" || RC=1

echo
echo "================================================================"
echo "  agent_spinner run ledger — script tests"
echo "================================================================"
"$SCRIPT_DIR/script_tests/ledger_run.sh" || RC=1

echo
echo "================================================================"
echo "  agent_spinner eval runner — plumbing (no live worker)"
echo "================================================================"
python3 "$SCRIPT_DIR/evals/test_run.py" || RC=1

cat <<'NOTE'

================================================================
  Behavioral evals
================================================================
The staged evals under tests/agent_spinner/evals/ are NOT run from this
entrypoint — they spawn workers and consume tokens. The runner's plumbing
test above runs without a live worker.
See tests/agent_spinner/evals/README.md.
NOTE

exit $RC
