#!/usr/bin/env bash
# Reproduction for the git_auto_review round-2 finding on a foreign event value
# during uninstall: an event the user hand-edited to a string or an object is
# content ai-modules does not own, so both the removal reduce and the success
# check must skip it instead of failing, and the uninstall must report SUCCESS
# and drop its log line.
#
# Fails on the pre-fix deployment script and passes after the guard.
#
# Usage:
#   bash tests/deployment/script_tests/repro/git_auto_review_uninstall_foreign_event.sh
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
# return the uninstall's combined output. The uninstall must exit 0, report its
# line removed rather than failed, and drop the log line.
run_case() { # name, hooks-json -> uninstall output
  local name="$1"
  local content="$2"
  local home="${SCRATCH}/${name}"
  mkdir -p "${home}/.codex"
  printf '%s\n' "$content" > "${home}/.codex/hooks.json"
  HOME="$home" DEPLOYED_ARTIFACTS_LOG="${home}/deploy.log" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type hook --target codex \
    >"${home}/deploy-stdout" 2>"${home}/deploy-stderr" ||
    fail "${name}: the deploy must exit 0 over a foreign event value: $(cat "${home}/deploy-stderr")"
  HOME="$home" DEPLOYED_ARTIFACTS_LOG="${home}/deploy.log" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type hook --target codex --uninstall \
    >"${home}/uninstall-stdout" 2>"${home}/uninstall-stderr" ||
    fail "${name}: the uninstall must exit 0 over a foreign event value: $(cat "${home}/uninstall-stderr") $(cat "${home}/uninstall-stdout")"
  if grep -q 'still exists after removal' "${home}/uninstall-stdout"; then
    fail "${name}: the uninstall must report its line removed rather than failed: $(cat "${home}/uninstall-stdout")"
  fi
  grep -q 'removed.*hooks\.json\[hooks\]' "${home}/uninstall-stdout" ||
    fail "${name}: the uninstall must report the hooks.json[hooks] line removed: $(cat "${home}/uninstall-stdout")"
  if grep -q 'hooks\.json\[hooks\]' "${home}/deploy.log" 2>/dev/null; then
    fail "${name}: the uninstall must drop its hooks.json[hooks] log line"
  fi
  jq -c '.' "${home}/.codex/hooks.json" ||
    fail "${name}: the uninstall must leave a parseable hooks.json"
}

assert_case() { # name, hooks-json, expected-hooks-json
  local name="$1"
  local content="$2"
  local want="$3"
  local got
  got="$(run_case "$name" "$content")"
  [[ "$got" == "$want" ]] ||
    fail "${name}: the uninstall must leave the foreign event value and remove only the owned entry (got='${got}' want='${want}')"
}

# A string event value beside a mergeable one: the deploy merges the mergeable
# event and leaves the string alone. Pre-fix the removal reduce failed with
# "Cannot iterate over string".
assert_case mixed-string '{"hooks":{
  "PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]}],
  "PostToolUse":"hand-edited"
}}' '{"hooks":{"PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]}],"PostToolUse":"hand-edited"}}'

# An object event value alone: the deploy owns nothing, and the success check
# reached ident() on a string member. Pre-fix the uninstall printed
# "still exists after removal".
assert_case object-event '{"version":1,"hooks":{"PreToolUse":{"matcher":"x"}}}' \
  '{"version":1,"hooks":{"PreToolUse":{"matcher":"x"}}}'

# An event list holding a non-object member is not an entry list either.
assert_case junk-member '{"hooks":{"PreToolUse":[
  {"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]},
  "hand-edited"
]}}' '{"hooks":{"PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]},"hand-edited"]}}'

printf 'Uninstall foreign-event reproduction passed\n'
