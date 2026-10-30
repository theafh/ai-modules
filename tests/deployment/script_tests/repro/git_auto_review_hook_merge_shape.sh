#!/usr/bin/env bash
# Reproduction for the git_auto_review round-1 finding on the entry-grain hook
# merge: a hook file whose `hooks` value is not an object, or whose event value
# is not an array of objects, is content ai-modules does not own, so the deploy
# preserves it and still succeeds instead of aborting the whole run.
#
# Fails on the pre-fix deployment script and passes after the guard.
#
# Usage:
#   bash tests/deployment/script_tests/repro/git_auto_review_hook_merge_shape.sh
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

# Deploy the global Codex hooks into a home holding one given hooks.json shape.
# Prints the deploy's exit code; the file it wrote stays for inspection.
run_case() { # name, hooks-json -> exit code
  local name="$1"
  local content="$2"
  local home="${SCRATCH}/${name}"
  mkdir -p "${home}/.codex"
  printf '%s\n' "$content" > "${home}/.codex/hooks.json"
  HOME="$home" DEPLOYED_ARTIFACTS_LOG="${home}/deploy.log" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type hook --target codex \
    >"${home}/stdout" 2>"${home}/stderr"
  printf '%s' "$?"
}

assert_case() { # name, hooks-json, expected-hooks-json -> asserts both outcomes
  local name="$1"
  local content="$2"
  local want="$3"
  local home="${SCRATCH}/${name}"
  local rc
  rc="$(run_case "$name" "$content")"
  [[ "$rc" == "0" ]] ||
    fail "${name}: the deploy must exit 0 over a foreign hook shape, got ${rc}: $(cat "${home}/stderr")"
  local got
  got="$(jq -c '.hooks' "${home}/.codex/hooks.json")" ||
    fail "${name}: the written hooks.json must still parse as JSON"
  [[ "$got" == "$want" ]] ||
    fail "${name}: the deploy must preserve the foreign hooks value (got='${got}' want='${want}')"
}

# An object whose event values are not arrays: no event is mergeable, so the
# whole value stays as it was. Pre-fix this reached ident() with an object.
assert_case nonlist '{"hooks":{"PreToolUse":{"matcher":"x"}}}' \
  '{"PreToolUse":{"matcher":"x"}}'

# A hooks value that is an array rather than an object. Pre-fix this reached
# .[$event] on an array and failed.
assert_case array '{"hooks":[{"matcher":"x"}]}' '[{"matcher":"x"}]'

# A hooks value that is a string, with a sibling top-level key.
assert_case string '{"other":1,"hooks":"hand-edited"}' '"hand-edited"'

# An event list holding a non-object member is not an entry list either.
assert_case junk '{"hooks":{"PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]},"hand-edited"]}}' \
  '{"PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]},"hand-edited"]}'

# The deploy keeps going past the foreign file, so the artifact after it lands.
[[ -f "${SCRATCH}/nonlist/.codex/hooks/charter_guardrail.sh" ]] ||
  fail "the deploy must still install the hook script that follows the foreign config"

printf 'Hook merge foreign-shape reproduction passed\n'
