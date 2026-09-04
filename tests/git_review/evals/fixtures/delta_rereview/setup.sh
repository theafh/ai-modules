#!/usr/bin/env bash
# A branch that has already been reviewed once. The stub gh serves that prior
# review body, the author's newer replies, and one inline thread, while the tree
# carries the state each tag has to read: one finding fixed, one claimed without
# a code change, one acknowledged but unfixed, one declined with a reason, one
# settled by a recorded decision, one regressed, and one new.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p src docs
cat > docs/decisions.md <<'MD'
# Decisions

## Retry budget, decided 2026-08-28 by the module owner

Retries stay in the transport layer, not in the export path. The export helper
takes whatever the transport hands it and does not retry on its own.
MD
cat > src/paths.py <<'PY'
def sanitize(path):
    """Every caller-supplied path passes through here before it is opened."""
    return path.replace("..", "")
PY
printf 'def convert(rows):\n    return rows\n' > src/convert.py
git add -A
git commit --quiet -m "seed converter, sanitizer, and the decisions log"
git push --quiet origin main
make_remote_look_like_github "$repo" "$target/origin.git"

git checkout --quiet -b feature/export

# The state the first review saw.
cat > src/export.py <<'PY'
from .paths import sanitize


def export(rows, destination):
    handle = open(sanitize(destination), "w")
    for i in range(len(rows)):
        handle.write(str(rows[i]) + str(rows[i + 1]))


def chunk(rows):
    return [rows[i:i + 512] for i in range(0, len(rows), 512)]


def doExport(rows, destination):
    return export(rows, destination)
PY
git add -A
git commit --quiet -m "src/export.py -> add the export path reviewed in the first round"
git push --quiet -u origin feature/export
first_round="$(git rev-parse HEAD)"

# The author's follow-up commit, which is what the delta run reviews.
cat > src/export.py <<'PY'
def export(rows, destination):
    """Write rows to destination."""
    # f1 closed: the handle is closed now.
    with open(destination, "w") as handle:
        # f2 still open: the author's reply claims this was fixed; it was not.
        for i in range(len(rows)):
            handle.write(str(rows[i]) + str(rows[i + 1]))

    # f6 regressed: sanitize() guarded this path in the first round and the
    # import is gone again, so destination reaches open() unchecked.
    return destination


def chunk(rows):
    # f3 acknowledged and still unfixed: 512 remains unexplained.
    return [rows[i:i + 512] for i in range(0, len(rows), 512)]


def doExport(rows, destination):
    # f4 declined with a reason: the author keeps the camelCase alias for the
    # external callers that already import it.
    return export(rows, destination)


def flush(handle):
    """Flush pending writes.

    New in this round: the caller may pass None when nothing was buffered, and
    this dereferences it unconditionally.
    """
    handle.flush()


# A prose concession beside the code change: the note below acknowledges the
# gap without closing it.
# TODO: route export() through paths.sanitize before the next release.
PY
git add -A
git commit --quiet -m "src/export.py -> close the handle, add a flush helper, and note the sanitize gap"
git push --quiet origin feature/export
head_oid="$(git rev-parse HEAD)"

payloads="$target/payloads"
default_pr_payloads "$payloads" "$head_oid"
printf '%s\n' "$first_round" > "$target/.first_round_sha"

cat > "$payloads/reviews.json" <<JSON
{
  "reviews": [
    {
      "author": {"login": "reviewer"},
      "state": "COMMENTED",
      "submittedAt": "2026-08-29T12:00:00Z",
      "body": "Reviewed \`$first_round\`.\\n\\n## What is critical\\n\\n- f6 src/export.py: destination reaches open() without passing paths.sanitize.\\n\\n## Bugs it may introduce\\n\\n- f1 src/export.py: the file handle is never closed.\\n- f2 src/export.py: rows[i + 1] walks one past the end on the last iteration.\\n\\n## What should be fixed though it is not a clear bug\\n\\n- f3 src/export.py: the 512 chunk size is unexplained.\\n- f4 src/export.py: doExport is camelCase among snake_case siblings.\\n\\n## Decisions the implementer must make before fixing\\n\\n- f5 Does export() retry on a failed write, or does the transport own retries?\\n- f9 Routed to the security owner: is sanitize() sufficient for absolute paths?"
    },
    {
      "author": {"login": "author"},
      "state": "COMMENTED",
      "submittedAt": "2026-08-30T09:30:00Z",
      "body": "Pushed a follow-up. f1 and f2 are both handled now."
    }
  ]
}
JSON

cat > "$payloads/comments.json" <<'JSON'
{
  "comments": [
    {"author": {"login": "author"}, "body": "f3: fair, the 512 is arbitrary. Leaving it for now, I will document it.", "createdAt": "2026-08-30T09:31:00Z"},
    {"author": {"login": "author"}, "body": "f4: keeping doExport. Two external callers import that name and I am not breaking them in this release.", "createdAt": "2026-08-30T09:32:00Z"},
    {"author": {"login": "author"}, "body": "f5: the decisions log settles this. Retries stay in the transport.", "createdAt": "2026-08-30T09:33:00Z"}
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
              "id": "T_f9_security",
              "isResolved": false,
              "isOutdated": false,
              "path": "src/export.py",
              "line": 4,
              "comments": {
                "pageInfo": {"hasNextPage": false, "endCursor": null},
                "nodes": [
                  {"author": {"login": "reviewer"}, "body": "f9 @security-owner: is sanitize() sufficient for absolute paths?", "createdAt": "2026-08-29T12:01:00Z"}
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

install_gh_stub "$target" "$payloads" >/dev/null
write_gh_env "$target" "$payloads" reviewer
printf '%s\n' "$repo"
