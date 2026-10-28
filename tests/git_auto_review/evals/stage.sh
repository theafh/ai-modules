#!/usr/bin/env bash
# stage.sh: stage one git_auto_review eval and print the agent-ready inputs.
#
# Usage:
#   stage.sh <eval_id> [target_dir]
#
# Prints name=value lines on stdout, each value quoted with printf %q so the
# lines are safe to `eval`:
#
#   sandbox_repo=<absolute path to the git repo the loop targets>
#   skill_name=git_auto_review
#   skill_path=<the source SKILL.md the runner deploys>
#   prompt=<the user prompt to feed the worker>
#   agent=<target agent name for a direct-agent eval, else empty>
#
# The fixture and prompt come from evals.json, so the two files cannot drift
# apart as evals are added. Every fixture stages its own repository under
# $target/repo and, for a canned gate result, a marked pre-seeded gate-return
# pair under the relay the skill derives.

set -euo pipefail

eval_id="${1:?eval id required (see evals.json)}"
target="${2:-$(mktemp -d "${TMPDIR:-/tmp}/git_auto_review_eval.XXXXXX")}"
mkdir -p "$target"
target="$(cd "$target" && pwd)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
SKILL_MD="$REPO_ROOT/plugins/ai_dev/skills/git_auto_review/SKILL.md"

{ read -r fixture; read -r prompt; read -r agent; } < <(python3 - "$HERE/evals.json" "$eval_id" <<'PY'
import json, sys

evals = json.load(open(sys.argv[1]))["evals"]
wanted = str(sys.argv[2])
for e in evals:
    if str(e["id"]) == wanted:
        print(e["files"][0].split("/")[2])
        print(json.dumps(e["prompt"]))
        print(e.get("agent", ""))
        break
else:
    sys.exit("unknown eval id: %s" % wanted)
PY
)

# The prompt arrives JSON-encoded so a multi-line or quote-carrying prompt
# survives the single line above; decode it back here.
prompt="$(python3 -c 'import json,sys; sys.stdout.write(json.loads(sys.argv[1]))' "$prompt")"

bash "$HERE/fixtures/$fixture/setup.sh" "$target" >/dev/null

sandbox_repo="$target/repo"
git -C "$sandbox_repo" rev-parse HEAD > "$target/.eval_started_at"

printf 'sandbox_repo=%s\n' "$(printf %q "$sandbox_repo")"
printf 'skill_name=%s\n' "$(printf %q "git_auto_review")"
printf 'skill_path=%s\n' "$(printf %q "$SKILL_MD")"
printf 'prompt=%s\n' "$(printf %q "$prompt")"
printf 'agent=%s\n' "$(printf %q "$agent")"
