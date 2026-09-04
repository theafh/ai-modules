#!/usr/bin/env bash
# The pull request already carries one comment from this reviewer, so a
# correction edits that post rather than adding a second one.

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
printf 'def convert(rows):\n    return rows\n\n\ndef export(rows):\n    return list(rows)\n' > src/convert.py
git add -A
git commit --quiet -m "src/convert.py -> add an export helper beside convert"
git push --quiet -u origin feature/export
head_oid="$(git rev-parse HEAD)"

payloads="$target/payloads"
default_pr_payloads "$payloads" "$head_oid"
cat > "$payloads/comments.json" <<JSON
{
  "comments": [
    {
      "id": "IC_reviewer_1",
      "url": "https://github.com/acme/widget/pull/7#issuecomment-1",
      "author": {"login": "reviewer"},
      "body": "Reviewed \`$head_oid\`.\\n\\n## Bugs it may introduce\\n\\n- src/convert.py: export() copies the list on every call, which doubles peak memory for large inputs.",
      "createdAt": "2026-08-30T12:00:00Z"
    }
  ]
}
JSON
install_gh_stub "$target" "$payloads" >/dev/null
write_gh_env "$target" "$payloads" reviewer
printf '%s\n' "$repo"
