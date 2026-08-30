#!/usr/bin/env bash
# Top-level git_commit-skill regression test entrypoint.
#
# Two surfaces:
#   - script_tests/  — deterministic bash unit tests for the bundled
#                      scripts (prepare_commit_context.sh,
#                      commit_with_message.sh). Runs in this shell.
#   - evals/         — skill-creator-aligned skill evals. Run via
#                      skill-creator's runner (out-of-band).
#
# This script runs the bundled-script unit tests by default. The skill
# evals are intentionally not auto-run here — they consume LLM tokens
# and follow skill-creator's iteration workflow.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            cat <<EOF
Usage: $0

Runs the bundled-script unit tests (script_tests/run.sh).

For skill-level evals, see tests/git_commit/evals/README.md — those
run under skill-creator's eval workflow, not from this entrypoint.
EOF
            exit 0
            ;;
    esac
done

echo "================================================================"
echo "  git_commit skill regression — bundled-script unit tests"
echo "================================================================"
"$SCRIPT_DIR/script_tests/run.sh"
RC=$?

cat <<'EOF'

================================================================
  Skill evals (skill-creator workflow)
================================================================
Skill behavior tests live under tests/git_commit/evals/. They are
NOT run from this entrypoint — they spawn subagents and consume LLM
tokens. See tests/git_commit/evals/README.md for the workflow.
EOF

exit $RC
