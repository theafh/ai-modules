#!/usr/bin/env bash
# Top-level natural_language regression entrypoint for the deterministic
# surface.
#
# natural_language is behavioral-only: the subject is an output style, so the
# harness ships no script_tests/. Its deterministic surface is the runner's
# unit tests (evals/test_run.py), the grader's unit tests
# (evals/test_grade.py), and the judge-command unit tests
# (evals/test_judge.py), none of which starts a worker.
#
# The behavioral evals under evals/ are intentionally not run from here. They
# spawn Claude workers; see RUNBOOK.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            cat <<USAGE
Usage: $0

Runs the runner's unit tests (evals/test_run.py), the grader's unit tests
(evals/test_grade.py), and the judge-command unit tests (evals/test_judge.py).
None of them starts a worker.

For the behavioral evals, see tests/natural_language/RUNBOOK.md.
USAGE
            exit 0
            ;;
    esac
done

echo "================================================================"
echo "  natural_language regression: runner unit tests"
echo "================================================================"
python3 "$SCRIPT_DIR/evals/test_run.py"
RC_RUN=$?

echo
echo "================================================================"
echo "  natural_language regression: grader unit tests"
echo "================================================================"
python3 "$SCRIPT_DIR/evals/test_grade.py"
RC_GRADE=$?

echo
echo "================================================================"
echo "  natural_language regression: judge-command unit tests"
echo "================================================================"
python3 "$SCRIPT_DIR/evals/test_judge.py"
RC_JUDGE=$?

cat <<'NOTE'

================================================================
  Behavioral evals
================================================================
Two scenarios over a fixed five-pass denominator live under
tests/natural_language/evals/. They are NOT run from this entrypoint,
because they spawn Claude workers. See RUNBOOK.md.
NOTE

if ((RC_RUN != 0 || RC_GRADE != 0 || RC_JUDGE != 0)); then
    exit 1
fi
exit 0
