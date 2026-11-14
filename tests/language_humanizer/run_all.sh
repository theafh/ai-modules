#!/usr/bin/env bash
# Top-level language_humanizer regression entrypoint for the deterministic
# surface.
#
# language_humanizer ships no bundled scripts, so the deterministic surface is
# the static contract (script_tests/run.sh), the grader's own unit tests
# (evals/test_grade.py), which prove grade.py passes a faithful rewrite and
# fails each lossy one, the judge-command unit tests (evals/test_judge.py),
# which prove the judge command carries the resolved judge model and effort,
# and the runner unit tests (evals/test_run.py), which prove every run and
# re-grade record carries the worker and judge settings and that a re-grade
# refuses to compare across a judge vendor, model, or effort difference.
#
# The behavioral evals under evals/ are intentionally not run from here. They
# spawn workers and consume tokens; see RUNBOOK.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            cat <<USAGE
Usage: $0

Runs the static contract checks (script_tests/run.sh), the grader unit
tests (evals/test_grade.py), the judge-command unit tests
(evals/test_judge.py), and the runner unit tests (evals/test_run.py).

For the behavioral evals, see tests/language_humanizer/RUNBOOK.md.
USAGE
            exit 0
            ;;
    esac
done

echo "================================================================"
echo "  language_humanizer regression: static contract"
echo "================================================================"
"$SCRIPT_DIR/script_tests/run.sh"
RC_STATIC=$?

echo
echo "================================================================"
echo "  language_humanizer regression: grader unit tests"
echo "================================================================"
python3 "$SCRIPT_DIR/evals/test_grade.py"
RC_GRADE=$?

echo
echo "================================================================"
echo "  language_humanizer regression: judge-command unit tests"
echo "================================================================"
python3 "$SCRIPT_DIR/evals/test_judge.py"
RC_JUDGE=$?

echo
echo "================================================================"
echo "  language_humanizer regression: runner unit tests"
echo "================================================================"
python3 "$SCRIPT_DIR/evals/test_run.py"
RC_RUN=$?

cat <<'NOTE'

================================================================
  Behavioral evals
================================================================
Three scenarios over a fixed five-pass denominator live under
tests/language_humanizer/evals/. They are NOT run from this entrypoint,
because they spawn workers and consume tokens. See RUNBOOK.md.
NOTE

if ((RC_STATIC != 0 || RC_GRADE != 0 || RC_JUDGE != 0 || RC_RUN != 0)); then
    exit 1
fi
exit 0
