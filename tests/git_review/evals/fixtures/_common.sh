#!/usr/bin/env bash
# Shared fixture helpers for the git_review behavioral evals.
#
# Staged remotes reuse the git_checkout fixture helpers rather than restating
# them, so both harnesses stage bare origins and clones the same way. This file
# adds the git_review-specific helpers on top: the stub `gh`, the guardrail and
# workflow scaffolding, and the seeded-defect writers.

set -euo pipefail

_COMMON_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../../git_checkout/evals/fixtures/_common.sh
. "$_COMMON_HERE/../../../git_checkout/evals/fixtures/_common.sh"

# --- stub gh -----------------------------------------------------------------

# Install a stub `gh` that serves fixture JSON and appends every invocation to a
# log, so an eval can assert both what the run read and what it refrained from
# posting. The stub goes in $root/bin, and the caller puts that directory first
# on PATH for the worker.
#
# Usage: install_gh_stub <fixture_root> <payload_dir>
#   payload_dir holds the JSON the stub serves, named by the gh surface:
#     pr.json comments.json reviews.json statusCheckRollup.json
#     review_threads_page1.json review_threads_page2.json rulesets.json
install_gh_stub() {
    local root=$1 payloads=$2
    mkdir -p "$root/bin"

    cat > "$root/bin/gh" <<'GH_STUB'
#!/usr/bin/env bash
# Stub gh for the git_review evals. Serves fixture JSON from $GH_STUB_PAYLOADS
# and records every invocation, one line per call, in $GH_STUB_LOG.
set -uo pipefail

LOG="${GH_STUB_LOG:?GH_STUB_LOG is required}"
PAYLOADS="${GH_STUB_PAYLOADS:?GH_STUB_PAYLOADS is required}"

printf '%s\n' "$*" >> "$LOG"

serve() {
    local file="$PAYLOADS/$1"
    if [[ -f "$file" ]]; then
        cat "$file"
        return 0
    fi
    printf '{}\n'
}

case "${1:-}" in
  auth)
    exit 0
    ;;
  pr)
    case "${2:-}" in
      view)
        # Serve one payload per --json field group, matching what the skill asks for.
        if [[ "$*" == *"--json comments"* ]]; then serve comments.json
        elif [[ "$*" == *"--json reviews"* ]]; then serve reviews.json
        elif [[ "$*" == *"statusCheckRollup"* ]]; then serve statusCheckRollup.json
        else serve pr.json
        fi
        ;;
      comment|review)
        printf 'https://github.com/acme/widget/pull/7#issuecomment-stub\n'
        ;;
      *) printf '{}\n' ;;
    esac
    ;;
  api)
    if [[ "$*" == *" user"* || "$*" == "api user" ]]; then
      printf '{"login":"%s"}\n' "${GH_STUB_LOGIN:-reviewer}"
    elif [[ "$*" == *"resolveReviewThread"* ]]; then
      # Every mutation branch sits ahead of the read-query branch below, which
      # matches any "query=" and would otherwise answer a mutation with thread
      # JSON. A caller that reads thread JSON back from its mutation retries,
      # which is the same confusion the strictness inside each branch prevents.
      #
      # Require a properly formed mutation. Matching the bare substring would
      # report success for a malformed call too, which hides a caller that is
      # retrying because it never got a usable answer.
      if [[ "$*" == *"-f query="*"mutation"* ]]; then
        printf '{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}\n'
      else
        printf 'gh: expected a GraphQL mutation via -f query=\n' >&2
        exit 1
      fi
    elif [[ "$*" == *"updateIssueComment"* ]]; then
      # The node-id route for editing a comment already posted, held to the same
      # well-formed-mutation standard as resolveReviewThread above.
      if [[ "$*" == *"-f query="*"mutation"* ]]; then
        printf '{"data":{"updateIssueComment":{"issueComment":{"id":"IC_reviewer_1"}}}}\n'
      else
        printf 'gh: expected a GraphQL mutation via -f query=\n' >&2
        exit 1
      fi
    elif [[ "$*" == *"reviewThreads"* || "$*" == *"query="* ]]; then
      # Match the cursor ARGUMENT, not the word "cursor" inside the query text:
      # the query declares $cursor and passes it to after:, so a loose match
      # would serve page 2 on the very first call.
      if [[ "$*" == *"-F cursor="* ]]; then serve review_threads_page2.json
      else serve review_threads_page1.json
      fi
    elif [[ "$*" == *"rulesets"* ]]; then
      serve rulesets.json
    elif [[ "$*" == *"issues/comments/"* ]]; then
      # The REST comment-edit route takes the numeric id carried in the comment
      # url's "#issuecomment-<n>" fragment. Answer an "IC_"-prefixed node id the
      # way the real forge does, so a caller that mixed the GraphQL id into the
      # REST path learns it here instead of passing on a call GitHub rejects.
      if [[ "$*" =~ issues/comments/[0-9]+([[:space:]]|$) ]]; then
        serve api.json
      else
        printf 'gh: Not Found (HTTP 404) - issues/comments takes the numeric comment id; the IC_ node id belongs to updateIssueComment\n' >&2
        exit 1
      fi
    else
      serve api.json
    fi
    ;;
  *)
    printf '{}\n'
    ;;
