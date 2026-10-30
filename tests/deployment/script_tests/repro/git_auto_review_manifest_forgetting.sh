#!/usr/bin/env bash
# Reproduction for the git_auto_review round-3 finding on the entry-grain hook
# merge: an event value that became foreign while still holding an entry the
# recorded @entries: manifest names must not be read as wholly unowned.
#
# Two routes lose the entry on the pre-fix script:
#   1. A redeploy over the hand-edited event rewrites the manifest to
#      @entries:[], forgetting the owned entry.
#   2. An uninstall over the hand-edited event reports success, deletes the
#      hook script, and drops the log line while the owned entry stays.
#
# Fails on the pre-fix deployment script and passes after the guard.
#
# Usage:
#   bash tests/deployment/script_tests/repro/git_auto_review_manifest_forgetting.sh
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

deploy() { # home -> exit code
  local home="$1"
  HOME="$home" DEPLOYED_ARTIFACTS_LOG="${home}/deploy.log" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type hook --target codex \
    >"${home}/deploy.out" 2>"${home}/deploy.err"
}

uninstall() { # home -> exit code
  local home="$1"
  HOME="$home" DEPLOYED_ARTIFACTS_LOG="${home}/deploy.log" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --uninstall \
    >"${home}/uninstall.out" 2>"${home}/uninstall.err"
}

# The identity the deploy recorded for its own entry in a destination's
# @entries: manifest. Reading it from the manifest is what makes this
# independent of any foreign entry the user's file already holds.
manifest_identity() { # deploy.log -> identity string
  awk -F'\t' '$1 ~ /hooks\.json\[hooks\]$/ {print $5}' "$1" | tail -1 \
    | sed -e 's/^@entries://' \
    | jq -r '.[0].identity // ""' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Route 1: a redeploy over a hand-edited event must not forget the entry.
# ---------------------------------------------------------------------------
R1="${SCRATCH}/route1"
mkdir -p "${R1}/.codex"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]}]}}' \
  > "${R1}/.codex/hooks.json"

deploy "$R1" || fail "route1: the initial deploy must succeed"
manifest_after_deploy="$(awk -F'\t' '$1 ~ /hooks\.json\[hooks\]$/ {print $5}' "${R1}/deploy.log" | tail -1)"
case "$manifest_after_deploy" in
  '@entries:'*) ;;
  *) fail "route1: the deploy must record an @entries: manifest, got '${manifest_after_deploy}'" ;;
esac
identity="$(manifest_identity "${R1}/deploy.log")"
[[ -n "$identity" ]] || fail "route1: the deploy must install ai-modules' entry"

# The user appends a non-object member, so the event value is no longer a clean
# entry list while still holding the owned entry.
jq '.hooks.PreToolUse += ["hand-edited"]' "${R1}/.codex/hooks.json" > "${R1}/tmp" \
  && mv "${R1}/tmp" "${R1}/.codex/hooks.json"

deploy "$R1" || fail "route1: the redeploy over a hand-edited event must succeed"

manifest_after_redeploy="$(awk -F'\t' '$1 ~ /hooks\.json\[hooks\]$/ {print $5}' "${R1}/deploy.log" | tail -1)"
[[ "$manifest_after_redeploy" == *"$identity"* ]] ||
  fail "route1: the redeploy must keep the owned entry in its manifest, got '${manifest_after_redeploy}'"

# ---------------------------------------------------------------------------
# Route 2: an uninstall over a hand-edited event must not claim a removal it
# did not make, and must not delete a script the owned entry still references.
# ---------------------------------------------------------------------------
R2="${SCRATCH}/route2"
mkdir -p "${R2}/.codex"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]}]}}' \
  > "${R2}/.codex/hooks.json"

deploy "$R2" || fail "route2: the initial deploy must succeed"
identity2="$(manifest_identity "${R2}/deploy.log")"
[[ -n "$identity2" ]] || fail "route2: the deploy must install ai-modules' entry"

# No redeploy: the manifest still names the entry, and the user's edit makes the
# event value foreign.
jq '.hooks.PreToolUse += ["hand-edited"]' "${R2}/.codex/hooks.json" > "${R2}/tmp" \
  && mv "${R2}/tmp" "${R2}/.codex/hooks.json"
cp "${R2}/deploy.log" "${R2}/deploy.log.before"

uninstall "$R2" || true

if rg -q "removed .*hooks\.json" "${R2}/uninstall.out" 2>/dev/null; then
  fail "route2: the uninstall must not report a removal over an entry it left in place"
fi

remaining_entry="$(jq -r --arg id "$identity2" '
  [.hooks.PreToolUse[]? | select(type == "object")
   | [.hooks[]? | (.command // empty)] | unique | sort | join("\u0001")
   | select(. == $id)] | length' "${R2}/.codex/hooks.json")"

if [[ "$remaining_entry" == "1" ]]; then
  grep -q "$identity2" "${R2}/deploy.log" ||
    fail "route2: the log line must survive while the owned entry is still present"
  [[ -f "${R2}/.codex/hooks/charter_guardrail.sh" ]] ||
    fail "route2: the hook script must survive while the owned entry references it"
fi

# ---------------------------------------------------------------------------
# The behaviour round 2 established must not regress: an event replaced
# wholesale holds no owned entry, so the uninstall reports success and drops
# its line.
# ---------------------------------------------------------------------------
R3="${SCRATCH}/route3"
mkdir -p "${R3}/.codex"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]}]}}' \
  > "${R3}/.codex/hooks.json"

deploy "$R3" || fail "route3: the initial deploy must succeed"

# The user replaces the whole event value with a string: no owned entry remains.
jq '.hooks.PreToolUse = "hand-edited"' "${R3}/.codex/hooks.json" > "${R3}/tmp" \
  && mv "${R3}/tmp" "${R3}/.codex/hooks.json"

uninstall "$R3" || fail "route3: the uninstall over a wholesale replacement must succeed"
rg -q "failed" "${R3}/uninstall.out" 2>/dev/null &&
  fail "route3: a wholesale replacement must not report failure"
[[ "$(jq -r '.hooks.PreToolUse' "${R3}/.codex/hooks.json")" == "hand-edited" ]] ||
  fail "route3: the user's replacement value must be preserved"

printf 'Hook manifest-forgetting reproduction passed\n'
