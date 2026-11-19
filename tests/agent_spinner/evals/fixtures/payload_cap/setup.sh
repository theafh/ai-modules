#!/usr/bin/env bash
# payload_cap: helper reports exceed the stated payload cap. The synthesis
# brief carries the truncation notice and the digest lists the trimmed
# identifiers, or it relays the returns by path with a read-in-full
# instruction. One load-bearing finding sits past the cap, so the orchestrator
# must read it from the source and dispose of it. The corpus is coherent: every
# docs page documents --jobs, bin/tool.sh accepts --workers and rejects --jobs,
# and docs/gamma.md carries the quoted legacy line the finding anchors to.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs" "$proj/bin"

# The command every page describes. It takes --workers and rejects --jobs, so
# the pages' --jobs examples are a real drift and the legacy form is a real
# unsupported flag.
cat > "$proj/bin/tool.sh" <<'TOOL'
#!/usr/bin/env bash
# tool.sh — the one command every docs page describes.
set -euo pipefail
usage() { echo "usage: tool.sh {alpha|beta|gamma} --workers <n>" >&2; exit 2; }
[ $# -ge 3 ] || usage
case "$1" in alpha|beta|gamma) ;; *) usage ;; esac
case "$2" in
  --workers) ;;
  --jobs)
    echo "tool.sh: --jobs is not accepted; use --workers" >&2
    exit 2
    ;;
  *) usage ;;
esac
case "$3" in ''|*[!0-9]*) usage ;; esac
echo "ran $1 with --workers $3"
TOOL
chmod +x "$proj/bin/tool.sh"

for name in alpha beta; do
  printf '# %s\n\nRun `tool.sh %s --jobs 4`.\n' "$name" "$name" > "$proj/docs/$name.md"
done

# gamma carries both the current-form example and the retired --jobs 8 line
# under its own heading, which is the finding the synthesis must dispose of.
cat > "$proj/docs/gamma.md" <<'PAGE'
# gamma

Run `tool.sh gamma --jobs 4`.

# legacy

Run `tool.sh gamma --jobs 8` for the legacy path.
PAGE

commit_tree "$proj"
run_ledger "$proj" init --phase survey --bound 240 \
  --unit survey:alpha --unit survey:beta --unit survey:gamma \
  --unit synthesis:survey >/dev/null
for label in survey:alpha survey:beta survey:gamma; do
  stage_row "$proj" "$label" "Survey docs/${label#survey:}.md against bin/tool.sh."
done

for name in alpha beta; do
  python3 - "$proj/.extras-$name.json" "$name" <<'PY'
import json, sys
path, name = sys.argv[1], sys.argv[2]
extras = {
    "_prose": "survey:%s — 1 finding." % name,
    "notes": "read the heading, the example block, and the flag list again.\n" * 240,
    "findings": [
        {"claim": "docs/%s.md documents --jobs; the command takes --workers." % name,
         "severity": "major",
         "quote": "Run `tool.sh %s --jobs 4`." % name,
         "anchor": "docs/%s.md, under \"# %s\"" % (name, name)},
    ],
}
json.dump(extras, open(path, "w"))
PY
  write_return "$proj" "survey:$name" "done" fail "@$proj/.extras-$name.json"
done

python3 - "$proj/.extras-gamma.json" <<'PY'
import json, sys
extras = {
    "_prose": "survey:gamma — 2 findings.",
    "notes": "read the heading, the example block, and the flag list again.\n" * 240,
    "findings": [
        {"claim": "docs/gamma.md documents --jobs; the command takes --workers.",
         "severity": "major",
         "quote": "Run `tool.sh gamma --jobs 4`.",
         "anchor": "docs/gamma.md, under \"# gamma\""},
        {"claim": "LOADBEARING: docs/gamma.md also documents a retired --jobs=8 form that the command rejects outright.",
         "severity": "blocker",
         "quote": "Run `tool.sh gamma --jobs 8` for the legacy path.",
         "anchor": "docs/gamma.md, under \"# legacy\""},
    ],
}
json.dump(extras, open(sys.argv[1], "w"))
PY
write_return "$proj" survey:gamma "done" fail "@$proj/.extras-gamma.json"
rm -f "$proj/.extras-alpha.json" "$proj/.extras-beta.json" "$proj/.extras-gamma.json"

seal_open_run "$target" "$proj"
echo "payload_cap sandbox staged at $proj"