esac
GH_STUB
    chmod +x "$root/bin/gh"

    mkdir -p "$payloads"
    : > "$root/gh_calls.log"
    printf '%s\n' "$root/bin"
}

# Write the env file the runner reads. Plain KEY=VALUE lines, no expansion: the
# runner prepends GH_STUB_BIN to its own PATH and passes the rest through.
write_gh_env() {
    local root=$1 payloads=$2 login=${3:-reviewer}
    cat > "$root/gh_env" <<ENV
GH_STUB_BIN=$root/bin
GH_STUB_LOG=$root/gh_calls.log
GH_STUB_PAYLOADS=$payloads
GH_STUB_LOGIN=$login
ENV
}

# The baseline payload set every forge fixture starts from. A fixture overwrites
# whichever file it needs to differ.
default_pr_payloads() {
    local payloads=$1 head_oid=$2
    mkdir -p "$payloads"

    cat > "$payloads/pr.json" <<JSON
{
  "number": 7,
  "title": "Add the export command",
  "body": "Adds an export command and retires the legacy format table.",
  "headRefName": "feature/export",
  "baseRefName": "main",
  "headRefOid": "$head_oid",
  "state": "OPEN",
  "isDraft": false,
  "mergeable": "MERGEABLE",
  "mergeStateStatus": "CLEAN",
  "reviewDecision": null,
  "additions": 40,
  "deletions": 12,
  "changedFiles": 3
}
JSON

    cat > "$payloads/comments.json" <<'JSON'
{
  "comments": [
    {"author": {"login": "author"}, "body": "Ready for a look.", "createdAt": "2026-08-30T09:00:00Z"}
  ]
}
JSON

    cat > "$payloads/reviews.json" <<'JSON'
{
  "reviews": [
    {"author": {"login": "peer"}, "state": "COMMENTED", "body": "One question on the retry budget.", "submittedAt": "2026-08-30T10:00:00Z"}
  ]
}
JSON

    cat > "$payloads/statusCheckRollup.json" <<'JSON'
{
  "statusCheckRollup": [
    {"name": "ci / check", "status": "COMPLETED", "conclusion": "SUCCESS"},
    {"name": "ci / lint", "status": "COMPLETED", "conclusion": "SUCCESS"}
  ]
}
JSON

    cat > "$payloads/review_threads_page1.json" <<'JSON'
{
  "data": {
    "repository": {
      "pullRequest": {
        "reviewThreads": {
          "pageInfo": {"hasNextPage": false, "endCursor": null},
          "nodes": [
            {
              "id": "T_open_retry",
              "isResolved": false,
              "isOutdated": false,
              "path": "src/export.py",
              "line": 24,
              "comments": {
                "pageInfo": {"hasNextPage": false, "endCursor": null},
                "nodes": [
                  {"author": {"login": "peer"}, "body": "Is 3 the right retry budget here?", "createdAt": "2026-08-30T10:01:00Z"}
                ]
              }
            }
          ]
        }
      }
    }
  }
}
JSON

    cat > "$payloads/rulesets.json" <<'JSON'
[]
JSON
}

