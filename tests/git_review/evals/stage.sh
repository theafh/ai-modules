#!/usr/bin/env bash
# stage.sh: stage one git_review eval and print the agent-ready inputs.
#
# Usage:
#   stage.sh <eval_id> [target_dir]
#
# Prints name=value lines on stdout, each value already quoted with printf %q so
# the lines are safe to `eval`:
#
#   sandbox_repo=<absolute path to the git repo the skill reviews>
#   prompt=<the user prompt to feed the agent>
#   target=<the fixture root, one level above the repo>
#   gh_env=<path to the stub-gh env file, or empty when the eval has none>
#
# The fixture and the prompt come from evals.json rather than from a case arm
# here, so the two files cannot drift apart as evals are added. The skills
# under test are not staged here: run.py micro-deploys git_review, git_checkout,
# git_commit, git_refresh, and the guardrail hub per eval and wraps their
# deployed scripts in logging shims.
#
# Layout: every eval stages under $target as
#   $target/repo                 the git repo the agent reviews
#   $target/payloads/            (forge evals) the JSON the stub gh serves
#   $target/bin/gh               (forge evals) the stub gh itself
#   $target/gh_calls.log         (forge evals) every stub invocation, one per line
#   $target/gh_env               (forge evals) the env the runner passes through
#   $target/script_calls.log     every bundled-script invocation, one per line
#   $target/.eval_started_at     the staged HEAD SHA, for grade.sh

set -euo pipefail

eval_id="${1:?eval id required (see evals.json)}"
target="${2:-$(mktemp -d "${TMPDIR:-/tmp}/git_review_eval.XXXXXX")}"
mkdir -p "$target"
target="$(cd "$target" && pwd)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

read -r fixture prompt < <(python3 - "$HERE/evals.json" "$eval_id" <<'PY'
import json, sys
evals = json.load(open(sys.argv[1]))["evals"]
wanted = str(sys.argv[2])
for e in evals:
    if str(e["id"]) == wanted:
        # The fixture path is evals/fixtures/<name>/setup.sh.
        print(e["files"][0].split("/")[2], json.dumps(e["prompt"]))
        break
else:
    sys.exit("unknown eval id: %s" % wanted)
PY
)

# The prompt arrives JSON-encoded so a multi-line or quote-carrying prompt
# survives the single line above; decode it back here.
prompt="$(python3 -c 'import json,sys; sys.stdout.write(json.loads(sys.argv[1]))' "$prompt")"

"$HERE/fixtures/$fixture/setup.sh" "$target" >/dev/null

# The runner's logging shims append one line per bundled-script call here.
: > "$target/script_calls.log"

sandbox_repo="$target/repo"
git -C "$sandbox_repo" rev-parse HEAD > "$target/.eval_started_at"

gh_env=""
[[ -f "$target/gh_env" ]] && gh_env="$target/gh_env"

printf 'sandbox_repo=%s\n' "$(printf %q "$sandbox_repo")"
printf 'prompt=%s\n'       "$(printf %q "$prompt")"
printf 'target=%s\n'       "$(printf %q "$target")"
printf 'gh_env=%s\n'       "$(printf %q "$gh_env")"
