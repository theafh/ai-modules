#!/usr/bin/env bash
# tests/spr/run_all.sh — deterministic entrypoint for the
# spr behavioral harness.
#
# Runs the grader's own PASS/FAIL script tests. The behavioral evals spawn a
# vendor worker, so they run out of band via evals/run.py.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$HERE/script_tests/run.sh"
