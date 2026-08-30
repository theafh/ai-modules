#!/usr/bin/env bash
# Top-level git_refresh-skill regression test entrypoint.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            cat <<EOF
Usage: $0

Runs the bundled-script unit tests (script_tests/run.sh).

Skill-level eval definitions live under tests/git_refresh/evals/. They are
executed through the session-level skill-creator workflow, not this entrypoint.
EOF
            exit 0
            ;;
    esac
done

echo "================================================================"
echo "  git_refresh skill regression - bundled-script unit tests"
echo "================================================================"
"$SCRIPT_DIR/script_tests/run.sh"
RC=$?

cat <<'EOF'

================================================================
  Skill evals (skill-creator workflow)
================================================================
Skill behavior tests live under tests/git_refresh/evals/. They are
not run from this entrypoint because they require an agent to execute
the skill against staged repositories.
EOF

exit $RC
