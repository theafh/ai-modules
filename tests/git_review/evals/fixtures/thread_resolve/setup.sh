#!/usr/bin/env bash
# Two inline review threads: one whose finding the tree has since closed, and
# one whose finding still stands, so a resolve instruction reaches exactly one
# of them.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p src
printf 'def convert(rows):\n    return rows\n' > src/convert.py
git add -A
git commit --quiet -m "seed converter"
git push --quiet origin main
make_remote_look_like_github "$repo" "$target/origin.git"

git checkout --quiet -b feature/export
cat > src/export.py <<'PY'
def export(rows, destination):
    """Write rows to destination."""
    # Thread T_closed_handle asked for this; the handle is closed now.
    with open(destination, "w") as handle:
        for i in range(len(rows)):
            handle.write(str(rows[i]) + str(rows[i + 1]))
    return destination
PY
git add -A
git commit --quiet -m "src/export.py -> add the export path with a managed file handle"
git push --quiet -u origin feature/export
head_oid="$(git rev-parse HEAD)"

payloads="$target/payloads"
default_pr_payloads "$payloads" "$head_oid"
cat > "$payloads/review_threads_page1.json" <<'JSON'
{
  "data": {
    "repository": {
      "pullRequest": {
        "reviewThreads": {
          "pageInfo": {"hasNextPage": false, "endCursor": null},
          "nodes": [
            {
              "id": "T_closed_handle",
              "isResolved": false,
              "isOutdated": false,
              "path": "src/export.py",
              "line": 4,
              "comments": {
                "pageInfo": {"hasNextPage": false, "endCursor": null},
                "nodes": [
                  {"author": {"login": "reviewer"}, "body": "The file handle is never closed.", "createdAt": "2026-08-29T12:00:00Z"}
                ]
              }
            },
            {
              "id": "T_open_offbyone",
              "isResolved": false,
              "isOutdated": false,
              "path": "src/export.py",
              "line": 6,
              "comments": {
                "pageInfo": {"hasNextPage": false, "endCursor": null},
                "nodes": [
                  {"author": {"login": "reviewer"}, "body": "rows[i + 1] walks one past the end on the last iteration.", "createdAt": "2026-08-29T12:01:00Z"}
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
