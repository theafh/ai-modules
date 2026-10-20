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

The behavioral evals under tests/git_refresh/evals/ run through their own
runner, not this entrypoint:
  python3 tests/git_refresh/evals/run.py
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
  Skill behavioral evals
================================================================
Skill behavior tests live under tests/git_refresh/evals/. Run them with
  python3 tests/git_refresh/evals/run.py
which stages each eval, runs one vendor worker per eval on the default
Cursor worker, and grades the repository with evals/grade.sh.
EOF

exit $RC
