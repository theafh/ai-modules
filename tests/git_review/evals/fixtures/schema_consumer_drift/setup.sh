#!/usr/bin/env bash
# The change edits a schema definition that a consumer elsewhere in the tree
# still reads under its old field name.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p schema services
cat > schema/order.json <<'JSON'
{
  "type": "object",
  "properties": {
    "order_id": {"type": "string"},
    "customer_email": {"type": "string"},
    "total_cents": {"type": "integer"}
  },
  "required": ["order_id", "customer_email", "total_cents"]
}
JSON
cat > services/invoicing.py <<'PY'
import json


def render(order):
    """Render an invoice line from one order record."""
    return "{}: {} to {}".format(
        order["order_id"], order["total_cents"], order["customer_email"]
    )


def load(path):
    with open(path) as fh:
        return json.load(fh)
PY
git add -A
git commit --quiet -m "seed order schema and the invoicing consumer"
git push --quiet origin main

git checkout --quiet -b rename-email-field
cat > schema/order.json <<'JSON'
{
  "type": "object",
  "properties": {
    "order_id": {"type": "string"},
    "contact_email": {"type": "string"},
    "total_cents": {"type": "integer"}
  },
  "required": ["order_id", "contact_email", "total_cents"]
}
JSON
git add -A
git commit --quiet -m "schema/order.json -> rename customer_email to contact_email"
git push --quiet -u origin rename-email-field
printf '%s\n' "$repo"
