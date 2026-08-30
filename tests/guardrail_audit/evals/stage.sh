#!/usr/bin/env bash
# stage.sh — stage one guardrail_audit eval and print agent-ready inputs.
#
# Usage:
#   stage.sh <eval_id> [target_dir]
#
# Prints name=value lines (printf %q quoted) for:
#   sandbox_proj, skill_path, hub_path, prompt
#
# After setup, verifies the sandbox is its own git toplevel so a failed
# or blocked init cannot leave us pointing at the host checkout.

set -euo pipefail

eval_id="${1:?eval id required}"
target="${2:-$(mktemp -d "${TMPDIR:-/tmp}/guardrail_audit_eval.XXXXXX")}"
mkdir -p "$target"
target="$(cd "$target" && pwd)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
SKILL_MD="$REPO_ROOT/plugins/ai_dev/skills/guardrail_audit/SKILL.md"
HUB_MD="$REPO_ROOT/plugins/ai_dev/skills/guardrail/SKILL.md"

# shellcheck source=fixtures/_common.sh
. "$HERE/fixtures/_common.sh"

case "$eval_id" in
  presence_gate|doc_vs_doc|doc_vs_code|direction_target|missing_testing|nature_mismatch)
    "$HERE/fixtures/$eval_id/setup.sh" "$target" >/dev/null
    ;;
  *)
    echo "unknown eval id: $eval_id" >&2
    exit 2
    ;;
esac

proj="$target/proj"
if [[ ! -d "$proj" ]]; then
  echo "stage.sh: setup produced no $proj" >&2
  exit 1
fi
ensure_sandbox_git "$proj"
if [[ ! -s "$target/.tree_sha256" ]]; then
  echo "stage.sh: missing $target/.tree_sha256 (setup incomplete)" >&2
  exit 1
fi

prompt="$(
  python3 - "$eval_id" "$HERE/evals.json" <<'PY'
import json, sys
eid, path = sys.argv[1], sys.argv[2]
data = json.load(open(path))
for e in data["evals"]:
    if e["id"] == eid:
        print(e["prompt"])
        break
else:
    raise SystemExit(f"prompt not found for {eid}")
PY
)"

date +%s > "$target/.eval_started_at"

printf 'sandbox_proj=%q\n' "$proj"
printf 'skill_path=%q\n' "$SKILL_MD"
printf 'hub_path=%q\n' "$HUB_MD"
printf 'prompt=%q\n' "$prompt"
