#!/usr/bin/env bash
# Top-level wiki-skill regression test entrypoint.
#
# Layer 1 is fully deterministic and runs in this shell.
# Layer 2 spawns Claude subagents — it can be run two ways:
#   (a) standalone:   `python3 tests/wiki/layer2/run.py` (uses `claude -p`)
#   (b) interactive:  open a Claude session and paste the canonical
#                     orchestration prompt (tests/wiki/RUNBOOK.md).
#
# This script runs Layer 1 by default and offers Layer 2 invocation hints.
# Pass --layer2 to also run the standalone Layer 2 orchestrator.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LAYER2=false
for arg in "$@"; do
    case "$arg" in
        --layer2|-2) LAYER2=true ;;
        --help|-h)
            cat <<EOF
Usage: $0 [--layer2]

Layer 1 (script-level, deterministic) runs by default.
Layer 2 (skill-level via claude -p) runs only with --layer2.
EOF
            exit 0
            ;;
    esac
done

echo "================================================================"
echo "  Wiki skill regression — Layer 1 (script-level, deterministic)"
echo "================================================================"
"$SCRIPT_DIR/layer1/run.sh"
L1_RC=$?

if ! $LAYER2; then
    cat <<'EOF'

================================================================
  Layer 2 (skill-level via Claude subagents)
================================================================
Layer 2 is not run by default because it spawns Claude subagents and
takes several minutes. Choose one:

  (a) Standalone (CLI):
      python3 tests/wiki/layer2/run.py
      # or override defaults:
      python3 tests/wiki/layer2/run.py --passes 2 --scenario L2-1

  (b) Interactive (in a Claude Code session):
      Open RUNBOOK.md and follow the canonical prompt.

EOF
    exit $L1_RC
fi

echo ""
echo "================================================================"
echo "  Wiki skill regression — Layer 2 (skill-level via claude -p)"
echo "================================================================"
python3 "$SCRIPT_DIR/layer2/run.py"
L2_RC=$?

# Render the HTML report for the latest run (best-effort; non-fatal on miss)
LATEST=$(find "$SCRIPT_DIR/layer2/workspace" -maxdepth 1 -type d -name 'run-*' \
           2>/dev/null | sort | tail -1)
if [[ -n "$LATEST" && -f "$LATEST/benchmark.json" ]]; then
    python3 "$SCRIPT_DIR/layer2/render_report.py" "$LATEST" >/dev/null 2>&1 || true
    echo ""
    echo "Report: $LATEST/report.html"
    echo "Benchmark (markdown): $LATEST/benchmark.md"
fi

if [[ $L1_RC -ne 0 || $L2_RC -ne 0 ]]; then
    exit 1
fi
exit 0
