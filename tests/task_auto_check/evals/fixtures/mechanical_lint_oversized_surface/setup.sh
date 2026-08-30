#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/api"
cat > "$target/proj/docs/api.md" <<'EOF'
# API

## Audit log

Documented audit-log behavior appears here.
EOF
audit_py="$target/proj/src/api/audit.py"
cat > "$audit_py" <<'EOF'
AUDIT_SCHEMA_VERSION = 1

AUDIT_EVENT_FIELDS = [
EOF
for i in $(seq 1 320); do
  printf '    "field_%d",\n' "$i" >> "$audit_py"
done
cat >> "$audit_py" <<'EOF'
]


def audit_event(payload):
    """Emit one audit-log event carrying every schema field."""
    return {name: payload.get(name) for name in AUDIT_EVENT_FIELDS}
EOF

# Target task: a single cohesive documentation unit that nonetheless exceeds the
# 300-line linter ceiling. Oversize is a judgement-call (split) finding, not a
# mechanically fixable one, so finalization surfaces it and leaves the file
# untouched rather than truncating or auto-splitting it.
task="$target/proj/tasks/api_audit-log-ready.md"
cat > "$task" <<'EOF'
---
description: Document every field of the API audit-log event schema so downstream consumers can parse audit events reliably.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: ready
reported-by: Harness
---

# API audit-log event schema docs

## Goal

Document each field of the API audit-log event schema so downstream consumers can parse audit events reliably from a single authoritative reference.

## Context

`docs/api.md` documents public API behavior. `src/api/audit.py` emits the audit-log event; its `AUDIT_EVENT_FIELDS` constant carries the field names only. Each field's type, meaning, and emission condition are defined solely by the enumeration below — they exist nowhere in the code and are the content this task documents.

EOF

types=("string" "integer" "ISO-8601 timestamp" "boolean")
verbs=("captures" "records" "flags" "reports")
for i in $(seq 1 320); do
  t="${types[$((i % 4))]}"
  v="${verbs[$(((i / 4) % 4))]}"
  printf -- '- field_%d (%s): %s audit condition %d for downstream consumers.\n' "$i" "$t" "$v" "$i" >> "$task"
done

cat >> "$task" <<'EOF'

## Approach

Update `docs/api.md` to document every audit-log field enumerated above under a single audit-log section, keyed by the attribute name.

## Acceptance

- `docs/api.md` documents each enumerated audit-log field under the audit-log section.
- Running `grep -c '^### field_' docs/api.md` after the docs edit returns 320 — one documented section per enumerated field.
EOF

commit_proj "$target"
