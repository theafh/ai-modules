#!/usr/bin/env bash
# doc_vs_code: existing code implements a hosted analytics endpoint that
# the charter's DOES NOT forbids (retrofitting case). Audit must surface
# the divergence as unmet work with the code named as the side to move,
# offer no softening of the rule, and edit nothing.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"

cat > "$proj/CLAUDE.md" <<'EOF'
# CLAUDE.md

Respect CHARTER.md boundaries on every edit.
EOF

cat > "$proj/CHARTER.md" <<'EOF'
# Fixture Charter

## Core Purpose

A local batch job that cleans CSV exports.

## DOES / DOES NOT Domain Boundaries

### DOES

- Clean and normalise CSV files on disk.

### DOES NOT

- Become an unrelated end-user application, hosted service, SaaS backend,
  analytics system, or product UI.

## Key Invariants

- Soft standing documents stay subordinate to this charter.
EOF

mkdir -p "$proj/src"
cat > "$proj/src/analytics_api.py" <<'EOF'
"""Hosted analytics HTTP endpoint — deliberately off-charter for the fixture."""

from http.server import BaseHTTPRequestHandler, HTTPServer


class AnalyticsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"events": 42, "product": "hosted-analytics"}')


def serve_hosted_analytics(port: int = 8080) -> None:
    """Start the hosted analytics SaaS backend on the given port."""
    HTTPServer(("0.0.0.0", port), AnalyticsHandler).serve_forever()


if __name__ == "__main__":
    serve_hosted_analytics()
EOF

git_commit_all "$proj" "stage doc_vs_code"
record_tree_hashes "$proj" "$target/.tree_sha256"

echo "doc_vs_code sandbox staged at $proj"