# --- repository scaffolding --------------------------------------------------

# A minimal CI workflow naming one gate, so the gate list has a first source.
plant_workflow() {
    local repo=$1 gate_command=$2
    mkdir -p "$repo/.github/workflows"
    cat > "$repo/.github/workflows/ci.yml" <<YML
name: ci
on: [push, pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: tests
        run: $gate_command
YML
}

# A documented local entry point, so the gate list has a second source.
plant_makefile() {
    local repo=$1 gate_command=$2
    cat > "$repo/Makefile" <<MK
.PHONY: help test
help:
	@echo "test - run the project test suite"
test:
	$gate_command
MK
}

# Present the origin remote as a github.com repository, so the forge layer's
# GitHub test matches, while every fetch and push still travels to the local
# bare repository through an insteadOf rewrite. `git remote -v` prints the
# configured URL rather than the rewritten one, which is what the test reads.
make_remote_look_like_github() {
    local repo=$1 bare=$2
    (
        cd "$repo"
        git config "url.$bare.insteadOf" "https://github.com/acme/widget.git"
        git remote set-url origin "https://github.com/acme/widget.git"
    )
}

plant_guardrails() {
    local repo=$1
    cat > "$repo/CHARTER.md" <<'MD'
# Widget Charter

## Core Purpose

Widget is a command-line converter. Its product is the converter binary.

## DOES / DOES NOT Domain Boundaries

### DOES

- Convert files between the formats the converter declares.
- Read and write on the local filesystem only.

### DOES NOT

- Open a network connection of any kind. Widget runs offline by design, and a
  network call is outside the boundary this charter sets.
- Store user data outside the directory the caller named.
MD
    cat > "$repo/TESTING.md" <<'MD'
# Widget Testing

Every new public function ships with a unit test in `tests/` named after it.
A change that adds a public function without that test diverges from this doc.
MD
    cat > "$repo/SECURITY.md" <<'MD'
# Widget Security

Read every input path through the sanitizer in `src/paths.py` before opening it.
A direct `open()` on caller-supplied input diverges from this doc.
MD
    cat > "$repo/ARCHITECTURE.md" <<'MD'
# Widget Architecture

## Direction

The converter is moving toward a plugin registry so formats can be added without
editing the core. Today the formats are a hardcoded table; that is the current
state rather than a defect.
MD
}

plant_standing_instructions() {
    local repo=$1 body=$2
    printf '%s\n' "$body" > "$repo/AGENTS.md"
}

# A file long enough that a sampling reader would miss its tail.
plant_long_file() {
    local path=$1 lines=$2 tail_line=$3
    local i
    mkdir -p "$(dirname "$path")"
    : > "$path"
    for ((i = 1; i <= lines; i++)); do
        printf 'def helper_%05d(value):\n    return value + %d\n\n' "$i" "$i" >> "$path"
    done
    printf '%s\n' "$tail_line" >> "$path"
}

# Push one more commit onto an existing branch from a throwaway clone, so the
# fixture's own clone falls behind its remote without touching its worktree.
push_commit_from_side() {
    local bare=$1 branch=$2 file=$3 content=$4 message=$5
    local work

    work="$(mktemp -d)"
    git clone --quiet "$bare" "$work/side" 2>/dev/null
    (
        cd "$work/side"
        setup_identity
        git checkout --quiet "$branch"
        printf '%s\n' "$content" > "$file"
        git add "$file"
        git commit --quiet -m "$message"
        git push --quiet origin "$branch"
    )
    rm -rf "$work"
}
