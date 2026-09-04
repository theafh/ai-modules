#!/usr/bin/env bash
# Top-level git_review-skill regression test entrypoint.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            cat <<USAGE
Usage: $0

Runs the bundled-script unit tests (script_tests/run.sh).

Skill-level evals live under tests/git_review/evals/ and are driven by
evals/run.py, which spawns one sonnet-pinned worker per eval. They are not run
from this entrypoint because each one costs an LLM call.
USAGE
            exit 0
            ;;
    esac
done

echo "================================================================"
echo "  git_review skill regression - bundled-script unit tests"
echo "================================================================"
"$SCRIPT_DIR/script_tests/run.sh"
RC=$?

cat <<'EOF_NOTE'

================================================================
  Skill evals (sonnet-pinned workers)
================================================================
Skill behavior tests live under tests/git_review/evals/. Run them with:

    python3 tests/git_review/evals/run.py            # every eval
    python3 tests/git_review/evals/run.py 1 13 32    # a subset

They are not run from this entrypoint because each eval spawns a claude -p
worker.
EOF_NOTE

exit $RC
