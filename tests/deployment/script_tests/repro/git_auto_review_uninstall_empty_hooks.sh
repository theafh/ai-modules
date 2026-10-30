#!/usr/bin/env bash
# Reproduction for the git_auto_review round-2 finding on the manifest
# uninstall: a hook file whose `hooks` value the deploy does not own is
# preserved by the deploy and recorded as an empty `@entries:` manifest, so the
# uninstall must leave that value alone instead of reducing it to an empty
# result and deleting the key.
#
# Fails on the pre-fix deployment script and passes after the guard.
#
# Usage:
#   bash tests/deployment/script_tests/repro/git_auto_review_uninstall_empty_hooks.sh
#
# DEPLOY_SCRIPT_PATH overrides the script under test; the default is this
# checkout's deployment/deployment.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT_PATH:-${REPO_ROOT}/deployment/deployment.sh}"
DEPLOY_BASH="/bin/bash"
SCRATCH="$(mktemp -d)"

cleanup() {
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -f "$DEPLOY_SCRIPT" ]] || fail "deployment script not found: $DEPLOY_SCRIPT"

# Deploy into a home holding one given hooks.json shape, then uninstall, and
# print the file the uninstall left behind.
run_case() { # name, hooks-json -> the file's compact JSON
  local name="$1"
  local content="$2"
  local home="${SCRATCH}/${name}"
  mkdir -p "${home}/.codex"
  printf '%s\n' "$content" > "${home}/.codex/hooks.json"
  HOME="$home" DEPLOYED_ARTIFACTS_LOG="${home}/deploy.log" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type hook --target codex \
    >"${home}/deploy-stdout" 2>"${home}/deploy-stderr" ||
    fail "${name}: the deploy must exit 0 over a foreign hook shape: $(cat "${home}/deploy-stderr")"
  HOME="$home" DEPLOYED_ARTIFACTS_LOG="${home}/deploy.log" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type hook --target codex --uninstall \
    >"${home}/uninstall-stdout" 2>"${home}/uninstall-stderr" ||
    fail "${name}: the uninstall must exit 0: $(cat "${home}/uninstall-stderr")"
  if grep -q 'still exists after removal' "${home}/uninstall-stdout"; then
    fail "${name}: the uninstall must not report the destination failed: $(cat "${home}/uninstall-stdout")"
  fi
  if grep -q 'hooks\.json\[hooks\]' "${home}/deploy.log" 2>/dev/null; then
    fail "${name}: the uninstall must drop its hooks.json[hooks] log line"
  fi
  jq -c '.' "${home}/.codex/hooks.json" ||
    fail "${name}: the uninstall must leave a parseable hooks.json"
}

assert_case() { # name, hooks-json, expected-json
  local name="$1"
  local content="$2"
  local want="$3"
  local got
  got="$(run_case "$name" "$content")"
  [[ "$got" == "$want" ]] ||
    fail "${name}: the uninstall must leave the hooks value as the deploy found it (got='${got}' want='${want}')"
}

# An empty hooks list is not an entry map, so the deploy owns no entry there
# and records @entries:[]. The uninstall must not delete the key.
assert_case empty-list '{"version":1,"hooks":[]}' '{"version":1,"hooks":[]}'

# A hooks value that is a string survives with its sibling keys.
assert_case string '{"other":1,"hooks":"hand-edited"}' '{"other":1,"hooks":"hand-edited"}'

# A hooks value that is an array survives whole.
assert_case array '{"version":1,"hooks":[{"matcher":"x"}]}' '{"version":1,"hooks":[{"matcher":"x"}]}'

printf 'Uninstall empty-hooks reproduction passed\n'
